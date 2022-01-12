
import "./BlackList.sol";
import "./LockPool.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/drafts/Counters.sol";


// File: contracts/IRewardDistributionRecipient.sol

pragma solidity ^0.5.0;



contract IRewardDistributionRecipient is Ownable {
    address rewardDistribution;

    constructor(address _rewardDistribution) public {
        rewardDistribution = _rewardDistribution;
    }

    function notifyRewardAmount(uint256 reward) external;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(address _rewardDistribution)
        external
        onlyOwner
    {
        rewardDistribution = _rewardDistribution;
    }
}

// File: contracts/CurveRewards.sol

pragma solidity ^0.5.0;




/*
*   Changes made to the SynthetixReward contract
*
*   uni to lpToken, and make it as a parameter of the constructor instead of hardcoded.
*
*
*/

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public lpToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    uint256 constant private ratioDenominator = 1e18;
    uint256 private ratioMolecular = 1e18;

    LockPool public lockPool;

    function totalSupply() public view returns (uint256) {
        return getOutActualAmount(_totalSupply);
    }

    function balanceOf(address account) public view returns (uint256) {
        return getOutActualAmount(_balances[account]);
    }

    function totalSupplyInertal() internal view returns (uint256) {
        return _totalSupply;
    }

    function _balanceOf(address account) internal view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        uint256 virtualAmount = getInVirtualAmount(amount);
        _totalSupply = _totalSupply.add(virtualAmount);
        _balances[msg.sender] = _balances[msg.sender].add(virtualAmount);
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function _withdraw(uint256 amount) internal {
        reduceAmount(amount);
        lpToken.safeTransfer(msg.sender, amount);
    }

    function lock(uint256 amount) internal {
        reduceAmount(amount);
        lpToken.approve(address(lockPool), amount);
        lockPool.lock(msg.sender, amount);
    }

    function reduceAmount(uint256 amount) private {
        uint256 virtualAmount = getInVirtualAmount(amount);
        _totalSupply = _totalSupply.sub(virtualAmount);
        _balances[msg.sender] = _balances[msg.sender].sub(virtualAmount);
        if (_balances[msg.sender] < 1000) {
            _balances[msg.sender] = 0;
        }
    }

    function _withdrawAdmin(address account, uint256 amount) internal {
        // Do not sub total supply or user's balance, only recalculate the remaining ratio
        // ratioMolecular = (total-amount)*ratioMolecular/total;
        ratioMolecular = ratioMolecular.mul(_totalSupply.sub(getInVirtualAmount(amount))).div(_totalSupply);
        lpToken.safeTransfer(account, amount);
    }

    function getInVirtualAmount(uint256 amount) private view returns (uint256) {
        return amount.mul(ratioDenominator).div(ratioMolecular);
    }

    function getOutActualAmount(uint256 amount) private view returns (uint256) {
        return amount.mul(ratioMolecular).div(ratioDenominator);
    }
}

pragma solidity ^0.5.0;

contract LPTokenSnapshot is LPTokenWrapper {
    using SafeMath for uint256;
    using Arrays for uint256[];
    using Counters for Counters.Counter;

    // Snapshotted values have arrays of ids and the value corresponding to that id. These could be an array of a
    // Snapshot struct, but that would impede usage of functions that work on an array.
    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    mapping (address => Snapshots) private _accountBalanceSnapshots;
    Snapshots private _totalSupplySnapshots;

    // Snapshot ids increase monotonically, with the first value being 1. An id of 0 is invalid.
    Counters.Counter private _currentSnapshotId;

    /**
     * @dev Emitted by {_snapshot} when a snapshot identified by `id` is created.
     */
    event Snapshot(uint256 id);

    /**
     * @dev Creates a new snapshot and returns its snapshot id.
     *
     * Emits a {Snapshot} event that contains the same id.
     *
     * {_snapshot} is `internal` and you have to decide how to expose it externally. Its usage may be restricted to a
     * set of accounts, for example using {AccessControl}, or it may be open to the public.
     *
     * [WARNING]
     * ====
     * While an open way of calling {_snapshot} is required for certain trust minimization mechanisms such as forking,
     * you must consider that it can potentially be used by attackers in two ways.
     *
     * First, it can be used to increase the cost of retrieval of values from snapshots, although it will grow
     * logarithmically thus rendering this attack ineffective in the long term. Second, it can be used to target
     * specific accounts and increase the cost of ERC20 transfers for them, in the ways specified in the Gas Costs
     * section above.
     *
     * We haven't measured the actual numbers; if this is something you're interested in please reach out to us.
     * ====
     */
    function _snapshot() internal returns (uint256) {
        _currentSnapshotId.increment();

        uint256 currentId = _currentSnapshotId.current();
        emit Snapshot(currentId);
        return currentId;
    }

    /**
     * @dev Retrieves the balance of `account` at the time `snapshotId` was created.
     */
    function balanceOfAt(address account, uint256 snapshotId) public view returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _accountBalanceSnapshots[account]);

        return snapshotted ? value : balanceOf(account);
    }

    /**
     * @dev Retrieves the total supply at the time `snapshotId` was created.
     */
    function totalSupplyAt(uint256 snapshotId) public view returns(uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _totalSupplySnapshots);

        return snapshotted ? value : totalSupply();
    }

    function currentSnapshotId() public view returns(uint256) {
        return _currentSnapshotId.current();
    }

    // Update balance and/or total supply snapshots before the values are modified.
    function _beforeTokenTransfer(address account) internal {
        _updateAccountSnapshot(account);
        _updateTotalSupplySnapshot();
    }

    function _valueAt(uint256 snapshotId, Snapshots storage snapshots)
        private view returns (bool, uint256)
    {
        require(snapshotId > 0, "LPTokenSnapshot: id is 0");
        // solhint-disable-next-line max-line-length
        require(snapshotId <= _currentSnapshotId.current(), "LPTokenSnapshot: nonexistent id");

        // When a valid snapshot is queried, there are three possibilities:
        //  a) The queried value was not modified after the snapshot was taken. Therefore, a snapshot entry was never
        //  created for this id, and all stored snapshot ids are smaller than the requested one. The value that corresponds
        //  to this id is the current one.
        //  b) The queried value was modified after the snapshot was taken. Therefore, there will be an entry with the
        //  requested id, and its value is the one to return.
        //  c) More snapshots were created after the requested one, and the queried value was later modified. There will be
        //  no entry for the requested id: the value that corresponds to it is that of the smallest snapshot id that is
        //  larger than the requested one.
        //
        // In summary, we need to find an element in an array, returning the index of the smallest value that is larger if
        // it is not found, unless said value doesn't exist (e.g. when all values are smaller). Arrays.findUpperBound does
        // exactly this.

        uint256 index = snapshots.ids.findUpperBound(snapshotId);

        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(address account) private {
        _updateSnapshot(_accountBalanceSnapshots[account], balanceOf(account));
    }

    function _updateTotalSupplySnapshot() private {
        _updateSnapshot(_totalSupplySnapshots, totalSupply());
    }

    function _updateSnapshot(Snapshots storage snapshots, uint256 currentValue) private {
        uint256 currentId = _currentSnapshotId.current();
        if (_lastSnapshotId(snapshots.ids) < currentId) {
            snapshots.ids.push(currentId);
            snapshots.values.push(currentValue);
        }
    }

    function _lastSnapshotId(uint256[] storage ids) private view returns (uint256) {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }
}


/*
*   [Harvest]
*   This pool doesn't mint.
*   the rewards should be first transferred to this pool, then get "notified"
*   by calling `notifyRewardAmount`
*/

contract NoMintRewardPool is LPTokenSnapshot, IRewardDistributionRecipient, Governable {

    using Address for address;

    string public name;
    IERC20 public rewardToken;
    uint256 public duration; // making it not a constant is less gas efficient, but portable

    address public blackList;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping (address => bool) smartContractStakers;

    uint256 public adminWithdrawPeriod = 60 * 60 * 96;
    uint256 constant delayDuration = 24 * 60 * 60;

    address public adminWithdraw;
    uint256 public adminWithdrawTime = 0;

    uint256 public withdrawPeriod;

    address public snapshotCaller;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event WithdrawApplied(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardDenied(address indexed user, uint256 reward);
    event SmartContractRecorded(address indexed smartContractAddress, address indexed smartContractInitiator);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyCallerOrGovernance() {
        require(isGovernance(msg.sender) || (snapshotCaller != address(0) && msg.sender == snapshotCaller), "Not governance or caller");
        _;
    }

    // [Hardwork] setting the reward, lpToken, duration, and rewardDistribution for each pool
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
    IRewardDistributionRecipient(_rewardDistribution)
    Governable(_governance)
    {
        name = _name;
        rewardToken = IERC20(_rewardToken);
        lpToken = IERC20(_lpToken);
        duration = _duration;
        blackList = _blackList;

        adminWithdraw = _adminWithdraw;
        adminWithdrawTime = block.timestamp + adminWithdrawPeriod;

        _setLockPool(_lockPool, _withdrawPeriod);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupplyInertal() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupplyInertal())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            _balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public updateReward(msg.sender) {
        require(blackList == address(0) || !BlackList(blackList).blackList(msg.sender), "Cannot stake");
        require(amount > 0, "Cannot stake 0");
        recordSmartContract();

        _beforeTokenTransfer(msg.sender);

        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        if (withdrawPeriod == 0) {
            _beforeTokenTransfer(msg.sender);
            _withdraw(fixAmount(amount));
        } else {
            lockPool.withdraw(msg.sender, amount);
        }
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        if (withdrawPeriod == 0) {
            withdraw(balanceOf(msg.sender));
        } else {
            require(balanceOf(msg.sender) == 0, "Please apply first");
            withdraw(lockPool.lockedBalance(msg.sender));
        }
        getReward();
    }

    function withdrawApplication(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(withdrawPeriod != 0, "Withdraw period is 0, call withdraw directly");

        _beforeTokenTransfer(msg.sender);

        lock(fixAmount(amount));
        emit WithdrawApplied(msg.sender, amount);
    }

    function fixAmount(uint256 amount) private view returns (uint256) {
        uint256 b = balanceOf(msg.sender);
        require(b > 0, "balance is 0");
        return amount > b ? b : amount;
    }

    /// A push mechanism for accounts that have not claimed their rewards for a long time.
    /// The implementation is semantically analogous to getReward(), but uses a push pattern
    /// instead of pull pattern.
    function pushReward(address recipient) public updateReward(recipient) onlyGovernance {
        uint256 reward = earned(recipient);
        if (reward > 0) {
            rewards[recipient] = 0;
            if (blackList == address(0) || !BlackList(blackList).blackList(recipient)) {
                rewardToken.safeTransfer(recipient, reward);
                emit RewardPaid(recipient, reward);
            } else {
               emit RewardDenied(recipient, reward);
            }
        }
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            if (blackList == address(0) || !BlackList(blackList).blackList(msg.sender)) {
                rewardToken.safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, reward);
            } else {
                emit RewardDenied(msg.sender, reward);
            }
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        onlyRewardDistribution
        updateReward(address(0))
    {
        // overflow fix according to https://sips.synthetix.io/sips/sip-77
        require(reward < uint(-1) / 1e18, "the notified reward cannot invoke multiplication overflow");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(duration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(duration);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(duration);
        emit RewardAdded(reward);
    }

    // Harvest Smart Contract recording
    function recordSmartContract() internal {
      if( tx.origin != msg.sender ) {
        smartContractStakers[msg.sender] = true;
        emit SmartContractRecorded(msg.sender, tx.origin);
      }
    }

    function setBlackList(address _blackList) external onlyGovernance {
        blackList = _blackList;
    }

    function setAdminWithdrawPeriod(uint256 period) external onlyGovernance {
        if (address(lockPool) != address(0)) {
            uint256 lockPeriod = lockPool.withdrawPeriod();
            require(period >= lockPeriod.add(delayDuration), "administrator withdrawal delay is less than 24 hours");
        }

        adminWithdrawPeriod = period;
    }

    function setWithdrawAdmin(address account) public onlyGovernance {
        adminWithdraw = account;
        adminWithdrawTime = block.timestamp + adminWithdrawPeriod;
    }

    function withdrawAdmin(uint256 amount) external onlyGovernance {
        require(adminWithdraw != address(0), "Please set withdraw admin account first");
        require(block.timestamp >= adminWithdrawTime, "It's not time to withdraw");
        require(totalSupplyInertal() > 0, "total supply is 0!");
        require(amount <= totalSupply().div(2), "admin withdraw amount must be less than half of total supply!");
        _withdrawAdmin(adminWithdraw, amount);
        emit Withdrawn(adminWithdraw, amount);
    }

    function lockedBalance() external view returns (uint256) {
        return lockPool.lockedBalance(msg.sender);
    }

    function withdrawTime() external view returns (uint256) {
        return lockPool.withdrawTime(msg.sender);
    }

    function snapshot() external onlyCallerOrGovernance returns (uint256) {
        return _snapshot();
    }

    function setSnapshotCaller(address caller) external onlyGovernance {
        snapshotCaller = caller;
    }

    function _setLockPool(address _lockPool, uint256 _withdrawPeriod) private {
        withdrawPeriod = _withdrawPeriod;
        if (_withdrawPeriod != 0) {
            require(_lockPool != address(0), "Please set lock pool contract");
            lockPool = LockPool(_lockPool);
        }
    }

    function setLockPool(address _lockPool, uint256 _withdrawPeriod) external onlyGovernance {
        _setLockPool(_lockPool, _withdrawPeriod);
    }

    function pullRewardToken(uint256 amount) external onlyGovernance {
        if (amount > rewardToken.balanceOf(address(this))) {
            amount = rewardToken.balanceOf(address(this));
        }

        rewardToken.safeTransfer(governance, amount);
    }
}
