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

    // Wrapper for setting fixture betting state and emitting event
    function setFixtureBettingStateTest(
        string memory fixtureID,
        BettingState state
    ) public {
        setFixtureBettingState(fixtureID, state);
    }

    function shouldHaveCorrectBettingStateTest(string memory fixtureID) public {
        shouldHaveCorrectBettingState(fixtureID);
    }

    function fulfillKickoffTimeTest(
        string memory fixtureID,
        uint256 _kickoffResponse
    ) public {
        fulfillKickoffTime(fixtureID, _kickoffResponse);
    }
}
