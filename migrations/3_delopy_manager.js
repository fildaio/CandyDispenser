const PoolManager = artifacts.require("PoolManager");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

module.exports = async function (deployer) {
    const governance = "0x";
    await deployProxy(PoolManager, [governance], { deployer, unsafeAllowCustomTypes: 'PoolEntity' });
    console.log("***********************************************");
    console.log("PoolManager address:", PoolManager.address);
    console.log("***********************************************");
};
