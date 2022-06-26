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
        OPEN,
        AWAITING,
        FULFILLED
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
        BetType betType
    );

    event BetPayout(address indexed better, string fixtureID, uint256 amount);

    event KickoffTimeUpdated(string fixtureID, uint256 kickoffTime);

    BetType[] public betTypes;

    // Entrance fee of 0.0001 Eth (10^14 Wei)
    uint256 public entranceFee = 10**14;

    // Cut off time for bets before KO time in seconds
    // i.e. all bets must be placed at time t where t < koTime - betCutOffTime
    uint256 betCutOffTime = 60 * 60;

    // Map each fixture ID to a map of BetType to an array of all addresses that have ever placed
    // bets for that fixture-result pair
    mapping(string => mapping(BetType => address[])) public historicalBetters;

    // activeBetters represents all addresses who currently have an amount staked on a fixture-result
    // The mapping(address => bool) pattern allows us to set address to true or false if an address
    // stakes/unstakes for that bet, and allows safer 'contains' methods on the betters
    mapping(string => mapping(BetType => mapping(address => bool)))
        public activeBetters;

    // Map each fixture ID to a map of BetType to a map of address to uint representing the amount of wei bet on that result
    mapping(string => mapping(BetType => mapping(address => uint256)))
        public amounts;

    // Map each fixture ID to a map of address to amount we owe the address owner
    mapping(string => mapping(address => uint256)) obligations;

    // Map each fixture ID to whether betting is open for this fixture
    mapping(string => BettingState) public bettingState;

    // Map each fixture ID to unix timestamp for its kickoff time
    mapping(string => uint256) public fixtureToKickoffTime;

    // Map oracle request ID to corresponding fixture ID
    mapping(bytes32 => string) public requestToFixture;

    constructor(
        string memory _sportsOracleURI,
        address _chainlink,
        address _link,
        bytes32 _jobId,
        uint256 _fee
    ) SportsOracleConsumer(_sportsOracleURI, _chainlink, _link, _jobId, _fee) {
        console.log(
            "Deploying a SportsBetting with sports oracle URI:",
            _sportsOracleURI
        );
        betTypes[0] = BetType.HOME;
        betTypes[1] = BetType.DRAW;
        betTypes[2] = BetType.AWAY;
    }

    // openBetForFixture makes an API call to oracle. It is expected that this
    // call will return the kickoff_time and the fulfillMultipleParameters func
    // will handle the state change to open
    // This is to ensure we don't open a bet until we have it's KO time and
    // know that it advanced enough in the future
    function openBetForFixture(string memory fixtureID) public onlyOwner {
        require(
            bettingState[fixtureID] != BettingState.OPEN,
            "Bet state is already OPEN for this fixture."
        );
        requestFixtureParameters(fixtureID);
    }

    function closeBetForFixture(string memory fixtureID) public onlyOwner {
        require(
            bettingState[fixtureID] != BettingState.CLOSED,
            "Bet state is already CLOSED for this fixture."
        );
        bettingState[fixtureID] = BettingState.CLOSED;
        emit BettingStateChanged(fixtureID, BettingState.CLOSED);
    }

    // Because the betting state transition OPEN -> AWAITING depends on
    // real-world time, we cannot simply rely on ctx state variables to
    // deduce if a contract remains open
    // In this function we deduce whether betting is open based on current
    // block timestamp, update the state accordingly, and return the result
    function shouldHaveCorrectBettingState(string memory fixtureID) private {
        uint256 ko = fixtureToKickoffTime[fixtureID];

        // If a bet is CLOSED, it can be OPENed if the kickoff time is
        // present and current timestamp is more than betCutOffTime before it
        if (
            bettingState[fixtureID] == BettingState.CLOSED &&
            block.timestamp <= ko - betCutOffTime &&
            betCutOffTime != 0
        ) {
            bettingState[fixtureID] = BettingState.OPEN;
            emit BettingStateChanged(fixtureID, BettingState.OPEN);
        }

        // If a bet is OPEN, it becomes AWAITING if the kickoff time is
        // present and current timestamp is more than betCutOffTime to
        // the right of it
        if (
            bettingState[fixtureID] == BettingState.OPEN &&
            block.timestamp > ko - betCutOffTime &&
            betCutOffTime != 0
        ) {
            bettingState[fixtureID] = BettingState.AWAITING;
            emit BettingStateChanged(fixtureID, BettingState.AWAITING);
        }
    }

    // Ideally the betting state will change from OPEN -> AWAITING
    // by virtue of a bet being placed too close to KO time, however
    // in the event this doesn't happen we allow a method for ctx owner
    // to force AWAITING
    // This also helps resolve bugs whereby the bet is marked as fulfilled
    // when it is not
    function awaitBetForFixture(string memory fixtureID) public onlyOwner {
        require(
            bettingState[fixtureID] != BettingState.AWAITING,
            "Bet state is already AWAITING for this fixture."
        );
        bettingState[fixtureID] = BettingState.AWAITING;
        emit BettingStateChanged(fixtureID, BettingState.AWAITING);
    }

    function fulfillBetForFixture(string memory fixtureID) public {
        require(
            bettingState[fixtureID] != BettingState.FULFILLED,
            "Bet state is already FULFILLED for this fixture."
        );
        requestFixtureParameters(fixtureID);
    }

    function stake(string memory fixtureID, BetType betType) public payable {
        shouldHaveCorrectBettingState(fixtureID);
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet activity is not open for this fixture."
        );
        require(msg.value >= entranceFee, "Amount is below minimum.");
        amounts[fixtureID][betType][msg.sender] += msg.value;
        historicalBetters[fixtureID][betType].push(msg.sender);
        activeBetters[fixtureID][betType][msg.sender] = true;
        emit BetStaked(msg.sender, fixtureID, msg.value, betType);
    }

    // Removes all stake in fixtureID-BetType combo
    function unstake(string memory fixtureID, BetType betType) public {
        shouldHaveCorrectBettingState(fixtureID);
        require(
            bettingState[fixtureID] == BettingState.OPEN,
            "Bet activity is not open for this fixture."
        );
        uint256 amountToUnstake = amounts[fixtureID][betType][msg.sender];
        require(amountToUnstake > 0, "No stake on this address-result.");

        amounts[fixtureID][betType][msg.sender] = 0;
        activeBetters[fixtureID][betType][msg.sender] = false;
        payable(msg.sender).transfer(amountToUnstake);
        emit BetUnstaked(msg.sender, fixtureID, betType);
    }

    function requestFixtureParameters(string memory fixtureID) private {
        bytes32 requestID = requestMultipleParameters(fixtureID);
        requestToFixture[requestID] = fixtureID;
        emit RequestedFixtureParameters(requestID, fixtureID);
    }

    function fulfillMultipleParameters(
        bytes32 _requestId,
        string memory _resultResponse,
        uint256 _kickoffResponse
    ) internal override recordChainlinkFulfillment(_requestId) {
        string memory fixtureID = requestToFixture[_requestId];

        emit RequestFixtureParametersFulfilled(
            _requestId,
            fixtureID,
            _resultResponse,
            _kickoffResponse
        );

        // This oracle result serves two purposes
        // 1. Receive fixture KO time to deduce correct betting state
        fulfillKickoffTime(fixtureID, _kickoffResponse);
        shouldHaveCorrectBettingState(fixtureID);

        // 2. Receive fixture result to perform payout logic if state
        // is AWAITING
        if (
            bettingState[fixtureID] == BettingState.AWAITING &&
            bytes(_resultResponse).length > 0
        ) {
            fulfillFixtureResult(fixtureID, _resultResponse);
        }
    }

    function fulfillKickoffTime(
        string memory fixtureID,
        uint256 _kickoffResponse
    ) private {
        if (_kickoffResponse != fixtureToKickoffTime[fixtureID]) {
            fixtureToKickoffTime[fixtureID] = _kickoffResponse;
            emit KickoffTimeUpdated(fixtureID, _kickoffResponse);
        }
    }

    function fulfillFixtureResult(
        string memory fixtureID,
        string memory _resultResponse
    ) private {
        BetType result = getFixtureResultFromAPIResponse(_resultResponse);

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

        bettingState[fixtureID] = BettingState.FULFILLED;
        emit BettingStateChanged(fixtureID, BettingState.FULFILLED);
    }

    function getFixtureResultFromAPIResponse(string memory _resultResponse)
        private
        returns (BetType)
    {
        if (strEqual(_resultResponse, "HOME")) {
            return BetType.HOME;
        } else if (strEqual(_resultResponse, "DRAW")) {
            return BetType.DRAW;
        } else if (strEqual(_resultResponse, "AWAY")) {
            return BetType.AWAY;
        }
        revert("Unexpected API Fixture result");
    }

    function strEqual(string memory a, string memory b) private returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function getLosingFixtureOutcomes(BetType outcome)
        private
        returns (BetType[] memory)
    {
        BetType[] memory losingOutcomes;
        for (uint256 i = 0; i <= betTypes.length; i++) {
            if (betTypes[i] != outcome) {
                losingOutcomes.push(betTypes[i]);
            }
        }
        return losingOutcomes;
    }

    function getTotalAmountBetOnFixtureOutcomes(
        string memory fixtureID,
        BetType[] memory outcomes
    ) private returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < outcomes.length; i++) {
            amount += getTotalAmountBetOnFixtureOutcome(fixtureID, outcomes[i]);
        }
        return amount;
    }

    function getTotalAmountBetOnFixtureOutcome(
        string memory fixtureID,
        BetType outcome
    ) private returns (uint256) {
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
    ) private {
        for (
            uint256 i = 0;
            i < historicalBetters[fixtureID][result].length;
            i++
        ) {
            address better = historicalBetters[fixtureID][result][i];
            if (activeBetters[fixtureID][result][better]) {
                uint256 betterAmount = amounts[fixtureID][result][better];
                uint256 betterObligation = (betterAmount / winningAmount) *
                    totalAmount;
                obligations[fixtureID][better] = betterObligation;

                amounts[fixtureID][result][better] = 0;
                activeBetters[fixtureID][result][better] = false;
                payable(msg.sender).transfer(betterObligation);
                emit BetPayout(msg.sender, fixtureID, betterObligation);
            }
        }
    }
}
