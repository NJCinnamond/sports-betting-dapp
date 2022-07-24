import { expect } from "chai";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers, network, waffle } from "hardhat";
const { deployMockContract, provider } = waffle;

const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// Contract enums
const bettingStateClosed = 0;
const bettingStateOpen = 1;
const bettingStateAwaiting = 2;

const betTypeHome = 0;

describe("Sports Betting contract", function () {
  async function deploySportsBettingFixture() {
    // TODO: Mock SportsOracleConsumer ctx
    const [deployerOfContract] = provider.getWallets();

    const LinkToken = require('../artifacts/contracts/mock/LinkToken.sol/LinkToken.json');
    const mockLinkToken = await deployMockContract(deployerOfContract, LinkToken.abi);

    // Get the SportsBetting contract and Signers
    const SportsBettingFactory = await ethers.getContractFactory("SportsBettingTest");
    const [owner, addr1, addr2] = await ethers.getSigners();

    const linkFee = 1000;

    const SportsBetting = await SportsBettingFactory.deploy(
      'mock_uri',
      '0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656', // Chainlink DevRel
      mockLinkToken.address,
      formatBytes32String('example'),
      linkFee
    );
    await SportsBetting.deployed();

    return { SportsBettingFactory, SportsBetting, owner, addr1, addr2 }
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
      const stakeAmount = ethers.utils.parseUnits("5", 16);

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
    it("Should not allow unstake if bet is not OPEN", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateClosed);

      // ACT & ASSERT
      await expect(SportsBetting.unstake(dummyFixtureID, betTypeHome))
        .to.be.revertedWith("Bet activity is not open for this fixture.");
    });

    it("Should not allow unstake if caller has no stake on fixture-result", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // ACT & ASSERT
      await expect(SportsBetting.connect(addr1).unstake(dummyFixtureID, betTypeHome))
        .to.be.revertedWith("No stake on this address-result.");
    });

    it("Should update contract state variables correctly with valid unstake", async function () {
      const { SportsBetting, addr1 } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      await SportsBetting.setFixtureBettingStateTest(dummyFixtureID, bettingStateOpen);

      // ACT
      // Stake 1 ETH
      const stakeAmount = ethers.utils.parseUnits("5", 16);
      await SportsBetting.connect(addr1).stake(dummyFixtureID, betTypeHome, { value: stakeAmount });

      // ASSERT
      await expect(SportsBetting.connect(addr1).unstake(dummyFixtureID, betTypeHome))
        .to.emit(SportsBetting, "BetUnstaked")
        .withArgs(addr1.address, dummyFixtureID, stakeAmount, betTypeHome);

      expect(await SportsBetting.amounts(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(0);

      expect(await SportsBetting.activeBetters(dummyFixtureID, betTypeHome, addr1.address))
        .to.equal(false);
    });
  });

  describe("fulfillKickoffTime", function () {
    it("Should correctly set kickoff time", async function () {
      const { SportsBetting, owner } = await loadFixture(deploySportsBettingFixture);

      // ASSIGN
      const dummyFixtureID = '1234';
      const kickoffTime = 2000007000;

      // ACT & ASSERT
      await expect(SportsBetting.fulfillKickoffTimeTest(dummyFixtureID, kickoffTime))
        .to.emit(SportsBetting, "KickoffTimeUpdated")
        .withArgs(dummyFixtureID, kickoffTime);
    });
  });
});