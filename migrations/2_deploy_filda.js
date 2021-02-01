const BlackList = artifacts.require("BlackList");
const NoMintRewardPool = artifacts.require("NoMintRewardPool");
const LockPool = artifacts.require("LockPool");

module.exports = async function (deployer, network, accounts) {

  await deployer.deploy(BlackList, "0x");
  await deployer.deploy(LockPool);

  var duration = 24 * 60 * 60;
  var withdrawPeriod = 5 * 60;
  var lpToken = "0x";

  await deployer.deploy(NoMintRewardPool,
      "",// name,
      "0x", // reward token
      lpToken, // lptoken
      duration, // duration in second
      "0x", // distribution account
      "0x", // governance
      BlackList.address,
      "0x", // witdraw admin account
      withdrawPeriod, // withdraw period
      LockPool.address // lock pool address
  );

  var lockPool = await LockPool.deployed();
  await lockPool.setRewardPool(NoMintRewardPool.address, lpToken);
  await lockPool.setWithdrawPeriod(withdrawPeriod);

  console.log("***********************************************");
  console.log("Pool address:", NoMintRewardPool.address);
  console.log("***********************************************");
};
