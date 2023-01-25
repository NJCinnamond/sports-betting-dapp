//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "../SportsBetting.sol";
import "../SportsBettingLib.sol";

contract SportsBettingTest is SportsBetting {
    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _dai,
        address _link,
        string memory _jobId,
        uint256 _fee,
        uint256 _commissionRate
    )
        SportsBetting(
            _sportsOracleURI,
            _oracle,
            _dai,
            _link,
            _jobId,
            _fee,
            _commissionRate
        )
    {}

    function initializeHistoricalBettersTest(string memory fixtureID) public {
        initializeHistoricalBetters(fixtureID);
    }

    function getHistoricalBettersLength(
        string memory fixtureID,
        SportsBettingLib.BetType betType
    ) public view returns (uint256) {
        return historicalBetters[fixtureID][betType].length;
    }

    function setHistoricalBetters(
        string memory fixtureID,
        SportsBettingLib.BetType betType,
        address[] memory addresses
    ) public {
        historicalBetters[fixtureID][betType] = addresses;
    }

    function getStakeSummaryForUserTest(string memory fixtureID, address user)
        public
        view
        returns (uint256[3] memory)
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
        SportsBettingLib.BetType result,
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

    function getTotalAmountBetOnFixtureOutcomesTest(
        string memory fixtureID,
        SportsBettingLib.BetType[] memory outcomes
    ) public view returns (uint256) {
        return getTotalAmountBetOnFixtureOutcomes(fixtureID, outcomes);
    }

    function updateFixtureResultTest(string memory fixtureID, uint256 _result)
        public
    {
        updateFixtureResult(fixtureID, _result);
    }

    function removeStakeStateTest(
        string memory fixtureID,
        SportsBettingLib.BetType betType,
        uint256 amount,
        address staker
    ) public {
        removeStakeState(fixtureID, betType, amount, staker);
    }
}
