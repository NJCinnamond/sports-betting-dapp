// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { BigNumber } from "ethers";
import { ethers } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const sportsOracleURI = "https://1vyuff64d9.execute-api.us-east-1.amazonaws.com/dev/fixtures/";
  const goerliOracleOperatorCtx = "0xcc79157eb46f5624204f47ab42b3906caa40eab7";
  const goerliLinkAddress = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
  const goerliOracleJobID = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("7d80a6386ef543a3abb52817f6707e3b"));
  console.log("Job id: ", goerliOracleJobID);
  const goerliOracleRequestFee = BigNumber.from("100000000000000000"); // 0.1 LINK
  console.log("Fee: ", goerliOracleRequestFee);

  // We get the contract to deploy
  const SportsBetting = await ethers.getContractFactory("SportsBetting");
  const sportsBetting = await SportsBetting.deploy(
    sportsOracleURI,
    goerliOracleOperatorCtx,
    goerliLinkAddress,
    goerliOracleJobID,
    goerliOracleRequestFee
  );

  await sportsBetting.deployed();

  console.log("SportsBetting deployed to:", sportsBetting.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
