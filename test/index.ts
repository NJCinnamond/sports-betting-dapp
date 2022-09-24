import { expect } from "chai";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers, network, waffle } from "hardhat";
const { deployMockContract, provider } = waffle;

const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// Contract enums
const bettingStateClosed = 0;
const bettingStateOpen = 1;
const bettingStateAwaiting = 2;
const bettingStateFulfilling = 3;

const betTypeHome = 0;
const betTypeDraw = 1;
const betTypeAway = 2;

describe("Sports Betting contract", function () {
  async function deploySportsBettingFixture() {
    // TODO: Mock SportsOracleConsumer ctx
    const [deployerOfContract] = provider.getWallets();

    const LinkToken = require('../artifacts/contracts/mock/LinkToken.sol/LinkToken.json');
    const mockLinkToken = await deployMockContract(deployerOfContract, LinkToken.abi);

    // Get the SportsBetting contract and Signers
    const SportsBettingFactory = await ethers.getContractFactory("SportsBettingTest");
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();

    const linkFee = 1000;

    const SportsBetting = await SportsBettingFactory.deploy(
      'mock_uri',
      '0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656', // Chainlink DevRel
      mockLinkToken.address,
      formatBytes32String('example'),
      linkFee
    );
    await SportsBetting.deployed();

    return { SportsBettingFactory, SportsBetting, owner, addr1, addr2, addr3, addr4 }
  }

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);
      expect(await SportsBetting.owner()).to.equal(owner.address);
    });
  });

  describe("setFixtureBettingState", function () {
    it("Should set correct betting state and emit event", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ACT & ASSERT
      const dummyFixtureID = '1234';
      await expect(SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen))
        .to.emit(SportsBetting, "BettingStateChanged")
        .withArgs(dummyFixtureID, bettingStateOpen);

      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateOpen);
    });
  })

  describe("shouldHaveCorrectBettingState", function () {
    it("Should not OPEN if bet is not CLOSED", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should not OPEN if bet has no kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      const currentTimestamp = 2000002000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should not OPEN if current block timestamp is too close to kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is less than 60 mins (betCutOffTime) to left of the kickoffTime, 
      // it is invalid
      const currentTimestamp = 2000006000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // Set Fixture kickoffTime
      await SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should not OPEN if current block timestamp is too far from kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is more than 60 mins (betCutOffTime) to left of the kickoffTime, and within
      // 1 week (betAdvanceTime) of the kickoffTime, it is valid
      const currentTimestamp = 1900002000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // Set Fixture kickoffTime
      await SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should OPEN if bet is CLOSED, kickoff time is present and valid timestamp", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is more than 60 mins (betCutOffTime) to left of the kickoffTime, and within
      // 1 week (betAdvanceTime) of the kickoffTime, it is valid
      const currentTimestamp = 2000002000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // Set Fixture kickoffTime
      await SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateOpen);
    });

    it("Should set AWAITING if bet is OPEN and current timestamp is valid", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is within 60 mins (betCutOffTime) of the kickoffTime, it is valid
      const currentTimestamp = 2000006000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Set Fixture kickoffTime
      await SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateAwaiting);
    });

    it("Should not set AWAITING if kickoff time is not present", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      const currentTimestamp = 2000006000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateOpen);
    });

    it("Should not set AWAITING if current timestamp is too far from kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Kickoff time is further than 60 mins (betCutOffTime) from kickoff time so it
      // will not be moved to AWAITING
      const currentTimestamp = 2000002000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Set Fixture kickoffTime
      await SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateOpen);
    });
  });

  describe("stake", function () {
    it("Should not allow stake if bet is not OPEN", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT & ASSERT
      await expect(SportsBetting.stake(dummyFixtureID, betTypeHome))
        .to.be.revertedWith("Bet activity is not open for this fixture.");
    });

    it("Should not allow stake if amount is below entrance fee", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      const amountBelowEntranceFee = 1;

      // ACT & ASSERT
      await expect(SportsBetting.stake(dummyFixtureID, betTypeHome, { value: amountBelowEntranceFee }))
        .to.be.revertedWith("Amount is below entrance fee.");
    });

    it("Should update contract state variables correctly with valid stake", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Stake 1 ETH
      const stakeAmount = ethers.utils.parseUnits("5", 18);

      // ACT & ASSERT
      await expect(SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: stakeAmount }))
        .to.emit(SportsBetting, "BetStaked")
        .withArgs(addr1.address, dummyFixtureID, stakeAmount, betTypeHome);

      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(stakeAmount);

      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeHome, 0))
        .to.equal(addr1.address);

      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(true);
    });
  });

  describe("unstake", function () {
    it("Should not allow unstake if amount is zero", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT & ASSERT
      await expect(SportsBetting.unstake(dummyFixtureID, betTypeHome, 0))
        .to.be.revertedWith("Amount should exceed zero.");
    });

    it("Should not allow unstake if bet is not OPEN", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);
      // Dummy unstake amount
      const unstakeAmount = ethers.utils.parseUnits("5", 16);

      // ACT & ASSERT
      await expect(SportsBetting.unstake(dummyFixtureID, betTypeHome, unstakeAmount))
        .to.be.revertedWith("Fixture is not in Open state.");
    });

    it("Should not allow unstake if caller has no stake on fixture-result", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      // Dummy unstake amount
      const unstakeAmount = ethers.utils.parseUnits("5", 16);

      // ACT & ASSERT
      await expect(SportsBetting.connect(addr1).unstake(dummyFixtureID, betTypeHome, unstakeAmount))
        .to.be.revertedWith("No stake on this address-result.");
    });

    it("Should update contract state variables correctly with valid partial unstake", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // ACT
      // Stake 1 ETH
      const stakeAmount = ethers.utils.parseUnits("5", 16);
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: stakeAmount });

      // Unstake 0.2 ETH
      const unstakeAmount = ethers.utils.parseUnits("2", 16);
      const expectedFinalStakeAmount = ethers.utils.parseUnits("3", 16);

      // ASSERT
      await expect(SportsBetting.connect(addr1).unstake(dummyFixtureID, betTypeHome, unstakeAmount))
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr1.address, dummyFixtureID, unstakeAmount, betTypeHome);

      // Expect the new stake amount to equal difference between starting stake amount and unstake amount
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(expectedFinalStakeAmount);

      // Expect addr1 to remain an active staker
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(true);
    });

    it("Should update contract state variables correctly with valid full unstake", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // ACT
      // Stake 1 ETH
      const stakeAmount = ethers.utils.parseUnits("5", 16);
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: stakeAmount });

      // ASSERT
      // Call unstake with unstakeAmount == stakeAmount for full unstake
      await expect(SportsBetting.connect(addr1).unstake(dummyFixtureID, betTypeHome, stakeAmount))
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr1.address, dummyFixtureID, stakeAmount, betTypeHome);

      // Expect new stake amount to be zero as this was a full unstake
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(0);

      // Expect addr1 to not remain an active staker
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(false);
    });
  });

  describe("fulfillKickoffTime", function () {
    it("Should correctly set kickoff time", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      const kickoffTime = 2000007000;

      // ACT & ASSERT
      await expect(SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime))
        .to.emit(SportsBetting, "KickoffTimeUpdated")
        .withArgs(dummyFixtureID, kickoffTime);
    });
  });

  describe("getLosingFixtureOutcomes", function () {
    it("Should correctly get losing fixture outcomes on HOME", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      const outcome = betTypeHome;
      const expected = [betTypeDraw, betTypeAway];

      // ACT & ASSERT
      expect(await SportsBetting.callStatic.getLosingFixtureOutcomesTest(outcome))
        .to.deep.equal(expected);
    });

    it("Should correctly get losing fixture outcomes on DRAW", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      const outcome = betTypeDraw;
      const expected = [betTypeHome, betTypeAway];

      // ACT & ASSERT
      expect(await SportsBetting.callStatic.getLosingFixtureOutcomesTest(outcome))
        .to.deep.equal(expected);
    });

    it("Should correctly get losing fixture outcomes on AWAY", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      const outcome = betTypeAway;
      const expected = [betTypeHome, betTypeDraw];

      // ACT & ASSERT
      expect(await SportsBetting.callStatic.getLosingFixtureOutcomesTest(outcome))
        .to.deep.equal(expected);
    });

    it("Should revert if invalid outcome", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      const outcome = 100; // Invalid enum

      // ACT & ASSERT
      await expect(SportsBetting.callStatic.getLosingFixtureOutcomesTest(outcome))
        .to.be.reverted;
    });
  });

  describe("fulfillFixturePayoutObligations", function () {
    it("Should revert if fixture bet state is not FULFILLING", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      const winningAmount = 0;
      const totalAmount = 0;

      // ACT & ASSERT
      await expect(SportsBetting.fulfillFixturePayoutObligationsTest(dummyFixtureID, betTypeHome, winningAmount, totalAmount))
        .to.be.revertedWith("Fixture bet state is not FULFILLING.");
    });

    it("Should update ctx variables and balances correctly", async function () {
      const { SportsBetting, addr1, addr2, addr3 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Addr1 bets on correct result (HOME) with 2 ETH
      const addr1BetAmount = ethers.utils.parseUnits("2", 18);
      // Addr2 also bets on correct result (HOME) with 1 ETH
      const addr2BetAmount = ethers.utils.parseUnits("1", 18);
      // Addr3 bets on a losing result (AWAY) with 6 ETH
      const addr3BetAmount = ethers.utils.parseUnits("6", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeHome, { value: addr2BetAmount });
      await SportsBetting.connect(addr3).stake(dummyFixtureID, betTypeAway, { value: addr3BetAmount });

      // Winning amount = 2 + 1 = 3 ETH
      // Total amount = 2 + 1 + 6 = 9 ETH
      const winningAmount = ethers.utils.parseUnits("3", 18);
      const totalAmount = ethers.utils.parseUnits("9", 18);

      // Expectations:
      // Addr1 paid out with (2/3) * 9 = 6 ETH
      // Addr2 paid out with (1/3) * 9 = 3 ETH
      const addr1ExpectedPayout = ethers.utils.parseUnits("6", 18);
      const addr2ExpectedPayout = ethers.utils.parseUnits("3", 18);

      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateFulfilling);

      // ACT & ASSERT
      await expect(SportsBetting.fulfillFixturePayoutObligationsTest(dummyFixtureID, betTypeHome, winningAmount, totalAmount))
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(addr1.address, dummyFixtureID, addr1ExpectedPayout)
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(addr2.address, dummyFixtureID, addr2ExpectedPayout);
    });

    it("Should update ctx variables and balances correctly with unstake", async function () {
      const { SportsBetting, addr1, addr2, addr3 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Addr1 bets on correct result (HOME) with 2 ETH
      const addr1BetAmount = ethers.utils.parseUnits("2", 18);
      // Addr2 also bets on correct result (HOME) with 1 ETH
      const addr2BetAmount = ethers.utils.parseUnits("1", 18);
      // Addr3 bets on a losing result (AWAY) with 6 ETH
      const addr3BetAmount = ethers.utils.parseUnits("6", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeHome, { value: addr2BetAmount });
      await SportsBetting.connect(addr3).stake(dummyFixtureID, betTypeAway, { value: addr3BetAmount });

      // Now addr2 unstakes entire stake
      await SportsBetting.connect(addr2).unstake(dummyFixtureID, betTypeHome, addr2BetAmount);

      // Winning amount = 2 ETH
      // Total amount = 8 ETH
      const winningAmount = ethers.utils.parseUnits("2", 18);
      const totalAmount = ethers.utils.parseUnits("8", 18);

      // Expectations:
      // Addr1 paid out with 8 ETH
      const addr1ExpectedPayout = ethers.utils.parseUnits("8", 18);

      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateFulfilling);

      // ACT & ASSERT
      await expect(SportsBetting.fulfillFixturePayoutObligationsTest(dummyFixtureID, betTypeHome, winningAmount, totalAmount))
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(addr1.address, dummyFixtureID, addr1ExpectedPayout);
    });
  });

  describe("getTotalAmountBetOnFixtureOutcome", function () {
    it("Should return zero when no bets placed", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // HOME win
      const outcomes = [betTypeHome];

      expect(await SportsBetting.callStatic.getTotalAmountBetOnFixtureOutcomesTest(dummyFixtureID, outcomes))
        .to.equal(0);
    });

    it("Should return correct bet amounts for one outcome", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetAmount = ethers.utils.parseUnits("2", 18);
      // Addr2 also bets on AWAY with 1 ETH
      const addr2BetAmount = ethers.utils.parseUnits("1", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeAway, { value: addr2BetAmount });

      // HOME win
      const outcomes = [betTypeHome];

      expect(await SportsBetting.callStatic.getTotalAmountBetOnFixtureOutcomesTest(dummyFixtureID, outcomes))
        .to.equal(addr1BetAmount);
    });

    it("Should return correct bet amounts for multiple outcome", async function () {
      const { SportsBetting, addr1, addr2, addr3, addr4 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetAmount = ethers.utils.parseUnits("2", 18);
      // Addr2 bets on AWAY with 1 ETH
      const addr2BetAmount = ethers.utils.parseUnits("1", 18);
      // Addr3 bets on DRAW with 3 ETH
      const addr3BetAmount = ethers.utils.parseUnits("3", 18);
      // Addr4 bets on HOME with 8 ETH
      const addr4BetAmount = ethers.utils.parseUnits("4", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeAway, { value: addr2BetAmount });
      await SportsBetting.connect(addr3).stake(dummyFixtureID, betTypeDraw, { value: addr3BetAmount });
      await SportsBetting.connect(addr4).stake(dummyFixtureID, betTypeHome, { value: addr4BetAmount });

      // HOME win and DRAW
      const outcomes = [betTypeHome, betTypeDraw];
      // Expected = 2 + 3 + 4 = 9 ETH
      const expected = ethers.utils.parseUnits("9", 18);

      expect(await SportsBetting.callStatic.getTotalAmountBetOnFixtureOutcomesTest(dummyFixtureID, outcomes))
        .to.equal(expected);
    });
  });

  describe("getFixtureResultFromAPIResponse", function () {
    it("Should revert if result response is unexpected string", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      const unexpectedResultResponse = 'OH NO!';

      // Revert string
      const expectedReversionString = `Error on fixture ${dummyFixtureID}: Unknown result from API: ${unexpectedResultResponse}`;

      await expect(SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, unexpectedResultResponse))
        .to.emit(SportsBetting, "BetPayoutFulfillmentError")
        .withArgs(dummyFixtureID, expectedReversionString)
        .to.be.revertedWith(expectedReversionString);
    });

    it("Should return correct BetTypes", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';

      // Inputs
      const homeResultResponse = 'HOME';
      const drawResultResponse = 'DRAW';
      const awayResultResponse = 'AWAY';

      // HOME
      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, homeResultResponse))
        .to.equal(betTypeHome);

      // DRAW
      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, drawResultResponse))
        .to.equal(betTypeDraw);

      // AWAY
      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, awayResultResponse))
        .to.equal(betTypeAway);
    });
  });
});