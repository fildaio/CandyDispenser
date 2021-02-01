// Load dependencies
const { expect } = require('chai');

// Load compiled artifacts
const BlackList = artifacts.require('BlackList');
const NoMintRewardPool = artifacts.require('NoMintRewardPool');
const IERC20 = artifacts.require('IERC20');

// Start test block
contract('NoMintRewardPool', function () {
  beforeEach(async function () {
    this.bl = await BlackList.new('0x11f7410a09464D737b50838715bf5720038cE429');
    this.token = await IERC20.at('0x17f94db94d9d6f10267c3bb9a35dafd7825de0fd');
    // Deploy a new NoMintRewardPool contract for each test
    this.pool = await NoMintRewardPool.new("0x82d30e24708318c5da73accb7cebc1d0a1d86276", // reward token
    "0x17f94db94d9d6f10267c3bb9a35dafd7825de0fd", // lptoken
    2592000, // duration in second,30 * 24 * 60 * 60
    "0x11f7410a09464D737b50838715bf5720038cE429", // distribution address
    "0x11f7410a09464D737b50838715bf5720038cE429",// governance
    this.bl.address
    );
  });

  // Test case
  it('retrieve returns a value previously stored', async function () {
    let account = web3.utils.toWei('1', 'ether');
    await this.token.approve(this.pool.address, account);
    await this.pool.stake(account);
    console.log((await this.pool.balanceOf('0x11f7410a09464D737b50838715bf5720038cE429')).toString());
    await this.pool.exit();
  });

});
