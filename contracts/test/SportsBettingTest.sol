//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "../SportsBetting.sol";
import "../SportsBettingLib.sol";

contract SportsBettingTest is SportsBetting {
    uint256 public linkFee;

    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _dai,
        address _link,
        string memory _jobId,
        uint256 _fee
    )
        SportsBetting(
            _sportsOracleURI,
            _oracle,
            _dai,
            _link,
            _jobId,
            _fee
        )
    {
        linkFee = _fee;
    }

    function handleWithdrawPayoutTest(
        string memory fixtureID
    ) public {
        handleWithdrawPayout(fixtureID);
    }

    function setFixtureResultCheat(
        string memory fixtureID,
        SportsBettingLib.FixtureResult result
    ) public {
        results[fixtureID] = result;
    }

    function setUserWasPaidCheat(
        string memory fixtureID,
        address user,
        bool wasPaid
    ) public {
        userWasPaid[fixtureID][user] = wasPaid;
    }

    function setActiveBetterCheat(
        string memory fixtureID, 
        SportsBettingLib.FixtureResult betType,
        address staker,
        bool isActive
    ) public {
        activeBetters[fixtureID][betType][staker] = isActive;
    }

    function setUserStakeCheat(
        string memory fixtureID, 
        SportsBettingLib.FixtureResult betType,
        address staker,
        uint256 amount
    ) public {
        amounts[fixtureID][betType][staker] = amount;
    }

    function setTotalStakeCheat(
        string memory fixtureID, 
        SportsBettingLib.FixtureResult betType,
        uint256 amount
    ) public {
        totalAmounts[fixtureID][betType] = amount;
    }

    function setUserToLinkCheat(address addr, uint256 amount) public {
        userToLink[addr] = amount;
    }

    function setRequestKickoffToFixtureCheat(bytes32 requestId, string memory fixtureId) public {
        requestKickoffToFixture[requestId] = fixtureId;
    }

    function setRequestResultToFixtureCheat(bytes32 requestId, string memory fixtureId) public {
        requestResultToFixture[requestId] = fixtureId;
    }

    function setFixtureBettingStateCheat(
        string memory fixtureID,
        BettingState state
    ) public {
        bettingState[fixtureID] = state;
    }

    function setFixtureKickoffTimeCheat(
        string memory fixtureID,
        uint256 ko
    ) public {
        fixtureToKickoffTime[fixtureID] = ko;
    }

    function initializeHistoricalBettersTest(string memory fixtureID) public {
        initializeHistoricalBetters(fixtureID);
    }

    function getHistoricalBettersLength(
        string memory fixtureID,
        SportsBettingLib.FixtureResult betType
    ) public view returns (uint256) {
        return historicalBetters[fixtureID][betType].length;
    }

    function setHistoricalBetters(
        string memory fixtureID,
        SportsBettingLib.FixtureResult betType,
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

    /*function shouldHaveCorrectBettingStateTest(string memory fixtureID) public {
        shouldHaveCorrectBettingState(fixtureID);
    }*/

    function fulfillFixtureKickoffTimeTest(bytes32 requestId, uint256 ko)
        public
    {
        fulfillFixtureKickoffTime(requestId, ko);
    }

    function fulfillFixtureResultTest(bytes32 requestId, uint256 result) 
        public
    {
        fulfillFixtureResult(requestId, result);
    }

    function updateKickoffTimeTest(string memory fixtureID, uint256 ko)
        public
    {
        updateKickoffTime(fixtureID, ko);
    }

    /*function fulfillFixturePayoutObligationsTest(
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
    }*/

    function getTotalAmountBetOnFixtureOutcomesTest(
        string memory fixtureID,
        SportsBettingLib.FixtureResult[] memory outcomes
    ) public view returns (uint256) {
        return getTotalAmountBetOnFixtureOutcomes(fixtureID, outcomes);
    }

    /*function updateFixtureResultTest(string memory fixtureID, uint256 _result)
        public
    {
        updateFixtureResult(fixtureID, _result);
    }*/
}
