# CandyDispenser

## 自动复投合约部署流程

### 安装依赖

```bash
npm install
```

### 部署合约

#### NoMintRewardPool

先部署NoMintRewardPool, 这是一个质押奖励池合约，可以设定锁定周期

```bash
constructor(string memory _name,
        address _rewardToken,
        address _lpToken,
        uint256 _duration,
        address _rewardDistribution,
        address _governance,
        address _blackList,
        address _adminWithdraw,
        uint256 _withdrawPeriod,
        address _lockPool) public
```

- `_name` 池子名字.
- `_rewardToken` 奖励token地址
- `_lpToken` 质押token地址，可以与`_rewardToken`相同
- `_duration` 池子的周期时间，单位是秒
- `_rewardDistribution` 启动池子的管理员
- `_governance` 池子的治理者，可以做一些池子的设定类操作
- `_blackList` 黑名单(BlackList)合约地址，可以设置为0
- `_adminWithdraw` 提款管理员地址，对于锁定周期的池子，可以设定管理员提取，提取的最大比例是质押总量的50%
- `_withdrawPeriod` 池子锁定周期，可以设定为0，单位秒
- `_lockPool` 锁定池(LockVaultPool)地址，如果没有锁定周期可以设定为0，当该参数不为0时，`_withdrawPeriod`也不可以为0

#### LockVaultPool

部署LockVaultPool，这个池子同时作为NoMintRewardPool的锁定池和自动复投池，它也是一个ERC20 token，用户通过它来质押的话，会等比mint给用户它的代币

```bash
constructor(string memory name_, string memory symbol_, uint256 initialExchangeRate_, address rewardPool_) public
```

- `name_` token名称
- `symbol_` token标识
- `initialExchangeRate_` 初始兑换率，第一个质押进来的用户会使用它来计算mint的代币数量，mintAmount = stakeAmount * EXP_SCALE / initialExchangeRate_, EXP_SCALE为1e18
- `rewardPool_` 奖励池地址(NoMintRewardPool)

#### NoMintRewardPool设定lockPool地址

以上两个合约都部署好之后，取得NoMintRewardPool的实例，调用setLockPool设定锁定池(LockVaultPool)地址和锁定周期

```bash
let pool = await NoMintRewardPool.deployed();
await pool.setLockPool(LockVaultPool.address, _withdrawPeriod);
```

## 接口

### NoMintRewardPool

* <span> stake </span>
```bash
function stake(uint256 amount) public
```
质押代币

    参数说明
       - amount 用户质押数量

* <span> withdraw </span>
```bash
function withdraw(uint256 amount) public
```
提取质押代币，该方法不会自动发奖励
对于没有锁定周期的池子，调用该方法直接提取，有锁定周期的池子，该方法只能提取已经申请提取的代币(如果锁定周期未到，会扣除一定比例销毁)

    参数说明
       - amount 用户提取数量

* <span> exit </span>
```bash
function exit() external
```
退出质押，提取用户质押的所有代币，并且自动发奖励


* <span> withdrawApplication </span>
```bash
function withdrawApplication(uint256 amount) external
```
有锁定周期的池子用于申请提取，申请之后进入锁定周期

    参数说明
       - amount 用户申请提取数量

* <span> getReward </span>
```bash
function getReward() public
```
提取奖励

* <span> earned </span>
```bash
function earned(address account) public view returns (uint256)
```
读取账户应得奖励数量

    参数说明
       - account 用户账户地址

    返回值说明
       - 用户应得奖励数量

* <span> lockedBalance </span>
```bash
function lockedBalance() external view returns (uint256)
```
读取调用者锁定代币数量

    返回值说明
       - 用户锁定数量

* <span> withdrawTime </span>
```bash
function withdrawTime() external view returns (uint256)
```
读取调用者锁定代币提取时间

    返回值说明
       - 用户锁定代币提取时间


* <span> notifyRewardAmount </span>
```bash
function notifyRewardAmount(uint256 reward)
        external
        onlyRewardDistribution
```
启动池子，该方法只能设定的rewardDistribution调用，该方法不会从调用者地址转代币

    参数说明
       - reward 奖励token数量

### LockVaultPool

LockVaultPool既可以作为NoMintRewardPool的锁定池，也可以做自动复投池，通过LockVaultPool质押的token会进入NoMintRewardPool，并且奖励会自动复投

* <span> withdrawBySender </span>
```bash
function withdrawBySender(uint256 amount) public
```
从锁定池提取质押token，只能提取从NoMintRewardPool申请提取的部分。如果还在锁定时间内，默认扣除20%的质押token销毁

    参数说明
       - amount 提取数量


* <span> deposit </span>
```bash
function deposit(uint256 amount, address to) public
```
质押token，按比例返回一个凭证token，资金进入NoMintRewardPool，奖励自动复投

    参数说明
       - amount 用户质押数量
       - to 质押记账地址


* <span> deposit </span>
```bash
function deposit(uint256 amount) external
```
与前一个方法相同，记账地址为调用者地址

    参数说明
       - amount 用户质押数量


* <span> cancelLock </span>
```bash
function cancelLock(uint256 amount, address to) public
```
取消锁定，取消的token重新进入NoMintRewardPool

    参数说明
       - amount 取消锁定数量
       - to 质押记账地址


* <span> cancelLock </span>
```bash
function cancelLock(uint256 amount) public
```
与前一个方法相同，记账地址为调用者地址

    参数说明
       - amount 取消锁定数量

* <span> vaultWithdraw </span>
```bash
function vaultWithdraw(uint256 amount, address to) public
```
提取自动复投的质押token，销毁amount数量的凭证，资金从NoMintRewardPool提取，如果有锁定周期进入锁定，没有锁定周期直接转给to地址

    参数说明
       - amount 用户要提取的凭证数量
       - to 质押token转移地址


* <span> vaultWithdraw </span>
```bash
function vaultWithdraw(uint256 amount) external
```
与前一个方法相同，token转移地址为调用者地址

    参数说明
       - amount 用户要提取的凭证数量


* <span> vaultWithdrawUnderlying </span>
```bash
function vaultWithdrawUnderlying(uint256 amount, address to) public
```
提取自动复投的质押token，按比例销毁凭证，资金从NoMintRewardPool提取，如果有锁定周期进入锁定，没有锁定周期直接转给to地址

    参数说明
       - amount 用户要提取的质押token数量
       - to 质押token转移地址


* <span> vaultWithdrawUnderlying </span>
```bash
function vaultWithdrawUnderlying(uint256 amount) external
```
与前一个方法相同，token转移地址为调用者地址

    参数说明
       - amount 用户要提取的质押token数量

* <span> exchangeRate </span>
```bash
function exchangeRate() public returns (uint256)
```
质押token与凭证token的兑换率，计算公式为 凭证数量 = 质押数量 * EXP_SCALE / exchangeRate, EXP_SCALE为1e18

    返回值说明
       - 兑换率


* <span> balanceOfUnderlying </span>
```bash
function balanceOfUnderlying(address account) public returns(uint256)
```
读取该账户在自动复投池的质押token数量

    参数说明
       - account 用户账户地址

    返回值说明
       - 用户token数量


* <span> balanceOf </span>
```bash
function balanceOf(address account) public returns(uint256)
```
读取该账户在自动复投池的凭证数量

    参数说明
       - account 用户账户地址

    返回值说明
       - 用户凭证数量
