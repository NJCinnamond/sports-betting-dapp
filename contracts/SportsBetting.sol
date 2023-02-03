//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "./mock/IERC20.sol";
import "./SportsOracleConsumer.sol";
import "./SportsBettingLib.sol";

contract SportsBetting is SportsOracleConsumer {

    // RESULT_RECEIVED <- FULFILLING
    // PAID <- (NEW)
    enum BettingState {
        CLOSED,
        OPENING,
        OPEN,
        AWAITING,
        RESULT_RECEIVED,
        CALCULATED,
        PAID
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
        SportsBettingLib.BetType betType
    );

    event BetUnstaked(
        address indexed better,
        string fixtureID,
        uint256 amount,
        SportsBettingLib.BetType betType
    );

    event BetPayoutFulfillmentError(string fixtureID, string reason);

    event BetPayout(address indexed better, string fixtureID, uint256 amount);

    event BetCommissionPayout(string indexed fixtureID, uint256 amount);

    event KickoffTimeUpdated(string fixtureID, uint256 kickoffTime);

    SportsBettingLib.BetType[4] public betTypes;

    // Contract owner
    address public immutable owner;

    // Entrance fee of 0.0001 DAI (10^14 Wei)
    uint256 public constant ENTRANCE_FEE = 10**14;

    // DAI Stablecoin address
    address public immutable daiAddress;

    // Commission rate percentage taken by contract owner for each payout as a percentage
    uint256 public constant COMMISSION_RATE = 1;

    // Max time before a fixture kick-off that a bet can be placed in seconds
    // A fixture bet state will not move to OPEN before a time to the left of the
    // ko time equal to BET_ADVANCE_TIME
    uint256 public constant BET_ADVANCE_TIME = 7 * 24 * 60 * 60;

    // Cut off time for bets before KO time in seconds
    // i.e. all bets must be placed at time t where t < koTime - BET_CUTOFF_TIME
    uint256 public constant BET_CUTOFF_TIME = 90 * 60; // 90 minutes

    // Commission total taken by contract owner indexed by fixture
    mapping(string => uint256) public commissionMap;

    // Map fixture ID to fixture result
    mapping(string => SportsBettingLib.BetType) public results;

    // Map each fixture ID to a map of BetType to an array of all addresses that have ever placed
    // bets for that fixture-result pair
    mapping(string => mapping(SportsBettingLib.BetType => address[])) public historicalBetters;

    // We want to store unique addresses in historicalBetters mapping.
    // Solidity has no native set type, so we keep a mapping of address to fixture type to bet type
    // to index in historicalBetters
    // We only append an address to historicalBetters if it does not have an existing index
    mapping(string => mapping(SportsBettingLib.BetType => mapping(address => uint256)))
        public historicalBettersIndex;

    // activeBetters represents all addresses who currently have an amount staked on a fixture-result
    // The mapping(address => bool) pattern allows us to set address to true or false if an address
    // stakes/unstakes for that bet, and allows safer 'contains' methods on the betters
    mapping(string => mapping(SportsBettingLib.BetType => mapping(address => bool)))
        public activeBetters;

    // Map each fixture ID to a map of BetType to a map of address to uint representing the amount of wei bet on that result
    mapping(string => mapping(SportsBettingLib.BetType => mapping(address => uint256)))
        public amounts;

    // Map each fixture ID to a map of address to amount the ctx paid the address owner for that fixture
    mapping(string => mapping(address => uint256)) public payouts;

    // Map each fixture ID to whether betting is open for this fixture
    mapping(string => BettingState) public bettingState;

    // Map each fixture ID to unix timestamp for its kickoff time
    mapping(string => uint256) public fixtureToKickoffTime;

    // Map oracle request ID for fixture kickoff time request to corresponding fixture ID
    mapping(bytes32 => string) public requestKickoffToFixture;

    // Map oracle request ID for fixture result request to corresponding fixture ID
    mapping(bytes32 => string) public requestResultToFixture;

    // ownerWasPaid maps fixture ID to boolean indicating whether owner has already received payout for fixture
    // This prevents re-entrancy attacks where the owner can claim multiple payouts in case of fixture with no winners
    mapping(string => bool) public ownerWasPaid;

    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _dai,
        address _link,
        string memory _jobId,
        uint256 _fee
    ) SportsOracleConsumer(_sportsOracleURI, _oracle, _link, _jobId, _fee) {
        betTypes[0] = SportsBettingLib.BetType.DEFAULT;
        betTypes[1] = SportsBettingLib.BetType.HOME;
        betTypes[2] = SportsBettingLib.BetType.DRAW;
        betTypes[3] = SportsBettingLib.BetType.AWAY;

        owner = msg.sender;
        daiAddress = _dai;
    }

    function initializeHistoricalBetters(string memory fixtureID) internal {
        for (uint256 i = 0; i < betTypes.length; i++) {
            initializeHistoricalBettersForBetType(fixtureID, betTypes[i]);
        }
    }

    function initializeHistoricalBettersForBetType(
        string memory fixtureID,
        SportsBettingLib.BetType betType
    ) internal {
        // This code initializes our map for historical betters in fixture
        // It ensures we can reliably track only unique betters for fixture
        historicalBetters[fixtureID][betType] = [address(0x0)];
    }

    function isHistoricalBetter(
        string memory fixtureID,
        SportsBettingLib.BetType betType,
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
        SportsBettingLib.BetType betType,
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
                    getTotalAmountBetOnFixtureOutcome(fixtureID, SportsBettingLib.BetType.HOME),
                    getTotalAmountBetOnFixtureOutcome(fixtureID, SportsBettingLib.BetType.DRAW),
                    getTotalAmountBetOnFixtureOutcome(fixtureID, SportsBettingLib.BetType.AWAY)
                ]
            });
    }

    function getStakeSummaryForUser(string memory fixtureID, address user)
        internal
        view
        returns (uint256[3] memory)
    {
        return [
            amounts[fixtureID][SportsBettingLib.BetType.HOME][user],
            amounts[fixtureID][SportsBettingLib.BetType.DRAW][user],
            amounts[fixtureID][SportsBettingLib.BetType.AWAY][user]
        ];
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
        handleClosingBetsForFixture(fixtureID);
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
            bettingState[fixtureID] == BettingState.OPENING &&
            block.timestamp <= ko - BET_CUTOFF_TIME &&
            block.timestamp >= ko - BET_ADVANCE_TIME
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
            (
                bettingState[fixtureID] == BettingState.OPENING &&
                (block.timestamp > ko - BET_CUTOFF_TIME ||
                    block.timestamp < ko - BET_ADVANCE_TIME)
            ) || 
            // OPEN/AWAITING -> CLOSED
            // If fixture is OPEN or AWAITING, it will become CLOSED if
            // current time is more than BET_ADVANCE_TIME to the left of ko
            (
                (bettingState[fixtureID] == BettingState.OPEN ||
                    bettingState[fixtureID] == BettingState.AWAITING) &&
                block.timestamp < ko - BET_ADVANCE_TIME
            )
            // NOTE: Fixture cannot be closed from RESULT_RECEIVED or PAID state
        );
    }

    function stake(string memory fixtureID, SportsBettingLib.BetType betType, uint256 amount) public {
        // Don't allow stakes if we should be in AWAITING state
        if (fixtureShouldBecomeAwaiting(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.AWAITING);
            return;
        }

        require(
            betType != SportsBettingLib.BetType.DEFAULT,
            "This BetType is not permitted."
        );
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet activity is not open."
        );
        require(amount >= ENTRANCE_FEE, "Amount is below entrance fee.");

        amounts[fixtureID][betType][msg.sender] += amount;
        addHistoricalBetter(fixtureID, betType, msg.sender);
        activeBetters[fixtureID][betType][msg.sender] = true;

        // Transfer DAI tokens
        IERC20 dai = IERC20(daiAddress);
        require(
            dai.transferFrom(msg.sender, address(this), amount),
            "Unable to transfer"
        );
        emit BetStaked(msg.sender, fixtureID, amount, betType);
    }

    // Removes all stake in fixtureID-BetType combo
    function unstake(
        string memory fixtureID,
        SportsBettingLib.BetType betType,
        uint256 amount
    ) public {
        // Don't allow stakes if we should be in AWAITING state
        if (fixtureShouldBecomeAwaiting(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.AWAITING);
            return;
        }
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet activity is not open."
        );

        require(amount > 0, "Amount should exceed zero.");
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Fixture is not in Open state."
        );
        handleUnstake(fixtureID, betType, amount, msg.sender);
    }

    // Execute business logic to unstake parameter amount to staker
    function handleUnstake(
        string memory fixtureID,
        SportsBettingLib.BetType betType,
        uint256 amount,
        address staker
    ) internal {
        removeStakeState(fixtureID, betType, amount, staker);

        // Transfer DAI to msg sender
        IERC20 dai = IERC20(daiAddress);
        require(dai.transfer(msg.sender, amount), "Unable to unstake");

        emit BetUnstaked(staker, fixtureID, amount, betType);
    }

    function removeStakeState(
        string memory fixtureID,
        SportsBettingLib.BetType betType,
        uint256 amount,
        address staker
    ) internal {
        uint256 amountStaked = amounts[fixtureID][betType][staker];
        require(amountStaked > 0, "No stake on this address-result.");
        require(amount <= amountStaked, "Current stake too low.");
        require(amountStaked - amount >= ENTRANCE_FEE, "Cannot go below entrance fee.");

        // Update stake amount
        amounts[fixtureID][betType][staker] = amountStaked - amount;

        // If non-partial unstake, caller is no longer an active staker
        if (amounts[fixtureID][betType][staker] <= 0) {
            activeBetters[fixtureID][betType][staker] = false;
        }
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

        SportsBettingLib.BetType parsedResult = SportsBettingLib.getFixtureResultFromAPIResponse(result);
        if (parsedResult == SportsBettingLib.BetType.DEFAULT) {
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
            // Set fixture state to RESULT_RECEIVED
            setFixtureBettingState(fixtureID, BettingState.RESULT_RECEIVED);
        }
    }

    // calculateFixturePayout calculates the obligations (amount we owe to each
    // winning staker for this fixture)
    function calculateFixturePayout(string memory fixtureID)
        public
    {
        require(
            bettingState[fixtureID] == BettingState.RESULT_RECEIVED,
            "State should be RESULT_RECEIVED."
        );

        SportsBettingLib.BetType result = results[fixtureID];
        SportsBettingLib.BetType[] memory winningOutcomes = new SportsBettingLib.BetType[](1);
        winningOutcomes[0] = result;

        SportsBettingLib.BetType[] memory losingOutcomes = SportsBettingLib.getLosingFixtureOutcomes(result);

        uint256 winningAmount = getTotalAmountBetOnFixtureOutcomes(
            fixtureID,
            winningOutcomes
        );
        uint256 losingAmount = getTotalAmountBetOnFixtureOutcomes(
            fixtureID,
            losingOutcomes
        );
        uint256 totalAmount = winningAmount + losingAmount;

        // If winningAmount > 0, we have winners we can pay out to
        if (winningAmount > 0) {
            uint256 commission = 0;
            for (
                uint256 i = 0;
                i < historicalBetters[fixtureID][result].length;
                i++
            ) {
                address better = historicalBetters[fixtureID][result][i];
                if (activeBetters[fixtureID][result][better]) {
                    uint256 betterAmount = amounts[fixtureID][result][better];

                    // Calculate better's share of winnings
                    uint256 betterObligation = (betterAmount * winningAmount) / totalAmount;

                    // Handle commission
                    commission += (COMMISSION_RATE * betterObligation) / 100;
                    betterObligation -= commission;

                    // Set bet payout better
                    payouts[fixtureID][better] = betterObligation;
                }
            }
            commissionMap[fixtureID] = commission;
        } else {
            // Else total amount is paid to owner
            commissionMap[fixtureID] =  totalAmount;
        }

        // State transition: RESULT_RECEIVED -> CALCULATED
        // This prevents cross-function re-entrancy attacks that would allow
        // attackers to recalculate bet payouts after is called transfer() in
        // fulfillFixturePayoutObligations
        setFixtureBettingState(fixtureID, BettingState.CALCULATED);

        // Begin fixture payout 
        fulfillFixturePayoutObligations(fixtureID);
    }

    // fulfillFixturePayoutObligations 
    function fulfillFixturePayoutObligations(
        string memory fixtureID
    ) internal {
        require(
            bettingState[fixtureID] == BettingState.CALCULATED,
            "Bet state not CALCULATED."
        );
        
        // Get result 
        SportsBettingLib.BetType result = results[fixtureID];

        // DAI interface
        IERC20 dai = IERC20(daiAddress);

        for (
            uint256 i = 0;
            i < historicalBetters[fixtureID][result].length;
            i++
        ) {
            address better = historicalBetters[fixtureID][result][i];
            if (activeBetters[fixtureID][result][better]) {
                // This user is no longer an active better
                // Setting to false prevents re-entrancy attacks when .transfer() is called below
                activeBetters[fixtureID][result][better] = false;

                // Pay better
                uint256 betterObligation = payouts[fixtureID][better];
                
                require(
                    dai.transfer(better, betterObligation),
                    "Unable to payout better"
                );
                
                emit BetPayout(better, fixtureID, betterObligation);
            }
        }
        
        // Handle payout to owner
        handleOwnerPayout(fixtureID, commissionMap[fixtureID]);

        // State transition: CALCULATED -> PAID
        // This is the terminal of the fixture betting workflow
        setFixtureBettingState(fixtureID, BettingState.PAID);
    }

    function handleOwnerPayout(string memory fixtureID, uint256 amount) internal {
        // ownerWasPaid prevents re-entrancy attacks
        if (!ownerWasPaid[fixtureID]) {
            ownerWasPaid[fixtureID] = true;

            // Pay commission to owner
            IERC20 dai = IERC20(daiAddress);
            require(
                dai.transfer(owner, amount),
                "Unable to payout owner"
            );
            emit BetCommissionPayout(fixtureID, commissionMap[fixtureID]);
        }
    }

    // If betting is closed but we have stakes, we pay betters back
    // For each bet type for fixture, refund all stakers who staked on that bet type
    function handleClosingBetsForFixture(string memory fixtureID) internal {
        for (uint256 i = 0; i < betTypes.length; i++) {
            handleClosingBetsForFixtureBetType(fixtureID, betTypes[i]);
        }
    }

    // For a given fixture and bet type, refund all stakers their full stake amount
    function handleClosingBetsForFixtureBetType(
        string memory fixtureID,
        SportsBettingLib.BetType betType
    ) internal {
        for (
            uint256 i = 0;
            i < historicalBetters[fixtureID][betType].length;
            i++
        ) {
            address better = historicalBetters[fixtureID][betType][i];
            if (activeBetters[fixtureID][betType][better]) {
                uint256 betterAmount = amounts[fixtureID][betType][better];
                handleUnstake(fixtureID, betType, betterAmount, better);
            }
        }
    }

    function getTotalAmountBetOnFixtureOutcomes(
        string memory fixtureID,
        SportsBettingLib.BetType[] memory outcomes
    ) internal view returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < outcomes.length; i++) {
            amount += getTotalAmountBetOnFixtureOutcome(fixtureID, outcomes[i]);
        }
        return amount;
    }

    function getTotalAmountBetOnFixtureOutcome(
        string memory fixtureID,
        SportsBettingLib.BetType outcome
    ) internal view returns (uint256) {
        uint256 amount = 0;
        for (
            uint256 i = 0;
            i < historicalBetters[fixtureID][outcome].length;
            i++
        ) {
            address better = historicalBetters[fixtureID][outcome][i];
            if (activeBetters[fixtureID][outcome][better]) {
                amount += amounts[fixtureID][outcome][better];
            }
        }
        return amount;
    }
}
