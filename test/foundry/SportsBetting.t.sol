//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "contracts/test/SportsBettingTest.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

    string constant mockURI = "mockURI";
    uint256 linkFee = 1e17; // 1e17 = 0.1 LINK
    address constant chainlinkDevRel = 0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656;
    SportsBettingTest sportsBetting; 
    MockDAI mockDAI;
    MockLINK mockLINK;

    address constant addr1 = 0xe58b52D74FA00f94d61C6Dcb73D79a8ea704a36B;
}

contract SportsBettingTestSuite is Test, HelperContract {
    function setUp() public {
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
    }

    // testSetFixtureBettingStateClosed asserts that, when a fixture is called with Closed,
    // 1. BettingState[fixtureID] becomes CLOSED
    // 2. The historical betters arrays for each fixture ID remain empty
    function testSetFixtureBettingStateClosed(string memory fixtureID) public {
        SportsBetting.BettingState state = SportsBetting.BettingState.CLOSED;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));

        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, state);

        sportsBetting.setFixtureBettingStateTest(fixtureID, SportsBetting.BettingState(state));

        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(state), actualState);

        // We expect the historical betters arrays to not be initialized as betting state is closed
        assertEq(sportsBetting.getHistoricalBettersLength(fixtureID,SportsBettingLib.FixtureResult.HOME), 0);
        assertEq(sportsBetting.getHistoricalBettersLength(fixtureID,SportsBettingLib.FixtureResult.DRAW), 0);
        assertEq(sportsBetting.getHistoricalBettersLength(fixtureID,SportsBettingLib.FixtureResult.AWAY), 0);
    }

    // testSetFixtureBettingStateOpen asserts that, when a fixture is called with Open,
    // 1. BettingState[fixtureID] becomes OPEN
    // 2. The historical betters arrays for each fixture ID is initialized to [zero address]
    function testSetFixtureBettingStateOpen(string memory fixtureID) public {
        SportsBetting.BettingState state = SportsBetting.BettingState.OPEN;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));

        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, state);

        sportsBetting.setFixtureBettingStateTest(fixtureID, SportsBetting.BettingState(state));

        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(state), actualState);

        // When a fixture is opened for betting we expect all historical betters arrays to be initialized with zero address
        assertEq(sportsBetting.getHistoricalBettersLength(fixtureID,SportsBettingLib.FixtureResult.HOME), 1);
        assertEq(sportsBetting.getHistoricalBettersLength(fixtureID,SportsBettingLib.FixtureResult.DRAW), 1);
        assertEq(sportsBetting.getHistoricalBettersLength(fixtureID,SportsBettingLib.FixtureResult.AWAY), 1);
        assertEq(sportsBetting.historicalBetters(fixtureID,SportsBettingLib.FixtureResult.HOME,0), address(0x0));
        assertEq(sportsBetting.historicalBetters(fixtureID,SportsBettingLib.FixtureResult.DRAW,0), address(0x0));
        assertEq(sportsBetting.historicalBetters(fixtureID,SportsBettingLib.FixtureResult.AWAY,0), address(0x0));
    }

    // testShouldCloseBetForFixtureIsTooLate asserts that, when closeBetForFixture is called on a fixture
    // that has a kickoff time too close
    // 1. The betting state is closed
    //
    // In this test case, the fixture is eligible to become closed because
    // 1. Fixture is in OPENING state
    // 2. Warped block timestamp is to the right of kickoff time - BET_CUTOFF_TIME
    function testShouldCloseBetForFixtureIsTooLate(string memory fixtureID, uint256 ko) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        // Set kickoff time
        uint256 kickoffTime = ko;
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp to too close to kickoff time to open bet
        uint256 warpTime = kickoffTime - sportsBetting.BET_CUTOFF_TIME() + 1;
        vm.warp(warpTime);

        // Expect state to be CLOSED
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.closeBetForFixture(fixtureID);

        // Assert state is closed
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);
    }

    // testShouldCloseBetForFixtureIsTooEarly asserts that, when closeBetForFixture is called on a fixture
    // that has a kickoff time too early or too far in future
    // 1. The betting state is closed
    //
    // In this test case, the fixture is eligible to become closed because
    // 1. Fixture is in OPENING state
    // 2a. Warped block timestamp is to the left of kickoff time - BET_ADVANCE_TIME
    // 2b. Warped block timestamp is to the right of kickoff time - BET_CUTOFF_TIME
    function testShouldCloseBetForFixtureIsTooEarlyOrLate(string memory fixtureID, uint256 ko) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Expect state to be CLOSED
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Set kickoff time
        uint256 kickoffTime = ko;
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        /////////////////////////////////////////////////////////////
        // Test 1
        // 
        // Warped block timestamp is to the immediate left of kickoff time - BET_ADVANCE_TIME
        /////////////////////////////////////////////////////////////

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        // Warp timestamp to too far from kickoff time
        uint256 warpTime = kickoffTime - sportsBetting.BET_ADVANCE_TIME() - 1;
        vm.warp(warpTime);

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.closeBetForFixture(fixtureID);

        // Assert state is closed
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);

        /////////////////////////////////////////////////////////////
        // Test 2
        // 
        // Warped block timestamp is to the immediate right of kickoff time - BET_CUTOFF_TIME
        /////////////////////////////////////////////////////////////

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        // Warp timestamp to too close to kickoff time to open bet
        warpTime = kickoffTime - sportsBetting.BET_CUTOFF_TIME() + 1;
        vm.warp(warpTime);

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.closeBetForFixture(fixtureID);

        // Assert state is closed
        actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);
    }

    // testShouldFailClosingBetForFixtureAlreadyClosed asserts that, when closeBetForFixture is called on a fixture
    // that is already closed
    // 1. The call should revert
    function testShouldFailClosingBetForFixtureAlreadyClosed(string memory fixtureID, uint256 ko) public {
        // Make this fixture CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.CLOSED); 

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Expect revert
        vm.expectRevert("Bet state is already CLOSED.");

        // Act
        sportsBetting.closeBetForFixture(fixtureID);
    }

    // testShouldNotCloseBetForFixtureShouldBecomeOpen asserts that, when closeBetForFixture is called on a fixture
    // that is OPENING but has a kickoff time within eligible window (i.e. should become OPEN)
    // 1. The call should revert
    //
    // In this test case, the fixture is ineligible to become closed because
    // 1. Fixture is in OPENING state
    // 2a. Warped block timestamp is to the right of kickoff time - BET_ADVANCE_TIME or
    // 2b. Warped block timestamp is to the left of kickoff time - BET_CUTOFF_TIME or
    //
    // Context: If a fixture is OPENING, the contract is awaiting the fulfillment of kickoff time
    // to determine if it OPENS or CLOSES. If the kickoff time is within eligible window to become
    // OPEN, then call to closeBetForFixture should revert
    function testShouldNotCloseBetForFixtureShouldBecomeOpen(string memory fixtureID, uint256 ko) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        /////////////////////////////////////////////////////////////
        // Test 1
        // 
        // Warped block timestamp is to the immediate right of kickoff time - BET_ADVANCE_TIME
        // and to the left of kickoff time - BET_CUTOFF_TIME
        /////////////////////////////////////////////////////////////

        // Set kickoff time
        uint256 kickoffTime = ko;
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp to too far from kickoff time
        uint256 warpTime = kickoffTime - sportsBetting.BET_ADVANCE_TIME() + 1;
        vm.warp(warpTime);

        // Expect revert
        vm.expectRevert("Fixture ineligible to be closed.");

        // Act
        sportsBetting.closeBetForFixture(fixtureID);

        /////////////////////////////////////////////////////////////
        // Test 2
        // 
        // Warped block timestamp is to the immediate left of kickoff time - BET_CUTOFF_TIME
        // and to the right of kickoff time - BET_ADVANCE_TIME
        /////////////////////////////////////////////////////////////

        // Warp timestamp to too far from kickoff time
        warpTime = kickoffTime - sportsBetting.BET_CUTOFF_TIME() - 1;
        vm.warp(warpTime);

        // Expect revert
        vm.expectRevert("Fixture ineligible to be closed.");

        // Act
        sportsBetting.closeBetForFixture(fixtureID);
    }

    // testShouldFailOpeningBetForFixtureAlreadyClosed asserts that, when openBetForFixture is called on a fixture
    // that is not CLOSED OR OPENING
    // 1. The call should revert
    function testShouldFailOpeningBetForFixtureAlreadyClosed(string memory fixtureID) public {
        // Make this fixture OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN); 

        // Expect revert
        vm.expectRevert("State must be CLOSED or OPENING.");

        // Act
        sportsBetting.openBetForFixture(fixtureID);
    }

    // testShouldSetOpeningBetForFixtureIfClosedOrOpening asserts that, when openBetForFixture is called on a fixture
    // that is CLOSED OR OPENING and user has >= required LINK
    // 1. The call set the fixture to OPENING
    function testShouldSetOpeningBetForFixtureIfClosedOrOpening(string memory fixtureID) public {
        // Spoof addr1 for having required LINK
        uint256 linkAmount = sportsBetting.linkFee() + 1;
        sportsBetting.setUserToLinkCheat(addr1, linkAmount);

        /////////////////////////////////////////////////////////////
        // Test 1
        // 
        // Fixture is CLOSED
        /////////////////////////////////////////////////////////////

        // Make this fixture CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.CLOSED); 

        // Expect state to be OPENING
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.OPENING;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        vm.prank(addr1);
        vm.mockCall(
            address(mockLINK),
            linkAmount,
            abi.encodeWithSelector(mockLINK.transferAndCall.selector),
            abi.encode(true)
        );
        sportsBetting.openBetForFixture(fixtureID);

        // Asset state is Opening
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);

        /////////////////////////////////////////////////////////////
        // Test 2
        // 
        // Fixture is OPENING
        /////////////////////////////////////////////////////////////

        // Spoof addr1 for having required LINK
        sportsBetting.setUserToLinkCheat(addr1, linkAmount);

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        // Expect state to be OPENING
        expectedState = SportsBetting.BettingState.OPENING;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        vm.prank(addr1);
        vm.mockCall(
            address(mockLINK),
            linkAmount,
            abi.encodeWithSelector(mockLINK.transferAndCall.selector),
            abi.encode(true)
        );
        sportsBetting.openBetForFixture(fixtureID);

        // Asset state is Opening
        actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);
    }

    // testShouldNotSetOpeningBetForFixtureIfUserHasInsufficientLink asserts that, when openBetForFixture is called on a fixture
    // that is CLOSED OR OPENING and user has < required LINK
    // 1. The call reverts
    function testShouldNotSetOpeningBetForFixtureIfUserHasInsufficientLink(string memory fixtureID) public {
        // Spoof addr1 for having less than required
        uint256 linkAmount = sportsBetting.linkFee() - 1;
        sportsBetting.setUserToLinkCheat(addr1, linkAmount);

        // Make this fixture CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.CLOSED); 

        // Expect state to be CLOSED
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Expect revert
        vm.expectRevert("You haven't sent enough LINK.");

        // Act
        vm.prank(addr1);
        sportsBetting.openBetForFixture(fixtureID);

        // Asset state is CLOSED
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);
    }

    // testShouldFailAwaitingForFixtureNotOpen asserts that, when awaitBetForFixture is called on a fixture
    // that is not OPEN
    // 1. The call should revert
    function testShouldFailAwaitingForFixtureNotOpen(string memory fixtureID) public {
        // Make this fixture CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.CLOSED); 

        // Expect revert
        vm.expectRevert("Bet state must be OPEN.");

        // Act
        sportsBetting.awaitBetForFixture(fixtureID);
    }

    // testShouldNotSetAwaitingForFixtureTooEarly asserts that, when awaitBetForFixture is called on a fixture
    // that is OPEN but current timestamp < kickoff time - BET_CUTOFF_TIME
    // 1. The call should revert
    function testShouldFailAwaitingForFixtureNotOpen(string memory fixtureID, uint256 ko) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Make this fixture OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN); 

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp to too far from kickoff time
        uint256 warpTime = ko - sportsBetting.BET_CUTOFF_TIME();
        vm.warp(warpTime);

        // Expect revert
        vm.expectRevert("Fixture ineligible for AWAITING.");

        // Act
        sportsBetting.awaitBetForFixture(fixtureID);
    }

    // testShouldSetAwaitingForFixture asserts that, when awaitBetForFixture is called on a fixture
    // that is OPEN and current timestamp >= kickoff time - BET_CUTOFF_TIME
    // 1. The call should revert
    function testShouldSetAwaitingForFixture(string memory fixtureID, uint256 ko) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Make this fixture OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN); 

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp to too far from kickoff time
        uint256 warpTime = ko - sportsBetting.BET_CUTOFF_TIME() + 1;
        vm.warp(warpTime);

        // Set expected state
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.AWAITING;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.awaitBetForFixture(fixtureID);

        // Assert state is closed
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);
    }

}