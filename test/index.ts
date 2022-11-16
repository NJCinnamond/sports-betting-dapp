import { expect } from "chai";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers, network, waffle } from "hardhat";
const { deployMockContract, provider } = waffle;

const chai = require('chai')
const sinon = require('sinon')
const sinonChai = require('sinon-chai')
const { smock } = require('@defi-wonderland/smock')
const expect = chai.expect
chai.use(smock.matchers)

const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// Contract enums
const bettingStateClosed = 0;
const bettingStateOpening = 1;
const bettingStateOpen = 2;
const bettingStateAwaiting = 3;
const bettingStateFulfilling = 4;

const betTypeHome = 1;
const betTypeDraw = 2;
const betTypeAway = 3;

const commissionRate = 1;

// Unix timestamp 1 day from now
const unixTomorrow = Math.round((new Date(Date.now() + 24 * 60 * 60 * 1000)).getTime() / 1000);

describe("Sports Betting contract", function () {
  async function deploySportsBettingFixture() {
    const [deployerOfContract] = provider.getWallets();

    const LinkToken = require('../artifacts/contracts/mock/LinkTokenInterface.sol/LinkTokenInterface.json');
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
      linkFee,
      commissionRate
    );
    await SportsBetting.deployed();

    return { SportsBettingFactory, SportsBetting, mockLinkToken, owner, addr1, addr2, addr3, addr4 }
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

  describe("initializeHistoricalBetters", function () {
    it("Should correctly initialize historicalBetters for each bet type", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ACT & ASSERT
      const dummyFixtureID = '1234';
      await SportsBetting.initializeHistoricalBettersTest(dummyFixtureID);

      const zeroAddress = '0x0000000000000000000000000000000000000000';

      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeHome, 0)).to.equal(zeroAddress);
      expect(await SportsBetting.getHistoricalBettersLength(dummyFixtureID, betTypeHome)).to.equal(1);

      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeAway, 0)).to.equal(zeroAddress);
      expect(await SportsBetting.getHistoricalBettersLength(dummyFixtureID, betTypeAway)).to.equal(1);

      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeDraw, 0)).to.equal(zeroAddress);
      expect(await SportsBetting.getHistoricalBettersLength(dummyFixtureID, betTypeDraw)).to.equal(1);
    });

    it("Should correctly initialize historicalBetters for each bet type after CLOSE from OPEN with stakes", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      const zeroAddress = '0x0000000000000000000000000000000000000000';

      // Dummy addresses
      const dummyAddr1 = '0x000000000000000000000000000000000000000a';
      const dummyAddr2 = '0x000000000000000000000000000000000000000b';
      const dummyAddr3 = '0x000000000000000000000000000000000000000c';

      // Dummy historical betters arrays
      const homeHistoricalBetters = [zeroAddress, dummyAddr1, dummyAddr2];
      const awayHistoricalBetters = [zeroAddress, dummyAddr3];
      const drawHistoricalBetters = [zeroAddress];

      // Set dummy historical betters arrays
      await SportsBetting.setHistoricalBetters(dummyFixtureID, betTypeHome, homeHistoricalBetters);
      await SportsBetting.setHistoricalBetters(dummyFixtureID, betTypeAway, awayHistoricalBetters);
      await SportsBetting.setHistoricalBetters(dummyFixtureID, betTypeDraw, drawHistoricalBetters);

      // ACT
      // Reinitialize historical betters
      await SportsBetting.initializeHistoricalBettersTest(dummyFixtureID);

      // ASSERT
      // Expect historical betters for all 3 bet types to equal array with zero address as single item
      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeHome, 0)).to.equal(zeroAddress);
      expect(await SportsBetting.getHistoricalBettersLength(dummyFixtureID, betTypeHome)).to.equal(1);

      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeAway, 0)).to.equal(zeroAddress);
      expect(await SportsBetting.getHistoricalBettersLength(dummyFixtureID, betTypeAway)).to.equal(1);

      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeDraw, 0)).to.equal(zeroAddress);
      expect(await SportsBetting.getHistoricalBettersLength(dummyFixtureID, betTypeDraw)).to.equal(1);
    });
  })

  describe("shouldHaveCorrectBettingState", function () {
    it("Should CLOSE if bet is not OPENING", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should CLOSE if bet has no kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      const currentTimestamp = 2000002000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpening);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should CLOSE if bet is OPENING but block timestamp is too close to kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is less than 90 mins (betCutOffTime) to left of the kickoffTime, 
      // it is invalid
      const currentTimestamp = 2000006000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpening);

      // Set Fixture kickoffTime
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should CLOSE if bet is OPENING but block timestamp is too far from kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is more than 1 week (betAdvanceTime) to left of the kickoffTime, it is invalid
      const currentTimestamp = 1900002000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpening);

      // Set Fixture kickoffTime
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
    });

    it("Should OPEN if bet is OPENING, kickoff time is present and valid timestamp", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is more than 90 mins (betCutOffTime) to left of the kickoffTime, and within
      // 1 week (betAdvanceTime) of the kickoffTime, it is valid
      const currentTimestamp = 2000000000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp]);
      await network.provider.send("evm_mine");

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpening);

      // Set Fixture kickoffTime
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateOpen);
    });

    it("Should set AWAITING if bet is OPEN and current timestamp is within betCutoffTime of kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Because the block ts is within 90 mins (betCutOffTime) of the kickoffTime, it is valid
      const currentTimestamp = 2000006000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Set Fixture kickoffTime
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateAwaiting);
    });

    it("Should not set AWAITING if current timestamp is too far from kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN

      // Set time-dependent vars
      // Kickoff time is further than 90 mins (betCutOffTime) from kickoff time so it
      // will not be moved to AWAITING
      const currentTimestamp = 2000001000;
      const kickoffTime = 2000007000;

      // Manipulate block timestamp
      await network.provider.send("evm_setNextBlockTimestamp", [currentTimestamp])
      await network.provider.send("evm_mine")

      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // Set Fixture kickoffTime
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, kickoffTime);

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateOpen);
    });

    it("Should not set AWAITING if bet is not OPEN", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';

      // ACT
      await SportsBetting.shouldHaveCorrectBettingStateTest(dummyFixtureID);

      // ASSERT
      expect(await SportsBetting.bettingState(dummyFixtureID)).to.equal(bettingStateClosed);
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
        .to.be.revertedWith("Bet activity is not open.");
    });

    it("Should not allow stake if amount is below entrance fee", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Stake 1 ETH
      const stakeAmount = ethers.utils.parseUnits("5", 18);

      // ACT & ASSERT
      await expect(SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: stakeAmount }))
        .to.emit(SportsBetting, "BetStaked")
        .withArgs(addr1.address, dummyFixtureID, stakeAmount, betTypeHome);

      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(stakeAmount);

      // 0 because first index is reserved for null address
      expect(await SportsBetting.historicalBetters(dummyFixtureID, betTypeHome, 1))
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
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      await expect(SportsBetting.updateKickoffTimeTest(dummyFixtureID, kickoffTime))
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
        .to.be.revertedWith("Bet state not FULFILLING.");
    });

    it("Should update ctx variables and balances correctly", async function () {
      const { SportsBetting, owner, addr1, addr2, addr3 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      // Addr1 obligation is (2/3) * 9 = 6 ETH
      // COMMISSION: Owner keeps 1% = 0.06 ETH. => Addr payout is 5.94 ETH
      const addr1ExpectedPayout = ethers.utils.parseUnits("5.94", 18);
      // Addr2 paid out with (1/3) * 9 = 3 ETH
      // COMMISSION: Owner keeps 1% = 0.03 ETH. => Addr payout is 2.97 ETH
      const addr2ExpectedPayout = ethers.utils.parseUnits("2.97", 18);
      // => total commission is 0.09 ETH
      const ownerExpectedPayout = ethers.utils.parseUnits("0.09", 18);

      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateFulfilling);

      // ACT & ASSERT
      await expect(SportsBetting.fulfillFixturePayoutObligationsTest(dummyFixtureID, betTypeHome, winningAmount, totalAmount))
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(addr1.address, dummyFixtureID, addr1ExpectedPayout)
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(addr2.address, dummyFixtureID, addr2ExpectedPayout)
        .to.emit(SportsBetting, "BetCommissionPayout")
        .withArgs(dummyFixtureID, ownerExpectedPayout);

      expect(await SportsBetting.callStatic.payouts(dummyFixtureID, addr1.address))
        .to.equal(addr1ExpectedPayout);
      expect(await SportsBetting.callStatic.payouts(dummyFixtureID, addr2.address))
        .to.equal(addr2ExpectedPayout);
      expect(await SportsBetting.callStatic.commissionMap(dummyFixtureID))
        .to.equal(ownerExpectedPayout);
    });

    it("Should update ctx variables and balances correctly with unstake", async function () {
      const { SportsBetting, owner, addr1, addr2, addr3 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      // Addr1 obligation is 8 ETH
      // COMMISSION: Owner keeps 1% = 0.08 ETH. => Addr payout is 7.92 ETH
      const addr1ExpectedPayout = ethers.utils.parseUnits("7.92", 18);
      // Owner obligation is 0.08 ETH
      const ownerExpectedPayout = ethers.utils.parseUnits("0.08", 18);

      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateFulfilling);

      // ACT & ASSERT
      await expect(SportsBetting.fulfillFixturePayoutObligationsTest(dummyFixtureID, betTypeHome, winningAmount, totalAmount))
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(addr1.address, dummyFixtureID, addr1ExpectedPayout)
        .to.emit(SportsBetting, "BetCommissionPayout")
        .withArgs(dummyFixtureID, ownerExpectedPayout);

      expect(await SportsBetting.callStatic.payouts(dummyFixtureID, addr1.address))
        .to.equal(addr1ExpectedPayout);
      expect(await SportsBetting.callStatic.payouts(dummyFixtureID, addr2.address))
        .to.equal(0);
      expect(await SportsBetting.callStatic.commissionMap(dummyFixtureID))
        .to.equal(ownerExpectedPayout);
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
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

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
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetAmount = ethers.utils.parseUnits("2", 18);
      // Addr2 bets on AWAY with 1 ETH
      const addr2BetAmount = ethers.utils.parseUnits("1", 18);
      // Addr3 bets on DRAW with 3 ETH
      const addr3BetAmount = ethers.utils.parseUnits("3", 18);
      // Addr4 bets on HOME with 8 ETH
      const addr4BetAmount = ethers.utils.parseUnits("4", 18);
      // Addr1 bets on HOME again with 3 ETH
      const addr1SecondBetAmount = ethers.utils.parseUnits("3", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeAway, { value: addr2BetAmount });
      await SportsBetting.connect(addr3).stake(dummyFixtureID, betTypeDraw, { value: addr3BetAmount });
      await SportsBetting.connect(addr4).stake(dummyFixtureID, betTypeHome, { value: addr4BetAmount });
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1SecondBetAmount });

      // HOME win and DRAW
      const outcomes = [betTypeHome, betTypeDraw];
      // Expected = 2 + 3 + 4 + 3 = 12 ETH
      const expected = ethers.utils.parseUnits("12", 18);

      expect(await SportsBetting.callStatic.getTotalAmountBetOnFixtureOutcomesTest(dummyFixtureID, outcomes))
        .to.equal(expected);
    });
  });

  describe("getFixtureResultFromAPIResponse", function () {
    it("Should revert if result response is unexpected uint256", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      const unexpectedResultResponse = 69; // No BetType enum value with 69 so this should fail

      // Revert string
      const expectedReversionString = `Error on fixture ${dummyFixtureID}: Unknown fixture result from API`;

      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, unexpectedResultResponse))
        .to.emit(SportsBetting, "BetPayoutFulfillmentError")
        .withArgs(dummyFixtureID, expectedReversionString);
    });

    it("Should revert if result response is BetType Default", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      const unexpectedResultResponse = 0; // BetType.DEFAULT

      // Revert string
      const expectedReversionString = `Error on fixture ${dummyFixtureID}: Unknown fixture result from API`;

      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, unexpectedResultResponse))
        .to.emit(SportsBetting, "BetPayoutFulfillmentError")
        .withArgs(dummyFixtureID, expectedReversionString);
    });

    it("Should return correct BetTypes", async function () {
      const { SportsBetting } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';

      // HOME
      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, betTypeHome))
        .to.equal(betTypeHome);

      // DRAW
      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, betTypeDraw))
        .to.equal(betTypeDraw);

      // AWAY
      expect(await SportsBetting.callStatic.getFixtureResultFromAPIResponseTest(dummyFixtureID, betTypeAway))
        .to.equal(betTypeAway);
    });
  });

  describe("getStakeSummaryForUser", function () {
    it("Should return zeros if no user stake", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT & ASSERT
      const result = await SportsBetting.callStatic.getStakeSummaryForUserTest(dummyFixtureID, addr1.address);

      // All bet types should be zero
      expect(result[0].toNumber()).to.equal(0);
      expect(result[1].toNumber()).to.equal(0);
      expect(result[2].toNumber()).to.equal(0);
    });

    it("Should return correct user stake with single staker", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);
      // Addr1 bets on AWAY with 1 ETH
      const addr1BetAwayAmount = ethers.utils.parseUnits("1", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeAway, { value: addr1BetAwayAmount });

      // ACT & ASSERT
      const result = await SportsBetting.callStatic.getStakeSummaryForUserTest(dummyFixtureID, addr1.address);

      // Should match addr1 stakes only
      expect(result[0].toString()).to.equal(addr1BetHomeAmount);
      expect(result[1].toString()).to.equal('0');
      expect(result[2].toString()).to.equal(addr1BetAwayAmount);
    });

    it("Should return correct user stake with multiple stakers", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);
      // Addr1 bets on AWAY with 1 ETH
      const addr1BetAwayAmount = ethers.utils.parseUnits("1", 18);

      // Addr2 bets on HOME with 4 ETH
      const addr2BetHomeAmount = ethers.utils.parseUnits("4", 18);
      // Addr2 bets on AWAY with 2 ETH
      const addr2BetAwayAmount = ethers.utils.parseUnits("2", 18);

      // Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeAway, { value: addr1BetAwayAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeHome, { value: addr2BetHomeAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeAway, { value: addr2BetAwayAmount });

      // ACT & ASSERT
      const result = await SportsBetting.callStatic.getStakeSummaryForUserTest(dummyFixtureID, addr1.address);

      // Should match addr1 stakes only
      expect(result[0].toString()).to.equal(addr1BetHomeAmount);
      expect(result[1].toString()).to.equal('0');
      expect(result[2].toString()).to.equal(addr1BetAwayAmount);
    });
  });

  describe("getEnrichedFixtureData", function () {
    it("Should return correct enrichment with multiple stakers", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);
      // Addr1 bets on AWAY with 1 ETH
      const addr1BetAwayAmount = ethers.utils.parseUnits("1", 18);

      // Addr2 bets on HOME with 4 ETH
      const addr2BetHomeAmount = ethers.utils.parseUnits("4", 18);
      // Addr2 bets on AWAY with 2 ETH
      const addr2BetAwayAmount = ethers.utils.parseUnits("2", 18);

      // Expected total stakes
      const expectedTotalHomeAmount = ethers.utils.parseUnits("6", 18);
      const expectedTotalAwayAmount = ethers.utils.parseUnits("3", 18);

      // ACT: Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeAway, { value: addr1BetAwayAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeHome, { value: addr2BetHomeAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeAway, { value: addr2BetAwayAmount });

      // ACT: Addr1 calls getEnrichedFixtureData
      const result = await SportsBetting.callStatic.getEnrichedFixtureData(dummyFixtureID, addr1.address);

      // ASSERT
      // Fixture state should be open
      expect(result["fixtureState"]).to.equal(bettingStateOpen);
      // User stakes should match addr1 stakes only
      expect(result["user"][0].toString()).to.equal(addr1BetHomeAmount);
      expect(result["user"][1].toString()).to.equal('0');
      expect(result["user"][2].toString()).to.equal(addr1BetAwayAmount);
      // Total stakes should be a summation of addr1 and addr2 stakes
      expect(result["total"][0].toString()).to.equal(expectedTotalHomeAmount);
      expect(result["total"][1].toString()).to.equal('0');
      expect(result["total"][2].toString()).to.equal(expectedTotalAwayAmount);
    });
  });

  describe("handleClosingBetsForFixture", function () {
    it("Should fully refund all stakers for all fixture amounts", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);
      // Addr1 bets on AWAY with 1 ETH
      const addr1BetAwayAmount = ethers.utils.parseUnits("1", 18);

      // Addr2 bets on HOME with 4 ETH
      const addr2BetHomeAmount = ethers.utils.parseUnits("4", 18);
      // Addr2 bets on DRAW with 2 ETH
      const addr2BetDrawAmount = ethers.utils.parseUnits("2", 18);

      // ACT: Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeAway, { value: addr1BetAwayAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeHome, { value: addr2BetHomeAmount });
      await SportsBetting.connect(addr2).stake(dummyFixtureID, betTypeDraw, { value: addr2BetDrawAmount });

      // ASSERT
      await expect(SportsBetting.handleClosingBetsForFixtureTest(dummyFixtureID))
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr1.address, dummyFixtureID, addr1BetHomeAmount, betTypeHome)
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr1.address, dummyFixtureID, addr1BetAwayAmount, betTypeAway)
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr2.address, dummyFixtureID, addr2BetHomeAmount, betTypeHome)
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr2.address, dummyFixtureID, addr2BetDrawAmount, betTypeDraw);

      // Expect the new stake amount to equal zero for both addresses
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(0);
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeAway, addr1.address))
        .to.equal(0);
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr2.address))
        .to.equal(0);
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeDraw, addr2.address))
        .to.equal(0);

      // Expect addr1 and addr2 to not be active betters
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(false);
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeAway, addr1.address))
        .to.equal(false);
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr2.address))
        .to.equal(false);
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeDraw, addr2.address))
        .to.equal(false);
    });
  });

  describe("removeStakeState", function () {
    it("Should correctly amend betting states for staker for partial unstake", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);
      // Wants to remove 1 ETH of stake
      const addr1UnstakeAmount = ethers.utils.parseUnits("1", 18);
      // Remaining bet should be 1 ETH
      const addr1FinalStakeAmount = ethers.utils.parseUnits("1", 18);

      // ACT: Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });

      // ASSERT
      await SportsBetting.removeStakeStateTest(dummyFixtureID, betTypeHome, addr1UnstakeAmount, addr1.address);

      // Expect the new stake amount to equal zero for both addresses
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(addr1FinalStakeAmount);

      // Expect addr1 and addr2 to not be active betters
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(true);
    });

    it("Should correctly amend betting states for staker for full unstake", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);

      // ACT: Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });

      // ASSERT
      // UNSTAKE FULL AMOUNT
      await SportsBetting.removeStakeStateTest(dummyFixtureID, betTypeHome, addr1BetHomeAmount, addr1.address);

      // Expect the new stake amount to equal zero for both addresses
      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(0);

      // Expect addr1 and addr2 to not be active betters
      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(false);
    });

    it("Should revert if no stake for staker on result", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 tries to unstake 2 ETH without an existing stake
      const addr1UnstakeAmount = ethers.utils.parseUnits("2", 18);

      // ASSERT
      await expect(SportsBetting.removeStakeStateTest(dummyFixtureID, betTypeHome, addr1UnstakeAmount, addr1.address))
        .to.be.revertedWith("No stake on this address-result.");
    });

    it("Should revert if unstake amount exceeds stake", async function () {
      const { SportsBetting, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 bets on HOME with 2 ETH
      const addr1BetHomeAmount = ethers.utils.parseUnits("2", 18);
      // Addr1 tries to unstake 3 ETH
      const addr1UnstakeAmount = ethers.utils.parseUnits("3", 18);

      // ACT: Place bets
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1BetHomeAmount });

      // ASSERT
      await expect(SportsBetting.removeStakeStateTest(dummyFixtureID, betTypeHome, addr1UnstakeAmount, addr1.address))
        .to.be.revertedWith("Current stake too low.");
    });
  });

  describe("transferLink", function () {
    it("Should update userToLink var", async function () {
      const { SportsBetting, addr1, addr2, mockLinkToken } = await loadFixture(deploySportsBettingFixture);

      // Addr1 transfers 1 LINK
      const addr1FirstTransferAmount = ethers.utils.parseUnits("1", 18);

      // Initialize mock
      await mockLinkToken.mock.transferFrom.returns(true);

      // Act
      await SportsBetting.connect(addr1).transferLink(addr1FirstTransferAmount);

      // Assert
      expect(await SportsBetting.userToLink(addr1.address))
        .to.equal(addr1FirstTransferAmount);

      // Addr1 transfers 2 more LINK. Addr2 transfers 4 LINK
      const addr1SecondTransferAmount = ethers.utils.parseUnits("2", 18);
      const addr1TotalTransferAmount = ethers.utils.parseUnits("3", 18);
      const addr2FirstTransferAmount = ethers.utils.parseUnits("4", 18);

      // Act
      await SportsBetting.connect(addr1).transferLink(addr1SecondTransferAmount);
      await SportsBetting.connect(addr2).transferLink(addr2FirstTransferAmount);

      // Assert
      expect(await SportsBetting.userToLink(addr1.address))
        .to.equal(addr1TotalTransferAmount);
      expect(await SportsBetting.userToLink(addr2.address))
        .to.equal(addr2FirstTransferAmount);
    });

    it("Should revert if transferFrom fails", async function () {
      const { SportsBetting, addr1, mockLinkToken } = await loadFixture(deploySportsBettingFixture);

      // Addr1 transfers 1 LINK
      const addr1FirstTransferAmount = ethers.utils.parseUnits("1", 18);

      // Initialize mock
      await mockLinkToken.mock.transferFrom.returns(false);

      // Act & Assert
      await expect(SportsBetting.connect(addr1).transferLink(addr1FirstTransferAmount))
        .to.be.revertedWith("Unable to transfer");
    });
  });

  describe("withdrawLink", function () {
    it("Should update userToLink var", async function () {
      const { SportsBetting, addr1, addr2, mockLinkToken } = await loadFixture(deploySportsBettingFixture);

      // Addr1 transfers 2 LINK
      const addr1TransferAmount = ethers.utils.parseUnits("2", 18);

      // Initialize mock and transfer
      await mockLinkToken.mock.transferFrom.returns(true);
      await SportsBetting.connect(addr1).transferLink(addr1TransferAmount);

      // Addr1 tries to withdraw 1 LINK 
      const addr1WithdrawalAmount = ethers.utils.parseUnits("1", 18);

      // Initialize mock
      await mockLinkToken.mock.transfer.returns(true);

      // Act
      await SportsBetting.connect(addr1).withdrawLink(addr1WithdrawalAmount);

      // Assert
      const expectedAddr1Link = ethers.utils.parseUnits("1", 18);
      expect(await SportsBetting.userToLink(addr1.address))
        .to.equal(expectedAddr1Link);
    });

    it("Should revert if user does not have enough LINK in ctx", async function () {
      const { SportsBetting, addr1, addr2, mockLinkToken } = await loadFixture(deploySportsBettingFixture);

      // Addr1 transfers 1 LINK
      const addr1TransferAmount = ethers.utils.parseUnits("1", 18);

      // Initialize mock and transfer link
      await mockLinkToken.mock.transferFrom.returns(true);
      await SportsBetting.connect(addr1).transferLink(addr1TransferAmount);

      // Addr1 tries to withdraw 2 LINK 
      const addr1WithdrawalAmount = ethers.utils.parseUnits("2", 18);

      // Assert
      await expect(SportsBetting.connect(addr1).withdrawLink(addr1WithdrawalAmount))
        .to.be.revertedWith("You don't have enough link");
    });

    it("Should revert if transfer fails", async function () {
      const { SportsBetting, addr1, mockLinkToken } = await loadFixture(deploySportsBettingFixture);

      // Addr1 transfers 1 LINK
      const addr1TransferAmount = ethers.utils.parseUnits("1", 18);

      // Initialize mock and transfer link
      await mockLinkToken.mock.transferFrom.returns(true);
      await SportsBetting.connect(addr1).transferLink(addr1TransferAmount);

      // Addr1 withdraws 1 LINK
      const addr1WithdrawalAmount = ethers.utils.parseUnits("1", 18);

      // Initialize mock
      await mockLinkToken.mock.transfer.returns(false);

      // Act & Assert
      await expect(SportsBetting.connect(addr1).withdrawLink(addr1WithdrawalAmount))
        .to.be.revertedWith("Unable to transfer");
    });
  });

  describe("updateFixtureResult", function () {
    it("Should send total amount to owner if no bets placed on winning result", async function () {
      const { SportsBetting, owner, addr1, addr2 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);
      await SportsBetting.updateKickoffTimeTest(dummyFixtureID, unixTomorrow);

      // Addr1 stakes 5 ETH ON HOME
      const addr1StakeAmount = ethers.utils.parseUnits("5", 18);
      SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: addr1StakeAmount });

      // Addr2 stakes 3 ETH ON DRAW
      const addr2StakeAmount = ethers.utils.parseUnits("3", 18);
      SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeDraw, { value: addr2StakeAmount });

      const totalStakeAmount = ethers.utils.parseUnits("8", 18);

      // ACT & ASSERT
      // AWAY wins so we expect owner to be paid out with full stake amount
      await expect(SportsBetting.connect(addr1).updateFixtureResultTest(dummyFixtureID, betTypeAway))
        .to.emit(SportsBetting, "BetPayout")
        .withArgs(owner.address, dummyFixtureID, totalStakeAmount);
    });
  });
});