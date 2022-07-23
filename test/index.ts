import { expect } from "chai";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers, network, waffle } from "hardhat";
const { deployMockContract, provider } = waffle;

const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// Contract enums
const bettingStateClosed = 0;
const bettingStateOpen = 1;

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
    it("Should open if bet is CLOSED, kickoff time is present and valid timestamp", async function () {
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
  });
});