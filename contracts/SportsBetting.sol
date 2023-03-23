//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "./SportsOracleConsumer.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./SportsBettingLib.sol";

/// @title A contract for sports result staking
/// @author Nathan Cinnamond
/// @notice Handles user stakes and allows winning stakers to claim payouts 
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

    /// @notice Event emitted each time the betting state for a fixture changes
    /// @param fixtureID: the corresponding fixtureID for fixture that has state change
    /// @param state: the BettingState corresponding to the new state of the fixture
    event BettingStateChanged(string fixtureID, BettingState state);

    /// @notice Event emitted each time a user stakes on a fixture outcome
    /// @param better: address of the staker
    /// @param fixtureID: corresponding fixtureID for fixture on which outcome is staked
    /// @param amount: amount added to total amount staked by better on fixture outcome
    /// @param betType: outcome of fixtureID that better has staked on
    event BetStaked(
        address indexed better,
        string indexed fixtureID,
        uint256 amount,
        SportsBettingLib.FixtureResult betType
    );

    /// @notice Event emitted each time a user unstakes on a fixture outcome
    /// @param better: address of the unstaker
    /// @param fixtureID: corresponding fixtureID for fixture on which outcome is unstaked
    /// @param amount: amount subtracted from total amount staked by better on fixture outcome
    /// @param betType: outcome of fixtureID that better has unstaked on
    event BetUnstaked(
        address indexed better,
        string indexed fixtureID,
        uint256 amount,
        SportsBettingLib.FixtureResult betType
    );

    /// @notice Event emitted each time a user claims payout on fixture result
    /// @param better: address of the unstaker
    /// @param fixtureID: corresponding fixtureID for fixture on outcome which better claims payout
    /// @param amount: amount paid out to better (original stake plus profit)
    event BetPayout(address indexed better, string fixtureID, uint256 amount);

    /// @notice Event emitted each time owner claims commission on bet payout profits
    /// @param amount: amount paid out to owner in commission
    event BetCommissionPayout(string indexed fixtureID, uint256 amount);

    /// @notice Event emitted each time a fixture kickoff time is fulfilled by oracle
    /// @param fixtureID: corresponding fixtureID for fixture with kickoff time fulfilled
    /// @param kickoffTime: unix timestamp of kickoff time for fixture
    event KickoffTimeUpdated(string fixtureID, uint256 kickoffTime);

    // Contract owner
    address public immutable owner;

    // DAI Stablecoin address
    address public immutable daiAddress;

    // Entrance fee of 0.0001 DAI (10^14 Wei)
    uint256 public constant ENTRANCE_FEE = 10e14;

    // Commission rate taken by contract owner for each payout in basis points
    // Note: 100 BPS = 1%
    uint256 public constant COMMISSION_RATE = 100;

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

    /// Invalid condition for fixture state transition from current->potential. 
    /// @param current bet state
    /// @param potential bet state
    error InvalidBettingStateTransition(BettingState current, BettingState potential);

    /// Invalid betting state to perform the action
    /// @param action e.g. stake
    /// @param current bet state
    /// @param required bet state
    error InvalidBettingStateForAction(string action, BettingState current, BettingState required);

    /// Invalid amount staked or unstaked
    /// @param fixtureID fixtureID corresponding to this action
    /// @param betType betType of the stake action
    /// @param amount amount being staked/unstaked
    /// @param reason human-readable explanation
    error InvalidStakeAction(string fixtureID, SportsBettingLib.FixtureResult betType, uint256 amount, string reason);

    /// Invalid amount staked or unstaked
    /// @param fixtureID fixtureID corresponding to this action
    /// @param state betting state of this fixture
    /// @param result fixture result
    /// @param reason human-readable explanation
    error InvalidPayoutAction(string fixtureID, BettingState state, SportsBettingLib.FixtureResult result, string reason);

    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _dai,
        address _link,
        string memory _jobId,
        uint256 _fee
    ) SportsOracleConsumer(_sportsOracleURI, _oracle, _link, _jobId, _fee) {
        owner = msg.sender;
        daiAddress = _dai;
    }

    // Wrapper for setting fixture betting state and emitting event
    function setFixtureBettingState(string memory fixtureID, BettingState state)
        internal
    {
        bettingState[fixtureID] = state;
        emit BettingStateChanged(fixtureID, state);
    }

    /// @notice Closes fixture if it is 1. Not currently closed AND 2. eligible to be closed
    /// @param fixtureID: the corresponding fixtureID for fixture to be closed
    function closeBetForFixture(string memory fixtureID) public {
        if (bettingState[fixtureID] == BettingState.CLOSED || !fixtureShouldBecomeClosed(fixtureID)) {
            revert InvalidBettingStateTransition(bettingState[fixtureID], BettingState.CLOSED);
        }
        setFixtureBettingState(fixtureID, BettingState.CLOSED);
    }

    /// @notice Makes oracle request to get fixture kickoff time and set fixture state to OPENING
    /// @notice On fulfillment handle, ctx will open fixture is eligible
    /// @param fixtureID: the corresponding fixtureID for fixture to be opened
    function openBetForFixture(string memory fixtureID) public {
        if (bettingState[fixtureID] != BettingState.CLOSED && bettingState[fixtureID] != BettingState.OPENING) {
            revert InvalidBettingStateTransition(bettingState[fixtureID], BettingState.OPEN);
        }
        setFixtureBettingState(fixtureID, BettingState.OPENING);
        requestFixtureKickoffTime(fixtureID);
    }
    
    /// @notice Changes fixture betting state to AWAITING if eligible
    /// @param fixtureID: the corresponding fixtureID for fixture to be set to AWAITING
    function awaitBetForFixture(string memory fixtureID) public {
        // Ideally the betting state will change from OPEN -> AWAITING
        // by virtue of a bet being placed too close to KO time, however
        // in the event this doesn't happen, this function can be called to
        // attempt to change state to AWAITING
        if (bettingState[fixtureID] != BettingState.OPEN || !fixtureShouldBecomeAwaiting(fixtureID)) {
            revert InvalidBettingStateTransition(bettingState[fixtureID], BettingState.AWAITING);
        }
        setFixtureBettingState(fixtureID, BettingState.AWAITING);
    }

    function fixtureShouldBecomeAwaiting(string memory fixtureID) internal view returns(bool) {
        uint256 ko = fixtureToKickoffTime[fixtureID];
        // OPEN -> AWAITING
        // If a bet is OPEN, it becomes AWAITING if
        // current time is more than BET_CUTOFF_TIME to the right of kickoff time
        return (
            ko > BET_CUTOFF_TIME &&
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
            ko != 0 &&
            ko >= BET_CUTOFF_TIME &&
            ko >= BET_ADVANCE_TIME &&
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
            ko != 0 &&
            ko >= BET_CUTOFF_TIME &&
            ko >= BET_ADVANCE_TIME &&
            (block.timestamp > ko - BET_CUTOFF_TIME ||
                block.timestamp < ko - BET_ADVANCE_TIME)
        );
    }

    /// @notice Allows user to stake on fixture with ID fixtureID for outcome 'betType' with 'amount'
    /// @param fixtureID: Corresponding fixtureID for fixture user is staking on
    /// @param betType: The fixture outcome the msg sender is staking on
    /// @param amount: The amount of collateral added to user's total stake on fixture outcome
    function stake(
        string memory fixtureID, 
        SportsBettingLib.FixtureResult betType, 
        uint256 amount
    ) public {
        // Don't allow stakes if we should be in AWAITING state
        if (fixtureShouldBecomeAwaiting(fixtureID)) {
            setFixtureBettingState(fixtureID, BettingState.AWAITING);
            return;
        }

        // Impose requirements
        require(
            betType != SportsBettingLib.FixtureResult.DEFAULT && 
            betType != SportsBettingLib.FixtureResult.CANCELLED, 
            "This BetType is not permitted.");
        if (bettingState[fixtureID] != BettingState.OPEN) {
            revert InvalidBettingStateForAction("stake", bettingState[fixtureID], BettingState.OPEN);
        }
        if (amount < ENTRANCE_FEE) {
            revert InvalidStakeAction(fixtureID, betType, amount, "Amount is below entrance fee.");
        }

        bool flag;
        uint256 newStakerAmount;
        uint256 newTotalAmount;

        // Handle possible overflow on staker amount
        (flag, newStakerAmount) = SafeMath.tryAdd(amounts[fixtureID][betType][msg.sender], amount);
        require(flag, "User stake overflow.");

        // Handle possible overflow on total amounts
        (flag, newTotalAmount) = SafeMath.tryAdd(totalAmounts[fixtureID][betType], amount);
        require(flag, "Total stake overflow.");

        // Update state
        amounts[fixtureID][betType][msg.sender] = newStakerAmount;
        totalAmounts[fixtureID][betType] = newTotalAmount;

        // Transfer DAI tokens
        emit BetStaked(msg.sender, fixtureID, amount, betType);
        IERC20 dai = IERC20(daiAddress);
        require(
            dai.transferFrom(msg.sender, address(this), amount),
            "Unable to transfer."
        );
    }

    /// @notice Allows user to unstake on fixture with ID fixtureID for outcome 'betType' with 'amount'
    /// @param fixtureID: Corresponding fixtureID for fixture user is unstaking on
    /// @param betType: The fixture outcome the msg sender is unstaking on
    /// @param amount: The amount of collateral subtracted from user's total stake on fixture outcome
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

        // Betting must be in OPEN state for this fixture
        if (bettingState[fixtureID] != BettingState.OPEN) {
            revert InvalidBettingStateForAction("unstake", bettingState[fixtureID], BettingState.OPEN);
        }

        // Impose requirements on unstake value
        if (amount <= 0) {
            revert InvalidStakeAction(fixtureID, betType, amount, "Amount should exceed zero.");
        }

        // Impose requirements on user's stake if this unstake occurs
        uint256 amountStaked = amounts[fixtureID][betType][msg.sender];
        if (amountStaked <= 0) {
            revert InvalidStakeAction(fixtureID, betType, amount, "No stake on this address-result.");
        }
        if (amount > amountStaked) {
            revert InvalidStakeAction(fixtureID, betType, amount, "Current stake too low.");
        }

        // New value for user stake on this fixture-betType combo
        uint256 newStakerAmount = amountStaked - amount;

        // If this is a partial unstake, ensure ENTRANCE_FEE is maintained
        if (newStakerAmount > 0 && newStakerAmount < ENTRANCE_FEE) {
            revert InvalidStakeAction(fixtureID, betType, amount, "Cannot go below entrance fee for partial unstake.");
        }

        // Update state
        amounts[fixtureID][betType][msg.sender] = newStakerAmount;
        totalAmounts[fixtureID][betType] -= amount;

        // Transfer DAI to msg sender
        emit BetUnstaked(msg.sender, fixtureID, amount, betType);
        IERC20 dai = IERC20(daiAddress);
        require(dai.transfer(msg.sender, amount), "Unable to transfer DAI.");
    }

    /// @notice Calls consumer contract to request fixture kickoff time from oracle
    /// @param fixtureID: Corresponding fixtureID for fixture user requests kickoff time for
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
        if (bytes(fixtureID).length == 0) {
            revert("No fixture matches request ID.");
        }
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

    /// @notice Calls consumer contract to request fixture result from oracle
    /// @param fixtureID: Corresponding fixtureID for fixture user requests result for
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
        // Can't proceed with empty fixture ID
        if (bytes(fixtureID).length == 0) {
            revert("Cannot find fixture ID");
        }

        emit RequestFixtureResultFulfilled(requestId, fixtureID, result);

        SportsBettingLib.FixtureResult parsedResult = SportsBettingLib.getFixtureResultFromAPIResponse(result);
        if (parsedResult == SportsBettingLib.FixtureResult.DEFAULT) {
            string memory errorString = string.concat(
                "Error on fixture ",
                fixtureID,
                ": Unknown fixture result from API"
            );
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

    /// @notice Transfers user winnings on fixture if applicable
    /// @param fixtureID: Corresponding fixtureID for fixture user withdraws winnings for
    function withdrawPayout(string memory fixtureID)
        external
    {
        if (bettingState[fixtureID] != BettingState.PAYABLE && bettingState[fixtureID] != BettingState.CANCELLED) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], results[fixtureID], "State not PAYABLE or CANCELLED.");
        }

        // Require user has not received payout for this fixture
        if (userWasPaid[fixtureID][msg.sender]) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], results[fixtureID], "User already paid.");
        }

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
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], result, "Invalid fixture result.");
        }

        // Require user had staked on winning result
        uint256 stakerAmount = amounts[fixtureID][result][msg.sender];
        if (stakerAmount <= 0) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], result, "You did not stake on the winning outcome.");
        }

        SportsBettingLib.FixtureResult[] memory winningOutcomes = new SportsBettingLib.FixtureResult[](1);
        winningOutcomes[0] = result;
        SportsBettingLib.FixtureResult[] memory losingOutcomes = SportsBettingLib.getLosingFixtureOutcomes(result);
        // Get total amounts bet on each fixture result
        uint256 winningAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, winningOutcomes);
        uint256 losingAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, losingOutcomes);
        (bool flag, uint256 totalAmount) = SafeMath.tryAdd(winningAmount, losingAmount);
        if (!flag) {
            revert("Overflow on total amount bet");
        }

        // Calculate staker's share of winnings
        uint256 obligation = SportsBettingLib.calculateStakerObligation(stakerAmount, winningAmount, totalAmount);
        // Deduct owner commission
        // Commission of COMMISSION_RATE % is taken from staker profits
        uint256 commission = SportsBettingLib.calculateCommission(obligation, stakerAmount, COMMISSION_RATE);
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

    function handleFixtureCancelledPayout(string memory fixtureID) internal {
        if (bettingState[fixtureID] != BettingState.CANCELLED) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], results[fixtureID], "Fixture not cancelled.");
        }

        uint256 obligation = 0;
        uint8 maxBetType = uint8(SportsBettingLib.FixtureResult.AWAY) + 1;
        for (uint8 i = 0; i < maxBetType; i++) {
            obligation += amounts[fixtureID][SportsBettingLib.FixtureResult(i)][msg.sender];
        }
        if (obligation == 0) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], results[fixtureID], "No stakes found on this fixture.");
        }

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

    /// @notice Transfers owner commission on fixture if applicable
    /// @param fixtureID: Corresponding fixtureID for fixture owner withdraws commission for
    function handleCommissionPayout(string memory fixtureID) internal {
        if (bettingState[fixtureID] != BettingState.PAYABLE) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], results[fixtureID], "Fixture not payable.");
        }
        if (commissionPaid[fixtureID]) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], results[fixtureID], "Commission already paid.");
        }

        SportsBettingLib.FixtureResult result = results[fixtureID];
        if (result == SportsBettingLib.FixtureResult.DEFAULT || result == SportsBettingLib.FixtureResult.CANCELLED) {
            revert InvalidPayoutAction(fixtureID, bettingState[fixtureID], result, "Invalid fixture result.");
        }

        // Commission of COMMISSION RATE % is taken from total staker profits
        SportsBettingLib.FixtureResult[] memory winningOutcomes = new SportsBettingLib.FixtureResult[](1);
        winningOutcomes[0] = result;
        uint256 winningAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, winningOutcomes);

        SportsBettingLib.FixtureResult[] memory losingOutcomes = SportsBettingLib.getLosingFixtureOutcomes(result);
        uint256 losingAmount = getTotalAmountBetOnFixtureOutcomes(fixtureID, losingOutcomes);
        
        uint256 totalAmount = winningAmount + losingAmount;

        // Calculate commission
        uint256 commission = SportsBettingLib.calculateCommission(totalAmount, winningAmount, COMMISSION_RATE);

        // Set commissionPaid to prevent re-entrancy
        commissionMap[fixtureID] = commission;
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

    /// @notice Gets total and user stakes on all outcomes for fixture
    /// @param fixtureID: Corresponding fixtureID for fixture outcomes
    /// @param user: Address of user corresponding to user fixture stakes
    /// @return FixtureEnrichment struct containing fixture state, user stakes and total stakes
    function getEnrichedFixtureData(string memory fixtureID, address user)
        external
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
