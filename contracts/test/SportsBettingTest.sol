//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "../SportsBetting.sol";

contract SportsBettingTest is SportsBetting {
    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _link,
        bytes32 _jobId,
        uint256 _fee
    ) SportsBetting(_sportsOracleURI, _oracle, _link, _jobId, _fee) {}

    function getStakeSummaryForUserTest(string memory fixtureID, address user)
        public
        returns (StakeSummary memory)
    {
        return getStakeSummaryForUser(fixtureID, user);
    }

    // Wrapper for setting fixture betting state and emitting event
    function setFixtureBettingStateTest(
        string memory fixtureID,
        BettingState state
    ) public {
        setFixtureBettingState(fixtureID, state);
    }

    function handleClosingBetsForFixtureTest(string memory fixtureID) public {
        handleClosingBetsForFixture(fixtureID);
    }

    function shouldHaveCorrectBettingStateTest(string memory fixtureID) public {
        shouldHaveCorrectBettingState(fixtureID);
    }

    function updateKickoffTimeTest(string memory fixtureID, uint256 _ko)
        public
    {
        updateKickoffTime(fixtureID, _ko);
    }

    function fulfillFixturePayoutObligationsTest(
        string memory fixtureID,
        BetType result,
        uint256 winningAmount,
        uint256 totalAmount
    ) public {
        fulfillFixturePayoutObligations(
            fixtureID,
            result,
            winningAmount,
            totalAmount
        );
    }

    function getLosingFixtureOutcomesTest(BetType outcome)
        public
        view
        returns (BetType[] memory)
    {
        return getLosingFixtureOutcomes(outcome);
    }

    function getTotalAmountBetOnFixtureOutcomesTest(
        string memory fixtureID,
        BetType[] memory outcomes
    ) public view returns (uint256) {
        return getTotalAmountBetOnFixtureOutcomes(fixtureID, outcomes);
    }

    function getFixtureResultFromAPIResponseTest(
        string memory fixtureID,
        uint256 _result
    ) public returns (BetType) {
        return getFixtureResultFromAPIResponse(fixtureID, _result);
    }
}
