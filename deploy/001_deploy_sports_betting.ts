import { BigNumber, ethers } from 'ethers';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();

    // TODO: Parametrize this in YAML
    const sportsOracleURI = "localhost:5000/";
    const goerliOracleOperatorCtx = "0xcc79157eb46f5624204f47ab42b3906caa40eab7";
    const goerliLinkAddress = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
    const goerliOracleJobID = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("7d80a6386ef543a3abb52817f6707e3b"));
    const goerliOracleRequestFee = BigNumber.from("100000000000000000"); // 0.1 LINK

    await deploy('SportsBetting', {
        from: deployer,
        args: [
            sportsOracleURI,
            goerliOracleOperatorCtx,
            goerliLinkAddress,
            goerliOracleJobID,
            goerliOracleRequestFee
        ],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
export default func;
func.tags = ['SportsBetting'];