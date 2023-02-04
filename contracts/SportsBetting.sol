//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "./mock/IERC20.sol";
import "./SportsOracleConsumer.sol";
import "./SportsBettingLib.sol";

contract SportsBetting is SportsOracleConsumer {

    enum BettingState {
        CLOSED,
        OPENING,
        OPEN,
        AWAITING,
        PAYABLE,
        CANCELLED
    }

    struct FixtureEnrichment {
        BettingState fixtureState;
        uint256[3] total;
        uint256[3] user;
    }

    event BettingStateChanged(string fixtureID, BettingState state);

    event BetStaked(
        address indexed better,
        string fixtureID,
        uint256 amount,
        SportsBettingLib.FixtureResult betType
    );

    event BetUnstaked(
        address indexed better,
        string fixtureID,
        uint256 amount,
        SportsBettingLib.FixtureResult betType
    );

    event BetPayoutFulfillmentError(string fixtureID, string reason);

    event BetPayout(address indexed better, string fixtureID, uint256 amount);

    event BetCommissionPayout(string indexed fixtureID, uint256 amount);

    event KickoffTimeUpdated(string fixtureID, uint256 kickoffTime);

    SportsBettingLib.FixtureResult[5] public betTypes;

    // Contract owner
    address public immutable owner;

    // DAI Stablecoin address
    address public immutable daiAddress;

    // Entrance fee of 0.0001 DAI (10^14 Wei)
    uint256 public constant ENTRANCE_FEE = 10**14;

    // Commission rate percentage taken by contract owner for each payout as a percentage
    uint256 public constant COMMISSION_RATE = 1;

    // Max time before a fixture kick-off that a bet can be placed in seconds
    // A fixture bet state will not move to OPEN before a time to the left of the
    // ko time equal to BET_ADVANCE_TIME
    uint256 public constant BET_ADVANCE_TIME = 7 days; // 7 days

    // Cut off time for bets before KO time in seconds
    // i.e. all bets must be placed at time t where t < koTime - BET_CUTOFF_TIME
    uint256 public constant BET_CUTOFF_TIME = 90 minutes; // 90 minutes

    // Map each fixture ID to whether betting is open for this fixture
    mapping(string => BettingState) public bettingState;

    // Map each fixture ID to a map of FixtureResult to a map of address to uint representing the amount of wei bet on that result
    mapping(string => mapping(SportsBettingLib.FixtureResult => mapping(address => uint256)))
        public amounts;

    // Map each fixture ID to a map of FixtureResult to a uint representing the total amount of wei bet on that result
    mapping(string => mapping(SportsBettingLib.FixtureResult => uint256))
        public totalAmounts;

    // Map each fixture ID to a map of address to amount the ctx paid the address owner for that fixture
    mapping(string => mapping(address => uint256)) public payouts;

    // Map each user address to fixture ID to boolean representing whether they were paid for a fixture
    mapping(string => mapping(address => bool)) public userWasPaid;

    // Map oracle request ID for fixture kickoff time request to corresponding fixture ID
    mapping(bytes32 => string) public requestKickoffToFixture;

    // Map each fixture ID to unix timestamp for its kickoff time
    mapping(string => uint256) public fixtureToKickoffTime;

    // Map oracle request ID for fixture result request to corresponding fixture ID
    mapping(bytes32 => string) public requestResultToFixture;

    // Map fixture ID to fixture result
    mapping(string => SportsBettingLib.FixtureResult) public results;

    // Commission total taken by contract owner indexed by fixture
    mapping(string => uint256) public commissionMap;

    // Map of fixture ID to whether commission was paid to owner for this fixture
    mapping(string => bool) public commissionPaid;

    // Map each fixture ID to a map of FixtureResult to an array of all addresses that have ever placed
    // bets for that fixture-result pair
    mapping(string => mapping(SportsBettingLib.FixtureResult => address[])) public historicalBetters;

    // We want to store unique addresses in historicalBetters mapping.
    // Solidity has no native set type, so we keep a mapping of address to fixture type to bet type
    // to index in historicalBetters
    // We only append an address to historicalBetters if it does not have an existing index
    mapping(string => mapping(SportsBettingLib.FixtureResult => mapping(address => uint256)))
        public historicalBettersIndex;

    // activeBetters represents all addresses who currently have an amount staked on a fixture-result
    // The mapping(address => bool) pattern allows us to set address to true or false if an address
    // stakes/unstakes for that bet, and allows safer 'contains' methods on the betters
    mapping(string => mapping(SportsBettingLib.FixtureResult => mapping(address => bool)))
        public activeBetters;

    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _dai,
        address _link,
        string memory _jobId,
        uint256 _fee
    ) SportsOracleConsumer(_sportsOracleURI, _oracle, _link, _jobId, _fee) {
        betTypes[0] = SportsBettingLib.FixtureResult.DEFAULT;
        betTypes[1] = SportsBettingLib.FixtureResult.CANCELLED;
        betTypes[2] = SportsBettingLib.FixtureResult.HOME;
        betTypes[3] = SportsBettingLib.FixtureResult.DRAW;
        betTypes[4] = SportsBettingLib.FixtureResult.AWAY;

        owner = msg.sender;
        daiAddress = _dai;
    }

    // Wrapper for setting fixture betting state and emitting event
    function setFixtureBettingState(string memory fixtureID, BettingState state)
        internal
    {
        bettingState[fixtureID] = state;
        emit BettingStateChanged(fixtureID, state);

        // If we open a fixture, intialize ctx state vars
        if (state == BettingState.OPEN) {
            initializeHistoricalBetters(fixtureID);
        }
    }

    // closeBetForFixture closes fixture if it is
    // 1. Not currently closed AND
    // 2. eligible to be closed
    function closeBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] != BettingState.CLOSED,
            "Bet state is already CLOSED."
        );
        require(
            fixtureShouldBecomeClosed(fixtureID),
            "Fixture ineligible to be closed."
        );
        setFixtureBettingState(fixtureID, BettingState.CLOSED);
    }

    // openBetForFixture makes an API call to oracle. It is expected that this
    // call will return the kickoff_time and the fulfillFixtureKickoffTime func
    // will handle the state change to open
    // This is to ensure we don't open a bet until we have its KO time and
    // know that it advanced enough in the future
    function openBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] == BettingState.CLOSED || bettingState[fixtureID] == BettingState.OPENING,
            "State must be CLOSED or OPENING."
        );
        setFixtureBettingState(fixtureID, BettingState.OPENING);
        requestFixtureKickoffTime(fixtureID);
    }

    // Ideally the betting state will change from OPEN -> AWAITING
    // by virtue of a bet being placed too close to KO time, however
    // in the event this doesn't happen, this function can be called to
    // attempt to change state to AWAITING
    function awaitBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet state must be OPEN."
        );
        require(
            fixtureShouldBecomeAwaiting(fixtureID),
            "Fixture ineligible for AWAITING."
        );
        setFixtureBettingState(fixtureID, BettingState.AWAITING);
    }

    function fixtureShouldBecomeAwaiting(string memory fixtureID) internal view returns(bool) {
        uint256 ko = fixtureToKickoffTime[fixtureID];
        // OPEN -> AWAITING
        // If a bet is OPEN, it becomes AWAITING if
        // current time is more than BET_CUTOFF_TIME to the right of kickoff time
        return (
            bettingState[fixtureID] == BettingState.OPEN &&
            block.timestamp > ko - BET_CUTOFF_TIME
        );
    }

    function fixtureShouldBecomeOpen(string memory fixtureID) internal view returns(bool) {
        uint256 ko = fixtureToKickoffTime[fixtureID];
        // OPENING -> OPEN
        // If a bet is OPENING, it can be OPENed if
        // current time is more than BET_CUTOFF_TIME before kickoff time AND
        // current time is less than BET_ADVANCE_TIME before kickoff time
        return (
            ko == 0 ||
            (
                bettingState[fixtureID] == BettingState.OPENING &&
                block.timestamp <= ko - BET_CUTOFF_TIME &&
                block.timestamp >= ko - BET_ADVANCE_TIME
            )
        );
    }

    function fixtureShouldBecomeClosed(string memory fixtureID) internal view returns(bool) {
        uint256 ko = fixtureToKickoffTime[fixtureID];
        return (
            // OPENING -> CLOSED
            // If fixture is OPENING, it will become CLOSED if
            // current time is to the right of kickoff time - BET_CUTOFF_TIME
            // OR
            // current time is to the left of kickoff time - BET_ADVANCE_TIME
            bettingState[fixtureID] == BettingState.OPENING &&
            (block.timestamp > ko - BET_CUTOFF_TIME ||
                block.timestamp < ko - BET_ADVANCE_TIME)
        );
    }

    function stake(string memory fixtureID, SportsBettingLib.FixtureResult betType, uint256 amount) public {
        // Don't allow stakes if we should be in AWAITING state
        if (fixtureShouldBecomeAwaiting(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.AWAITING);
            return;
        }

        // Impose requirements
        require(
            betType != SportsBettingLib.FixtureResult.DEFAULT && betType != SportsBettingLib.FixtureResult.CANCELLED, 
            "This BetType is not permitted.");
        require(bettingState[fixtureID] == BettingState.OPEN, "Bet activity is not open.");
        require(amount >= ENTRANCE_FEE, "Amount is below entrance fee.");

        // Update state
        amounts[fixtureID][betType][msg.sender] += amount;
        totalAmounts[fixtureID][betType] += amount;
        addHistoricalBetter(fixtureID, betType, msg.sender);
        activeBetters[fixtureID][betType][msg.sender] = true;

        // Transfer DAI tokens
        emit BetStaked(msg.sender, fixtureID, amount, betType);
        IERC20 dai = IERC20(daiAddress);
        require(
            dai.transferFrom(msg.sender, address(this), amount),
            "Unable to transfer"
        );
    }

    // Removes all stake in fixtureID-FixtureResult combo
    function unstake(
        string memory fixtureID,
        SportsBettingLib.FixtureResult betType,
        uint256 amount
    ) public {
        // Don't allow stakes if we should be in AWAITING state
        if (fixtureShouldBecomeAwaiting(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.AWAITING);
            return;
        }

        // Impose requirements on unstake value
        require(bettingState[fixtureID] == BettingState.OPEN, "Bet activity is not open.");
        require(amount > 0, "Amount should exceed zero.");
        require(bettingState[fixtureID] == BettingState.OPEN, "Fixture is not in Open state.");

        // Impose requirements on user's stake if this unstake occurs
        uint256 amountStaked = amounts[fixtureID][betType][msg.sender];
        require(amountStaked > 0, "No stake on this address-result.");
        require(amount <= amountStaked, "Current stake too low.");
        // If this is a non-partial unstake, ensure ENTRANCE_FEE is maintained
        if (amountStaked > amount) {
            require(amountStaked - amount >= ENTRANCE_FEE, "Cannot go below entrance fee.");
        }

        // Update state
        amounts[fixtureID][betType][msg.sender] -= amount;
        totalAmounts[fixtureID][betType] -= amount;
        // If non-partial unstake, caller is no longer an active staker
        if (amounts[fixtureID][betType][msg.sender] <= 0) {
            activeBetters[fixtureID][betType][msg.sender] = false;
        }

        // Transfer DAI to msg sender
        emit BetUnstaked(msg.sender, fixtureID, amount, betType);
        IERC20 dai = IERC20(daiAddress);
        require(dai.transfer(msg.sender, amount), "Unable to unstake");
    }

    function requestFixtureKickoffTime(string memory fixtureID) public {
        bytes32 requestID = requestFixtureKickoffTimeParameter(fixtureID);
        requestKickoffToFixture[requestID] = fixtureID;
        emit RequestedFixtureKickoff(requestID, fixtureID);
    }

    function fulfillFixtureKickoffTime(bytes32 requestId, uint256 ko)
        internal
        override
    {
        string memory fixtureID = requestKickoffToFixture[requestId];
        emit RequestFixtureKickoffFulfilled(requestId, fixtureID, ko);

        updateKickoffTime(fixtureID, ko);
        if (fixtureShouldBecomeOpen(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.OPEN);
        } else if (fixtureShouldBecomeClosed(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.CLOSED);
        }
    }

    function updateKickoffTime(string memory fixtureID, uint256 ko) internal {
        if (ko != fixtureToKickoffTime[fixtureID]) {
            fixtureToKickoffTime[fixtureID] = ko;
            emit KickoffTimeUpdated(fixtureID, ko);
        }
    }

    function requestFixtureResult(string memory fixtureID) public {
        bytes32 requestID = requestFixtureResultParameter(fixtureID);
        requestResultToFixture[requestID] = fixtureID;
        emit RequestedFixtureResult(requestID, fixtureID);
    }

    function fulfillFixtureResult(bytes32 requestId, uint256 result)
        internal
        override
    {
        string memory fixtureID = requestResultToFixture[requestId];
        emit RequestFixtureResultFulfilled(requestId, fixtureID, result);

        SportsBettingLib.FixtureResult parsedResult = SportsBettingLib.getFixtureResultFromAPIResponse(result);
        if (parsedResult == SportsBettingLib.FixtureResult.DEFAULT) {
            string memory errorString = string.concat(
                "Error on fixture ",
                fixtureID,
                ": Unknown fixture result from API"
            );
            emit BetPayoutFulfillmentError(fixtureID, errorString);
            revert(errorString);
        }

        results[fixtureID] = parsedResult;

        // Only action on fixture result if we are in AWAITING
        if (bettingState[fixtureID] == BettingState.AWAITING) {
            if (parsedResult == SportsBettingLib.FixtureResult.CANCELLED) {
                setFixtureBettingState(fixtureID, BettingState.CANCELLED);
            } else {
                setFixtureBettingState(fixtureID, BettingState.PAYABLE);
            } 
        }
    }

    function withdrawPayout(string memory fixtureID)
        public
    {
        require(
            bettingState[fixtureID] == BettingState.PAYABLE || bettingState[fixtureID] == BettingState.CANCELLED,
            "State not PAYABLE or CANCELLED."
        );

        // Require user has not received payout for this fixture
        require(!userWasPaid[fixtureID][msg.sender], "Already paid.");

        if (bettingState[fixtureID] == BettingState.PAYABLE) {
            handleWithdrawPayout(fixtureID);
        } else if (bettingState[fixtureID] == BettingState.CANCELLED) {
            handleFixtureCancelledPayout(fixtureID);
        }
    }

    function handleWithdrawPayout(string memory fixtureID)
        internal
    {
        SportsBettingLib.FixtureResult result = results[fixtureID];
        if (result == SportsBettingLib.FixtureResult.DEFAULT || result == SportsBettingLib.FixtureResult.CANCELLED) {
            revert("Invalid fixture result.");
        }

        // Require user had staked on winning result
        uint256 stakerAmount = amounts[fixtureID][result][msg.sender];
        require(stakerAmount > 0, "You did not stake on the winning outcome");

        SportsBettingLib.FixtureResult[] memory winningOutcomes = new SportsBettingLib.FixtureResult[](1);
        winningOutcomes[0] = result;
        SportsBettingLib.FixtureResult[] memory losingOutcomes = SportsBettingLib.getLosingFixtureOutcomes(result);

        // Get total amounts bet on each fixture result
        uint256 winningAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, winningOutcomes);
        uint256 losingAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, losingOutcomes);
        uint256 totalAmount = winningAmount + losingAmount;

        // Calculate staker's share of winnings
        uint256 obligation = (stakerAmount * totalAmount) / winningAmount;

        // Deduct owner commission
        // Commission of COMMISSION_RATE % is taken from staker profits
        uint256 commission = (COMMISSION_RATE * (obligation-stakerAmount)) / 100;
        obligation -= commission;

        // Set bet payout states
        payouts[fixtureID][msg.sender] = obligation;
        userWasPaid[fixtureID][msg.sender] = true;

        // Pay staker
        emit BetPayout(msg.sender, fixtureID, obligation);
        IERC20 dai = IERC20(daiAddress);
        require(
            dai.transfer(msg.sender, obligation),
            "Unable to payout staker"
        );
    }

    function handleFixtureCancelledPayout(string memory fixtureID)
        internal
    {
        require(bettingState[fixtureID] == BettingState.CANCELLED, "Fixture not cancelled");
        uint256 obligation = 0;
        for (uint256 i = 0; i < betTypes.length; i++) {
            obligation += amounts[fixtureID][betTypes[i]][msg.sender];
        }
        require(obligation > 0, "No stakes found on this fixture");

        // Set bet payout states
        payouts[fixtureID][msg.sender] = obligation;
        userWasPaid[fixtureID][msg.sender] = true;

        // Pay staker
        emit BetPayout(msg.sender, fixtureID, obligation);
        IERC20 dai = IERC20(daiAddress);
        require(
            dai.transfer(msg.sender, obligation),
            "Unable to payout staker"
        );
    }

    function handleCommissionPayout(string memory fixtureID) public {
        require(bettingState[fixtureID] == BettingState.PAYABLE, "Fixture not payable");
        require(!commissionPaid[fixtureID], "Commission already paid.");

        SportsBettingLib.FixtureResult result = results[fixtureID];
        if (result == SportsBettingLib.FixtureResult.DEFAULT || result == SportsBettingLib.FixtureResult.CANCELLED) {
            revert("Invalid fixture result.");
        }

        // Commission of COMMISSION RATE % is taken from 
        // TOTAL STAKER PROFITS e.g. total amount staked on losing outcommes
        // So calculate losing amount
        SportsBettingLib.FixtureResult[] memory losingOutcomes = SportsBettingLib.getLosingFixtureOutcomes(result);
        uint256 losingAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, losingOutcomes);

        // Calculate percentage
        commissionMap[fixtureID] = (COMMISSION_RATE * losingAmount) / 100;
        // Set commissionPaid to prevent re-entrancy, although we only pay is amount > 0
        commissionPaid[fixtureID] = true;
        emit BetCommissionPayout(fixtureID, commissionMap[fixtureID]);
        if (commissionMap[fixtureID] > 0) {
            IERC20 dai = IERC20(daiAddress);
            require(
                dai.transfer(owner, commissionMap[fixtureID]),
                "Unable to payout owner"
            );
        }
    }

    function getTotalAmountBetOnFixtureOutcomes(
        string memory fixtureID,
        SportsBettingLib.FixtureResult[] memory outcomes
    ) internal view returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < outcomes.length; i++) {
            amount += totalAmounts[fixtureID][outcomes[i]];
        }
        return amount;
    }

    function initializeHistoricalBetters(string memory fixtureID) internal {
        for (uint256 i = 0; i < betTypes.length; i++) {
            initializeHistoricalBettersForBetType(fixtureID, betTypes[i]);
        }
    }

    function initializeHistoricalBettersForBetType(
        string memory fixtureID,
        SportsBettingLib.FixtureResult betType
    ) internal {
        // This code initializes our map for historical betters in fixture
        // It ensures we can reliably track only unique betters for fixture
        historicalBetters[fixtureID][betType] = [address(0x0)];
    }

    function isHistoricalBetter(
        string memory fixtureID,
        SportsBettingLib.FixtureResult betType,
        address staker
    ) internal view returns (bool) {
        // address 0x0 is not valid if pos is 0 is not in the array
        if (
            staker != address(0x0) &&
            historicalBettersIndex[fixtureID][betType][staker] > 0
        ) {
            return true;
        }
        return false;
    }

    function addHistoricalBetter(
        string memory fixtureID,
        SportsBettingLib.FixtureResult betType,
        address staker
    ) internal {
        if (!isHistoricalBetter(fixtureID, betType, staker)) {
            historicalBettersIndex[fixtureID][betType][
                staker
            ] = historicalBetters[fixtureID][betType].length;
            historicalBetters[fixtureID][betType].push(staker);
        }
    }

    function getEnrichedFixtureData(string memory fixtureID, address user)
        public
        view
        returns (FixtureEnrichment memory)
    {
        return
            FixtureEnrichment({
                fixtureState: bettingState[fixtureID],
                user: getStakeSummaryForUser(fixtureID, user),
                total: [
                    totalAmounts[fixtureID][SportsBettingLib.FixtureResult.HOME],
                    totalAmounts[fixtureID][SportsBettingLib.FixtureResult.DRAW],
                    totalAmounts[fixtureID][SportsBettingLib.FixtureResult.AWAY]
                ]
            });
    }

    function getStakeSummaryForUser(string memory fixtureID, address user)
        internal
        view
        returns (uint256[3] memory)
    {
        return [
            amounts[fixtureID][SportsBettingLib.FixtureResult.HOME][user],
            amounts[fixtureID][SportsBettingLib.FixtureResult.DRAW][user],
            amounts[fixtureID][SportsBettingLib.FixtureResult.AWAY][user]
        ];
    }
}
