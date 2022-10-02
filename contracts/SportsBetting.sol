//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./SportsOracleConsumer.sol";
import "hardhat/console.sol";

contract SportsBetting is SportsOracleConsumer {
    enum BetType {
        HOME,
        DRAW,
        AWAY
    }

    enum BettingState {
        CLOSED,
        OPENING,
        OPEN,
        AWAITING,
        FULFILLING,
        FULFILLED
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
        BetType betType
    );

    event BetUnstaked(
        address indexed better,
        string fixtureID,
        uint256 amount,
        BetType betType
    );

    event BetPayoutFulfillmentError(string fixtureID, string reason);

    event BetPayout(address indexed better, string fixtureID, uint256 amount);

    event KickoffTimeUpdated(string fixtureID, uint256 kickoffTime);

    BetType[3] public betTypes;

    // Entrance fee of 0.0001 Eth (10^14 Wei)
    uint256 public entranceFee = 10**14;

    // Max time before a fixture kick-off that a bet can be placed in seconds
    // A fixture bet state will not move to OPEN before a time to the left of the
    // ko time equal to betAdvanceTime
    uint256 public betAdvanceTime = 7 * 24 * 60 * 60;

    // Cut off time for bets before KO time in seconds
    // i.e. all bets must be placed at time t where t < koTime - betCutOffTime
    uint256 public betCutOffTime = 90 * 60; // 90 minutes

    // Map each fixture ID to a map of BetType to an array of all addresses that have ever placed
    // bets for that fixture-result pair
    mapping(string => mapping(BetType => address[])) public historicalBetters;

    // We want to store unique addresses in historicalBetters mapping.
    // Solidity has no native set type, so we keep a mapping of address to fixture type to bet type
    // to index in historicalBetters
    // We only append an address to historicalBetters if it does not have an existing index
    mapping(string => mapping(BetType => mapping(address => uint256)))
        public historicalBettersIndex;

    // activeBetters represents all addresses who currently have an amount staked on a fixture-result
    // The mapping(address => bool) pattern allows us to set address to true or false if an address
    // stakes/unstakes for that bet, and allows safer 'contains' methods on the betters
    mapping(string => mapping(BetType => mapping(address => bool)))
        public activeBetters;

    // Map each fixture ID to a map of BetType to a map of address to uint representing the amount of wei bet on that result
    mapping(string => mapping(BetType => mapping(address => uint256)))
        public amounts;

    // Map each fixture ID to a map of address to amount we owe the address owner
    mapping(string => mapping(address => uint256)) public obligations;

    // Map each fixture ID to whether betting is open for this fixture
    mapping(string => BettingState) public bettingState;

    // Map each fixture ID to unix timestamp for its kickoff time
    mapping(string => uint256) public fixtureToKickoffTime;

    // Map oracle request ID for fixture kickoff time request to corresponding fixture ID
    mapping(bytes32 => string) public requestKickoffToFixture;

    // Map oracle request ID for fixture result request to corresponding fixture ID
    mapping(bytes32 => string) public requestResultToFixture;

    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _link,
        bytes32 _jobId,
        uint256 _fee
    ) SportsOracleConsumer(_sportsOracleURI, _oracle, _link, _jobId, _fee) {
        betTypes[0] = BetType.HOME;
        betTypes[1] = BetType.DRAW;
        betTypes[2] = BetType.AWAY;
    }

    function initializeHistoricalBetters(string memory fixtureID) internal {
        for (uint256 i = 0; i < betTypes.length; i++) {
            initializeHistoricalBettersForBetType(fixtureID, betTypes[i]);
        }
    }

    function initializeHistoricalBettersForBetType(
        string memory fixtureID,
        BetType betType
    ) internal {
        // This code initializes our map for historical betters in fixture
        // It ensures we can reliably track only unique betters for fixture
        historicalBetters[fixtureID][betType] = [address(0x0)];
    }

    function isHistoricalBetter(
        string memory fixtureID,
        BetType betType,
        address staker
    ) internal returns (bool) {
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
        BetType betType,
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
                    getTotalAmountBetOnFixtureOutcome(fixtureID, BetType.HOME),
                    getTotalAmountBetOnFixtureOutcome(fixtureID, BetType.DRAW),
                    getTotalAmountBetOnFixtureOutcome(fixtureID, BetType.AWAY)
                ]
            });
    }

    function getStakeSummaryForUser(string memory fixtureID, address user)
        internal
        view
        returns (uint256[3] memory)
    {
        return [
            amounts[fixtureID][BetType.HOME][user],
            amounts[fixtureID][BetType.DRAW][user],
            amounts[fixtureID][BetType.AWAY][user]
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
        // EDGE CASE: We close betting for a fixture that has bets placed, i.e. in the case
        // of a postponed fixture or an errant opening
        // We need to pay back the betters who placed bets
        else if (state == BettingState.CLOSED) {
            handleClosingBetsForFixture(fixtureID);
        }
    }

    // closeBetForFixture calls shouldHaveCorrectBettingState which, if kickoff time
    // is in a certain position relative to current timestamp, will close the bet
    function closeBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] != BettingState.CLOSED,
            "Bet state is already CLOSED."
        );
        shouldHaveCorrectBettingState(fixtureID);
    }

    // openBetForFixture makes an API call to oracle. It is expected that this
    // call will return the kickoff_time and the fulfillFixtureKickoffTime func
    // will handle the state change to open
    // This is to ensure we don't open a bet until we have its KO time and
    // know that it advanced enough in the future
    function openBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] == BettingState.CLOSED,
            "Bet state must be CLOSED."
        );
        setFixtureBettingState(fixtureID, BettingState.OPENING);
        requestFixtureKickoffTime(fixtureID);
    }

    // Ideally the betting state will change from OPEN -> AWAITING
    // by virtue of a bet being placed too close to KO time, however
    // in the event this doesn't happen, this function can be called to
    // attempt to change state to AWAITING
    // This also helps resolve bugs whereby the bet is marked as fulfilled
    // when it is not
    function awaitBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet state must be OPEN."
        );
        shouldHaveCorrectBettingState(fixtureID);
    }

    // This function handles betting state transitions respective to bet kickoff time
    // In general, a bet should be
    // CLOSED       if time < kickoff - betAdvanceTime
    // OPEN         if kickoff - betAdvanceTime <= time <= ko - betCutOffTime
    // AWAITING     if time > ko - betCutOffTime
    function shouldHaveCorrectBettingState(string memory fixtureID) internal {
        uint256 ko = fixtureToKickoffTime[fixtureID];

        // CLOSE if no kickoff time present
        if (ko == 0) {
            setFixtureBettingState(fixtureID, BettingState.CLOSED);
            return;
        }

        // OPENING -> CLOSED
        // If fixture is OPENING, it will become CLOSED if
        // current time is to the right of kickoff time - betCutOffTime
        // OR
        // current time is to the left of kickoff time - betAdvanceTime
        if (
            bettingState[fixtureID] == BettingState.OPENING &&
            (block.timestamp > ko - betCutOffTime ||
                block.timestamp < ko - betAdvanceTime)
        ) {
            setFixtureBettingState(fixtureID, BettingState.CLOSED);
            return;
        }

        // OPEN/AWAITING -> CLOSED
        // If fixture is OPEN or AWAITING, it will become CLOSED if
        // current time is more than betAdvanceTime to the left of ko
        if (
            (bettingState[fixtureID] == BettingState.OPEN ||
                bettingState[fixtureID] == BettingState.AWAITING) &&
            block.timestamp < ko - betAdvanceTime
        ) {
            setFixtureBettingState(fixtureID, BettingState.CLOSED);
            return;
        }

        // OPENING -> OPEN
        // If a bet is OPENING, it can be OPENed if
        // current time is more than betCutOffTime before kickoff time AND
        // current time is less than betAdvanceTime before kickoff time
        if (
            bettingState[fixtureID] == BettingState.OPENING &&
            block.timestamp <= ko - betCutOffTime &&
            block.timestamp >= ko - betAdvanceTime
        ) {
            setFixtureBettingState(fixtureID, BettingState.OPEN);
            return;
        }

        // OPEN -> AWAITING
        // If a bet is OPEN, it becomes AWAITING if
        // current time is more than betCutOffTime to the right of kickoff time
        if (
            bettingState[fixtureID] == BettingState.OPEN &&
            block.timestamp > ko - betCutOffTime &&
            betCutOffTime != 0
        ) {
            setFixtureBettingState(fixtureID, BettingState.AWAITING);
            return;
        }
    }

    function fulfillBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] == BettingState.AWAITING,
            "Bet state must be AWAITING."
        );
        setFixtureBettingState(fixtureID, BettingState.FULFILLING);
        requestFixtureResult(fixtureID);
    }

    function stake(string memory fixtureID, BetType betType) public payable {
        shouldHaveCorrectBettingState(fixtureID);
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet activity is not open."
        );
        require(msg.value >= entranceFee, "Amount is below entrance fee.");

        amounts[fixtureID][betType][msg.sender] += msg.value;
        addHistoricalBetter(fixtureID, betType, msg.sender);
        activeBetters[fixtureID][betType][msg.sender] = true;
        emit BetStaked(msg.sender, fixtureID, msg.value, betType);
    }

    // Removes all stake in fixtureID-BetType combo
    function unstake(
        string memory fixtureID,
        BetType betType,
        uint256 amount
    ) public {
        require(amount > 0, "Amount should exceed zero.");
        shouldHaveCorrectBettingState(fixtureID);
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Fixture is not in Open state."
        );
        handleUnstake(fixtureID, betType, amount, msg.sender);
    }

    // Execute business logic to unstake parameter amount to staker
    function handleUnstake(
        string memory fixtureID,
        BetType betType,
        uint256 amount,
        address staker
    ) internal {
        uint256 amountStaked = amounts[fixtureID][betType][staker];
        require(amountStaked > 0, "No stake on this address-result.");
        require(amount <= amountStaked, "Current stake too low.");

        // Update stake amount
        amounts[fixtureID][betType][staker] = amountStaked - amount;

        // If non-partial unstake, caller is no longer an active staker
        if (amounts[fixtureID][betType][staker] <= 0) {
            activeBetters[fixtureID][betType][staker] = false;
        }

        payable(staker).transfer(amount);
        emit BetUnstaked(staker, fixtureID, amount, betType);
    }

    function requestFixtureKickoffTime(string memory fixtureID) internal {
        bytes32 requestID = requestFixtureKickoffTimeParameter(fixtureID);
        requestKickoffToFixture[requestID] = fixtureID;
        emit RequestedFixtureKickoff(requestID, fixtureID);
    }

    function fulfillFixtureKickoffTime(bytes32 _requestId, uint256 _ko)
        internal
        override
    {
        string memory fixtureID = requestKickoffToFixture[_requestId];
        emit RequestFixtureKickoffFulfilled(_requestId, fixtureID, _ko);

        updateKickoffTime(fixtureID, _ko);
        shouldHaveCorrectBettingState(fixtureID);
    }

    function updateKickoffTime(string memory fixtureID, uint256 _ko) internal {
        if (_ko != fixtureToKickoffTime[fixtureID]) {
            fixtureToKickoffTime[fixtureID] = _ko;
            emit KickoffTimeUpdated(fixtureID, _ko);
        }
    }

    function requestFixtureResult(string memory fixtureID) internal {
        bytes32 requestID = requestFixtureResultParameter(fixtureID);
        requestResultToFixture[requestID] = fixtureID;
        emit RequestedFixtureResult(requestID, fixtureID);
    }

    function fulfillFixtureResult(bytes32 _requestId, uint256 _result)
        internal
        override
    {
        string memory fixtureID = requestResultToFixture[_requestId];
        emit RequestFixtureResultFulfilled(_requestId, fixtureID, _result);

        // Only action on fixture result if we are in FULFILLING
        if (bettingState[fixtureID] == BettingState.FULFILLING) {
            updateFixtureResult(fixtureID, _result);
            setFixtureBettingState(fixtureID, BettingState.FULFILLED);
        }
    }

    function updateFixtureResult(string memory fixtureID, uint256 _result)
        internal
    {
        BetType result = getFixtureResultFromAPIResponse(fixtureID, _result);

        BetType[] memory winningOutcomes;
        winningOutcomes[0] = result;

        BetType[] memory losingOutcomes = getLosingFixtureOutcomes(result);

        uint256 winningAmount = getTotalAmountBetOnFixtureOutcomes(
            fixtureID,
            winningOutcomes
        );
        uint256 losingAmount = getTotalAmountBetOnFixtureOutcomes(
            fixtureID,
            losingOutcomes
        );
        uint256 totalAmount = winningAmount + losingAmount;

        // Now we set the obligations map entry for this fixture based on above calcs and
        // perform the payout
        fulfillFixturePayoutObligations(
            fixtureID,
            result,
            winningAmount,
            totalAmount
        );
    }

    function getFixtureResultFromAPIResponse(
        string memory fixtureID,
        uint256 _result
    ) internal returns (BetType) {
        if (_result == uint256(BetType.HOME)) {
            return BetType.HOME;
        } else if (_result == uint256(BetType.DRAW)) {
            return BetType.DRAW;
        } else if (_result == uint256(BetType.AWAY)) {
            return BetType.AWAY;
        }

        // Error: unknown value in 'result' field
        // Set fixture state to AWAITING so we can try again in future
        setFixtureBettingState(fixtureID, BettingState.AWAITING);

        string memory errorString = string.concat(
            "Error on fixture ",
            fixtureID,
            ": Unknown fixture result from API"
        );
        emit BetPayoutFulfillmentError(fixtureID, errorString);
        revert(errorString);
    }

    function strEqual(string memory a, string memory b)
        private
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function getLosingFixtureOutcomes(BetType outcome)
        internal
        view
        returns (BetType[] memory)
    {
        BetType[] memory losingOutcomes = new BetType[](2);

        uint256 losingOutcomesIndex = 0;
        for (uint256 i = 0; i < betTypes.length; i++) {
            if (betTypes[i] != outcome) {
                losingOutcomes[losingOutcomesIndex] = betTypes[i];
                losingOutcomesIndex += 1;
            }
        }
        return losingOutcomes;
    }

    function getTotalAmountBetOnFixtureOutcomes(
        string memory fixtureID,
        BetType[] memory outcomes
    ) internal view returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < outcomes.length; i++) {
            amount += getTotalAmountBetOnFixtureOutcome(fixtureID, outcomes[i]);
        }
        return amount;
    }

    function getTotalAmountBetOnFixtureOutcome(
        string memory fixtureID,
        BetType outcome
    ) internal view returns (uint256) {
        uint256 amount;
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

    // fulfillFixturePayoutObligations calculates the obligations (amount we owe to each
    // winning staker for this fixture)
    function fulfillFixturePayoutObligations(
        string memory fixtureID,
        BetType result,
        uint256 winningAmount,
        uint256 totalAmount
    ) internal {
        if (bettingState[fixtureID] != BettingState.FULFILLING) {
            revert("Fixture bet state is not FULFILLING.");
        }

        for (
            uint256 i = 0;
            i < historicalBetters[fixtureID][result].length;
            i++
        ) {
            address better = historicalBetters[fixtureID][result][i];
            if (activeBetters[fixtureID][result][better]) {
                uint256 betterAmount = amounts[fixtureID][result][better];
                uint256 betterObligation = betterAmount *
                    (totalAmount / winningAmount);
                obligations[fixtureID][better] = betterObligation;

                amounts[fixtureID][result][better] = 0;
                activeBetters[fixtureID][result][better] = false;
                payable(better).transfer(betterObligation);
                emit BetPayout(better, fixtureID, betterObligation);
            }
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
        BetType betType
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
}
