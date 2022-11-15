import { BigNumber } from 'ethers';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const yaml = require('js-yaml');
const fs = require('fs');
const deployFilename = './deploy/config/goerli.yaml';
const deployObj = yaml.load(fs.readFileSync(deployFilename, {encoding: 'utf-8'}));

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();

    const oracleURI = deployObj.oracle.sportsOracleURI;
    const oracleOperatorCtx = deployObj.oracle.nodeOperatorAddress;
    const linkAddress = deployObj.linkAddress;
    const jobID = deployObj.oracle.jobID;
    const requestFee = BigNumber.from(deployObj.oracle.requestFee); // 0.1 LINK
    const commissionRate = deployObj.commissionRate;

    await deploy('SportsBetting', {
        from: deployer,
        args: [
            oracleURI,
            oracleOperatorCtx,
            linkAddress,
            jobID,
            requestFee,
            commissionRate
        ],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
module.exports = func;
func.tags = ['SportsBetting'];