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

    event RequestFixtureKickoffFulfilled(
        bytes32 indexed requestId,
        string fixtureID,
        uint256 kickoff
    );

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
    // that has a kickoff time too early
    // 1. The betting state is closed
    //
    // In this test case, the fixture is eligible to become closed because
    // 1. Fixture is in OPENING state
    // 2. Warped block timestamp is to the left of kickoff time - BET_ADVANCE_TIME
    function testShouldCloseBetForFixtureIsTooEarly(string memory fixtureID, uint256 ko, uint256 warpTime) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Assume block.timpestam is to the left of kickoff time - BET_ADVANCE_TIME
        vm.assume(warpTime < ko - sportsBetting.BET_ADVANCE_TIME());

        // Expect state to be CLOSED
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        // Warp timestamp to too far from kickoff time
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
    }

    // testShouldCloseBetForFixtureIsTooLate asserts that, when closeBetForFixture is called on a fixture
    // that has a kickoff time too far in future
    // 1. The betting state is closed
    //
    // In this test case, the fixture is eligible to become closed because
    // 1. Fixture is in OPENING state
    // 2. Warped block timestamp is to the right of kickoff time - BET_CUTOFF_TIME
    function testShouldCloseBetForFixtureIsTooLate(string memory fixtureID, uint256 ko, uint256 warpTime) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);

        // Assume block.timpestam is to the right of kickoff time - BET_CUTOFF_TIME
        vm.assume(warpTime > ko - sportsBetting.BET_CUTOFF_TIME());

        // Expect state to be CLOSED
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 

        // Warp timestamp
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
    // 2. Warped block timestamp is to the right of kickoff time - BET_ADVANCE_TIME and
    //    warped block timestamp is to the left of kickoff time - BET_CUTOFF_TIME or
    //
    // Context: If a fixture is OPENING, the contract is awaiting the fulfillment of kickoff time
    // to determine if it OPENS or CLOSES. If the kickoff time is within eligible window to become
    // OPEN, then call to closeBetForFixture should revert
    function testShouldNotCloseBetForFixtureShouldBecomeOpen(string memory fixtureID, uint256 ko, uint256 warpTime) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);
        // Bound block timestamp to OPEN window
        // i.e. is greater than or equal to kickoff time - BET_ADVANCE_TIME
        // AND is less than kickoff_time - BET_CUTOFF_TIME
        warpTime = bound(warpTime, ko - sportsBetting.BET_ADVANCE_TIME(), ko - sportsBetting.BET_CUTOFF_TIME());

        // Make this fixture OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING); 
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp
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
    function testShouldSetOpeningBetForFixtureIfClosedOrOpening(string memory fixtureID, uint256 state) public {
        // Spoof addr1 for having required LINK
        uint256 linkAmount = sportsBetting.linkFee() + 1;
        sportsBetting.setUserToLinkCheat(addr1, linkAmount);

        // Bound state to either CLOSED or OPENING
        state = bound(state, uint256(SportsBetting.BettingState.CLOSED), uint256(SportsBetting.BettingState.OPENING));

        // Infer state from input
        SportsBetting.BettingState inferredState = SportsBetting.BettingState(state);

        // Make this fixture CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, inferredState); 

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
    // that is OPEN but current timestamp <= kickoff time - BET_CUTOFF_TIME
    // 1. The call should revert
    function testShouldNotSetAwaitingForFixtureTooEarly(string memory fixtureID, uint256 ko, uint256 warpTime) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);
        // This test case assumes block timestamp is less than kickoff time - BET_CUTOFF_TIME
        vm.assume(warpTime < ko - sportsBetting.BET_CUTOFF_TIME());

        // Make this fixture OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN); 

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp to too far from kickoff time
        vm.warp(warpTime);

        // Expect revert
        vm.expectRevert("Fixture ineligible for AWAITING.");

        // Act
        sportsBetting.awaitBetForFixture(fixtureID);
    }

    // testShouldSetAwaitingForFixture asserts that, when awaitBetForFixture is called on a fixture
    // that is OPEN and current timestamp >= kickoff time - BET_CUTOFF_TIME
    // 1. The call should revert
    function testShouldSetAwaitingForFixture(string memory fixtureID, uint256 ko, uint256 warpTime) public {
        // TODO: Assert somewhere in SportsBetting ctx that ko is a reasonably large value so we
        // can prevent underflow
        vm.assume(ko > 1e9);
        // This test case assumes block timestamp is greater than or equal to kickoff time - BET_CUTOFF_TIME
        vm.assume(warpTime >= ko - sportsBetting.BET_CUTOFF_TIME());

        // Make this fixture OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN); 

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp timestamp to too far from kickoff time
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

    // testShouldRevertOnInvalidKickoffTimeFulfillment asserts that, when
    // fulfillFixtureKickoffTime is called with an invalid requestId and therefore no matching fixtureID it
    // 1. Reverts
    function testShouldRevertOnInvalidKickoffTimeFulfillment(
        bytes32 requestId,
        uint256 ko
    ) 
    public {
        // Expect revert
        vm.expectRevert("No fixture matches request ID.");

        // Act
        sportsBetting.fulfillFixtureKickoffTimeTest(requestId, ko);
    }

    // testFixtureShouldBecomeOpenOnValidKickoffTimeFulfillment asserts that, when
    // fulfillFixtureKickoffTime is called with a valid fixtureID and kickoff time eligible for fixture
    // to be opened, it
    // 1. Emits RequestFixtureKickoffFulfilled event
    // 2. Sets fixture betting state to OPEN
    // 3. Emits BettingStateChanged event
    function testOpeningFixtureShouldBecomeOpenOnValidKickoffTimeFulfillment(
        bytes32 requestId, 
        string memory fixtureID, 
        uint256 ko,
        uint256 warpTime
    ) 
    public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // This test case assumes block timestamp is 
        // less than kickoff time - BET_CUTOFF_TIME AND
        // AND greater than kickoff time - BET_ADVANCE_TIME
        warpTime = bound(warpTime, ko - sportsBetting.BET_ADVANCE_TIME(), ko - sportsBetting.BET_CUTOFF_TIME());
        
        sportsBetting.setRequestKickoffToFixtureCheat(requestId, fixtureID);

        // Set state to CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING);

        // Warp timestamp to within window for fixture to become OPEN
        vm.warp(warpTime);

        // Expect RequestFixtureKickoffFulfilled emit 
        vm.expectEmit(true, true, true, true, address(sportsBetting));
        // Emit the event we expect to see
        emit RequestFixtureKickoffFulfilled(requestId, fixtureID, ko);

        // Set expected state
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.OPEN;

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.fulfillFixtureKickoffTimeTest(requestId, ko);

        // Assert state is OPEN
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);

        // Assert fixtureToKickoffTime updated
        assertEq(sportsBetting.fixtureToKickoffTime(fixtureID), ko);
    }

    // testClosedFixtureShouldRemainClosedDespiteValidKickoffTimeFulfillment asserts that, when
    // fulfillFixtureKickoffTime is called with a valid fixtureID and kickoff time but is in CLOSED state, it
    // 1. Emits RequestFixtureKickoffFulfilled event
    // 2. Betting state remains CLOSED for fixture
    //
    // Context: Only a fixture in OPENING state can become OPEN
    function testClosedFixtureShouldRemainClosedDespiteValidKickoffTimeFulfillment(
        bytes32 requestId, 
        string memory fixtureID, 
        uint256 ko,
        uint256 warpTime
    ) 
    public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        
        sportsBetting.setRequestKickoffToFixtureCheat(requestId, fixtureID);

        // Set state to CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.CLOSED);

        // Regardless of block.timestamp relation to kickoff time, fixture state should remain CLOSED
        vm.warp(warpTime);

        // Expect RequestFixtureKickoffFulfilled emit 
        vm.expectEmit(true, true, true, true, address(sportsBetting));
        // Emit the event we expect to see
        emit RequestFixtureKickoffFulfilled(requestId, fixtureID, ko);

        // Set expected state
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Act
        sportsBetting.fulfillFixtureKickoffTimeTest(requestId, ko);

        // Assert state is OPEN
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);

        // Assert fixtureToKickoffTime updated
        assertEq(sportsBetting.fixtureToKickoffTime(fixtureID), ko);
    }

    // testOpeningFixtureShouldBecomeClosedOnInvalidKickoffTimeFulfillment asserts that, when
    // fulfillFixtureKickoffTime is called with a valid fixtureID in OPENING state and kickoff time ineligible for fixture
    // to be opened, it
    // 1. Emits RequestFixtureKickoffFulfilled event
    // 2. Betting state becomes CLOSED for fixture
    function testOpeningFixtureShouldBecomeClosedOnInvalidKickoffTimeFulfillment(
        bytes32 requestId, 
        string memory fixtureID,
        uint256 ko,
        uint256 warpTime
    ) 
    public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // This test case assumes block timestamp is less than to kickoff time - BET_ADVANCE_TIME
        vm.assume(warpTime < ko - sportsBetting.BET_ADVANCE_TIME());
        
        sportsBetting.setRequestKickoffToFixtureCheat(requestId, fixtureID);

        // Set state to OPENING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPENING);

        // Warp timestamp to outside of window for fixture to become OPEN
        vm.warp(warpTime);

        // Expect RequestFixtureKickoffFulfilled emit 
        vm.expectEmit(true, true, true, true, address(sportsBetting));
        // Emit the event we expect to see
        emit RequestFixtureKickoffFulfilled(requestId, fixtureID, ko);

        // Set expected state
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.CLOSED;

        // Act
        sportsBetting.fulfillFixtureKickoffTimeTest(requestId, ko);

        // Assert state is CLOSED
        uint8 actualState = uint8(sportsBetting.bettingState(fixtureID));
        assertEq(uint8(expectedState), actualState);

        // Assert fixtureToKickoffTime updated
        assertEq(sportsBetting.fixtureToKickoffTime(fixtureID), ko);
    }

    // function testNonClosedOrOpeningFixtureShouldNotChangeStateOnKickoffTimeFulfillment asserts that
    // if fixture is not CLOSED or OPENING (i.e. if it is AWAITING, PAYABLE, OR CANCELLED) and it is
    // called with any kickoff time
    // 1. RequestFixtureKickoffFulfilled emitted
    // 2. Betting state does not change
    function testNonClosedOrOpeningFixtureShouldNotChangeStateOnKickoffTimeFulfillment(
        bytes32 requestId, 
        string memory fixtureID,
        uint256 ko,
        uint256 warpTime,
        uint256 state
    ) 
    public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // Assume state is either AWAITING, PAYABLE, or CANCELLED
        state = bound(state, uint256(SportsBetting.BettingState.AWAITING), uint256(SportsBetting.BettingState.CANCELLED));
        
        // Infer state
        SportsBetting.BettingState inferredState = SportsBetting.BettingState(state);

        sportsBetting.setRequestKickoffToFixtureCheat(requestId, fixtureID);

        // Set state to AWAITING
        sportsBetting.setFixtureBettingStateCheat(fixtureID, inferredState);

        // Regardless of block.timestamp relation to kickoff time, fixture state should remain AWAITING
        vm.warp(warpTime);

        // Expect RequestFixtureKickoffFulfilled emit 
        vm.expectEmit(true, true, true, true, address(sportsBetting));
        // Emit the event we expect to see
        emit RequestFixtureKickoffFulfilled(requestId, fixtureID, ko);

        // Act
        sportsBetting.fulfillFixtureKickoffTimeTest(requestId, ko);

        // Assert state is AWAITING
        uint256 actualState = uint256(sportsBetting.bettingState(fixtureID));
        assertEq(uint256(inferredState), actualState);

        // Assert fixtureToKickoffTime updated
        assertEq(sportsBetting.fixtureToKickoffTime(fixtureID), ko);
    }

    // testShouldSetAwaitingOnStake
    function testShouldSetAwaitingOnStake(
        string memory fixtureID, 
        uint256 ko, 
        uint256 warpTime, 
        uint256 amount,
        uint256 betTypeInt
    ) public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // block.timestamp should be greater than kickoff time - BET_CUTOFF_TIME
        vm.assume(warpTime > ko - sportsBetting.BET_CUTOFF_TIME());
        // Bound Bet Type to valid enum value
        betTypeInt = bound(betTypeInt, uint256(SportsBettingLib.FixtureResult.DEFAULT), uint256(SportsBettingLib.FixtureResult.CANCELLED));

        // Infer bet type from input
        SportsBettingLib.FixtureResult betType = SportsBettingLib.FixtureResult(betTypeInt);

        // Set state to OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN);

        // Set expected state AWAITING
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.AWAITING;

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp block.timestamp
        vm.warp(warpTime);

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.stake(fixtureID, betType, amount);

        // Assert bet state becomes awaiting
        uint256 actualState = uint256(sportsBetting.bettingState(fixtureID));
        assertEq(uint256(expectedState), actualState);
    }

    // testShouldRequireCorrectBetTypeOnStake
    function testShouldRequireCorrectBetTypeOnStake(
        string memory fixtureID, 
        uint256 ko, 
        uint256 warpTime, 
        uint256 amount,
        uint256 betTypeInt
    ) public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // Bound warpTime to within valid range
        warpTime = bound(warpTime, ko - sportsBetting.BET_ADVANCE_TIME(), ko - sportsBetting.BET_CUTOFF_TIME());

        // REVERT CONDITION
        // Assume Bet Type is invalid enum value
        vm.assume(betTypeInt == uint256(SportsBettingLib.FixtureResult.DEFAULT) || betTypeInt == uint256(SportsBettingLib.FixtureResult.CANCELLED));
        
        // Infer bet type from input
        SportsBettingLib.FixtureResult betType = SportsBettingLib.FixtureResult(betTypeInt);

        // Set state to OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN);

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp block.timestamp
        vm.warp(warpTime);

        // Expect revert for invalid bet type
        vm.expectRevert("This BetType is not permitted.");

        // Act
        sportsBetting.stake(fixtureID, betType, amount);
    }

    // testShouldRequireOpenStateOnStake
    function testShouldRequireOpenStateOnStake(
        string memory fixtureID, 
        uint256 ko, 
        uint256 warpTime, 
        uint256 amount,
        uint256 betTypeInt
    ) public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // Bound warpTime to within valid range
        warpTime = bound(warpTime, ko - sportsBetting.BET_ADVANCE_TIME(), ko - sportsBetting.BET_CUTOFF_TIME());
        // Bound Bet Type to valid enum value
        betTypeInt = bound(betTypeInt, uint256(SportsBettingLib.FixtureResult.HOME), uint256(SportsBettingLib.FixtureResult.AWAY));
        
        // Infer bet type from input
        SportsBettingLib.FixtureResult betType = SportsBettingLib.FixtureResult(betTypeInt);

        // REVERT CONDITION
        // Set state to CLOSED
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.CLOSED);

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp block.timestamp
        vm.warp(warpTime);

        // Expect revert for invalid bet type
        vm.expectRevert("Bet activity is not open.");

        // Act
        sportsBetting.stake(fixtureID, betType, amount);
    }

    // testShouldRequireEntranceFeeStake
    function testShouldRequireEntranceFeeStake(
        string memory fixtureID, 
        uint256 ko, 
        uint256 warpTime, 
        uint256 amount,
        uint256 betTypeInt
    ) public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // Bound warpTime to within valid range
        warpTime = bound(warpTime, ko - sportsBetting.BET_ADVANCE_TIME(), ko - sportsBetting.BET_CUTOFF_TIME());
        // Bound Bet Type to valid enum value
        betTypeInt = bound(betTypeInt, uint256(SportsBettingLib.FixtureResult.HOME), uint256(SportsBettingLib.FixtureResult.AWAY));
        
        // Infer bet type from input
        SportsBettingLib.FixtureResult betType = SportsBettingLib.FixtureResult(betTypeInt);

        // Set state to OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN);

        // REVERT CONDITION
        // Bound amount to between zero and entrance fee
        vm.assume(amount < sportsBetting.ENTRANCE_FEE());

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp block.timestamp
        vm.warp(warpTime);

        // Expect revert for invalid bet type
        vm.expectRevert("Amount is below entrance fee.");

        // Act
        sportsBetting.stake(fixtureID, betType, amount);
    }

    // Test staking workflow
    // testShouldRequireEntranceFeeStake

    // testShouldCorrectlyUpdateContractStateOnStake

    // testShouldRevertIfTransferFailsOnStake
    
    // Test unstaking workflow
    // testShouldSetAwaitingOnUnstake
    // testShouldRequireOpenStateOnUnstake
    // testShouldRequireNonZeroAmountOnStake
    // testShouldRequireExistingStakeOnUnstake
    // testShouldRevertOnUnstakeTooLow
    // testShouldRevertOnStakeBelowEntranceFeeOnStake
    // testShouldCorrectlyUpdateContractStateOnUnstake
    // testShouldRevertIfTransferFailsOnUnstake

    // testShouldSetAwaitingOnUnstake
    function testShouldSetAwaitingOnUnstake(
        string memory fixtureID, 
        uint256 ko, 
        uint256 warpTime, 
        uint256 amount,
        uint256 betTypeInt
    ) public {
        // For this test case, assume a valid fixtureID
        vm.assume(bytes(fixtureID).length > 0);
        // Assume reasonable fixture KO time
        vm.assume(ko > 10e9);
        // block.timestamp should be greater than kickoff time - BET_CUTOFF_TIME
        vm.assume(warpTime > ko - sportsBetting.BET_CUTOFF_TIME());
        // Bound Bet Type to valid enum value
        betTypeInt = bound(betTypeInt, uint256(SportsBettingLib.FixtureResult.DEFAULT), uint256(SportsBettingLib.FixtureResult.CANCELLED));

        // Infer bet type from input
        SportsBettingLib.FixtureResult betType = SportsBettingLib.FixtureResult(betTypeInt);

        // Set state to OPEN
        sportsBetting.setFixtureBettingStateCheat(fixtureID, SportsBetting.BettingState.OPEN);

        // Set expected state AWAITING
        SportsBetting.BettingState expectedState = SportsBetting.BettingState.AWAITING;

        // Set kickoff time
        sportsBetting.setFixtureKickoffTimeCheat(fixtureID, ko);

        // Warp block.timestamp
        vm.warp(warpTime);

        // Expect BettingStateChanged emit
        vm.expectEmit(true, true, false, true, address(sportsBetting));
        // Emit the event we expect to see
        emit BettingStateChanged(fixtureID, expectedState);

        // Act
        sportsBetting.unstake(fixtureID, betType, amount);

        // Assert bet state becomes awaiting
        uint256 actualState = uint256(sportsBetting.bettingState(fixtureID));
        assertEq(uint256(expectedState), actualState);
    }
}