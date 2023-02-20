//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "forge-std/InvariantTest.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import "contracts/test/SportsBettingTest.sol";
import { MockDAI, MockLINK, HelperContract } from "test/foundry/helpers.sol";

contract SportsBettingInvariantHandler is CommonBase, StdCheats, StdUtils {
    SportsBettingTest sportsBetting;
    MockDAI mockDAI;

    uint256 public ghost_homeStakeSum;
    uint256 public ghost_drawStakeSum;
    uint256 public ghost_awayStakeSum;

    constructor(
        SportsBettingTest _sportsBetting,
        MockDAI _mockDAI
    ) {
        sportsBetting = _sportsBetting;
        mockDAI = _mockDAI;
    }

    function stake(uint256 betType, uint256 amount) external {
        string memory fixtureID = "dummyFixture";

        vm.mockCall(
            address(mockDAI),
            abi.encodeWithSelector(mockDAI.transferFrom.selector),
            abi.encode(true)
        );

        // Bound bet type to HOME, DRAW, AWAY
        betType = bound(betType, uint256(SportsBettingLib.FixtureResult.HOME), uint256(SportsBettingLib.FixtureResult.AWAY));
        SportsBettingLib.FixtureResult betTypeEnum = SportsBettingLib.FixtureResult(betType);

        // Ensure fixture is OPEN and should not be awaiting
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN);
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, block.timestamp + 86400);
        sportsBetting.stake(fixtureID, betTypeEnum, amount);

        if (betTypeEnum == SportsBettingLib.FixtureResult.HOME) {
            ghost_homeStakeSum += amount;
        } else if (betTypeEnum == SportsBettingLib.FixtureResult.DRAW) {
            ghost_drawStakeSum += amount;
        } else if (betTypeEnum == SportsBettingLib.FixtureResult.AWAY) {
            ghost_awayStakeSum += amount;
        }
    }

    function unstake(uint256 betType, uint256 amount) external {
        string memory fixtureID = "dummyFixture";

        vm.mockCall(
            address(mockDAI),
            abi.encodeWithSelector(mockDAI.transfer.selector),
            abi.encode(true)
        );

        // Bound bet type to HOME, DRAW, AWAY
        betType = bound(betType, uint256(SportsBettingLib.FixtureResult.HOME), uint256(SportsBettingLib.FixtureResult.AWAY));
        SportsBettingLib.FixtureResult betTypeEnum = SportsBettingLib.FixtureResult(betType);

        // Ensure fixture is OPEN and should not be awaiting
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN);
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, block.timestamp + 86400);
        sportsBetting.unstake(fixtureID, betTypeEnum, amount);

        if (betTypeEnum == SportsBettingLib.FixtureResult.HOME) {
            ghost_homeStakeSum -= amount;
        } else if (betTypeEnum == SportsBettingLib.FixtureResult.DRAW) {
            ghost_drawStakeSum -= amount;
        } else if (betTypeEnum == SportsBettingLib.FixtureResult.AWAY) {
            ghost_awayStakeSum -= amount;
        }
    }
}

contract SportsBettingInvariantTest is Test, InvariantTest {
    SportsBettingInvariantHandler sportsBettingHandler;
    SportsBettingTest sportsBetting;
    MockDAI mockDAI;
    MockLINK mockLINK;

    function setUp() public {
        string memory mockURI = "mockURI";
        uint256 linkFee = 1e17; // 1e17 = 0.1 LINK
        address chainlinkDevRel = 0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656;

        mockDAI = new MockDAI();
        mockLINK = new MockLINK();
        sportsBetting = new SportsBettingTest(
            mockURI,
            chainlinkDevRel,
            address(mockDAI),
            address(mockLINK),
            "7599d3c8f31e4ce78ad2b790cbcfc673",
            linkFee
        );
        sportsBettingHandler = new SportsBettingInvariantHandler(
            sportsBetting,
            mockDAI
        );

        targetContract(address(sportsBettingHandler));
    }

    function invariant_total_amounts() external {
        string memory fixtureID = "dummyFixture";

        // HOME
        assertEq(
            sportsBetting.totalAmounts(fixtureID, SportsBettingLib.FixtureResult.HOME),
            sportsBettingHandler.ghost_homeStakeSum()
        );

        // DRAW
        assertEq(
            sportsBetting.totalAmounts(fixtureID, SportsBettingLib.FixtureResult.DRAW),
            sportsBettingHandler.ghost_drawStakeSum()
        );
        
        // AWAY
        assertEq(
            sportsBetting.totalAmounts(fixtureID, SportsBettingLib.FixtureResult.AWAY),
            sportsBettingHandler.ghost_awayStakeSum()
        );
    }
}