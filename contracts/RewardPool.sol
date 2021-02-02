
import "./BlackList.sol";
import "./LockPool.sol";


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

/*
*   [Harvest]
*   This pool doesn't mint.
*   the rewards should be first transferred to this pool, then get "notified"
*   by calling `notifyRewardAmount`
*/

contract NoMintRewardPool is LPTokenWrapper, IRewardDistributionRecipient, Governable {

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
        setWithdrawAdmin(_adminWithdraw);

        withdrawPeriod = _withdrawPeriod;
        if (_withdrawPeriod != 0) {
            require(_lockPool != address(0), "Please set lock pool contract");
            lockPool = LockPool(_lockPool);
        }
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

        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        if (withdrawPeriod == 0) {
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

    function lockedBalanceByAccount(address account) external view returns (uint256) {
        return lockPool.lockedBalance(account);
    }

    function withdrawTimeByAccount(address account) external view returns (uint256) {
        return lockPool.withdrawTime(account);
    }


}
