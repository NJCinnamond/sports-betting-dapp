//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "contracts/test/SportsBettingTest.sol";

contract MockDAI is ERC20 {
    constructor() ERC20("Name", "DAI") {
        this;
    }
}

contract MockLINK is ERC20 {
    constructor() ERC20("Name", "LINK") {
        this;
    }

    // Mock LINK token transferAndCall method
    function transferAndCall(address, uint, bytes memory)
        public pure
        returns (bool success)
    {
        return true;
    }
}

abstract contract HelperContract {
    event BettingStateChanged(string fixtureID, SportsBetting.BettingState state);

    event RequestFixtureKickoffFulfilled(
        bytes32 indexed requestId,
        string fixtureID,
        uint256 kickoff
    );

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

    event BetPayout(address indexed better, string fixtureID, uint256 amount);

    event BetCommissionPayout(string indexed fixtureID, uint256 amount);

    string constant mockURI = "mockURI";
    uint256 linkFee = 1e17; // 1e17 = 0.1 LINK
    address constant chainlinkDevRel = 0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656;
    SportsBettingTest sportsBetting; 
    MockDAI mockDAI;
    MockLINK mockLINK;

    address constant addr1 = 0xe58b52D74FA00f94d61C6Dcb73D79a8ea704a36B;
    address constant addr2 = 0x07401dc21CcA4aF0f4a50f7DFCCE4c795f671cD7;
}
