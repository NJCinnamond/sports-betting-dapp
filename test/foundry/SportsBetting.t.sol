//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "contracts/SportsBetting.sol";
import "contracts/mock/IERC20.sol";

abstract contract HelperContract {
    string constant mockURI = "mockURI";
    uint256 linkFee = 1;
    address constant chainlinkDevRel = 0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656;
    SportsBetting sportsBetting; 

}

contract SportsBettingTest is Test, HelperContract {
    function setUp() public {
        sportsBetting = new SportsBetting(
            mockURI,
            chainlinkDevRel,
            formatBytes32String("example"),
            linkFee
        );
    }

    function testSetFixtureBettingState(string fixtureID, SportsBetting.BettingState state) public {
        sportsBetting.setFixtureBettingState(fixtureID, state);
        assertEq(sportsBetting.bettingState[fixtureID], state);
    }
}