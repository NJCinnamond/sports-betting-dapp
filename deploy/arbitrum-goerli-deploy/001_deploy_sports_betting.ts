import { BigNumber, ethers } from 'ethers';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();

    // TODO: Parametrize this in YAML
    const sportsOracleURI = "https://1vyuff64d9.execute-api.us-east-1.amazonaws.com/dev/premier-league/fixtures/";
    const arbitrumGoerliOracleOperatorCtx = "0x2362A262148518Ce69600Cc5a6032aC8391233f5";
    const arbitrumGoerliLinkAddress = "0xd14838A68E8AFBAdE5efb411d5871ea0011AFd28";
    const arbitrumGoerliOracleJobID = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("7599d3c8f31e4ce78ad2b790cbcfc673"));
    const arbitrumGoerliOracleRequestFee = BigNumber.from("100000000000000000"); // 0.1 LINK
    const commissionRate = 1;

    await deploy('SportsBetting', {
        from: deployer,
        args: [
            sportsOracleURI,
            arbitrumGoerliOracleOperatorCtx,
            arbitrumGoerliLinkAddress,
            arbitrumGoerliOracleJobID,
            arbitrumGoerliOracleRequestFee,
            commissionRate
        ],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
export default func;
func.tags = ['SportsBetting'];