pragma solidity ^0.5.0;

import "./IRewardPool.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/lifecycle/Pausable.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract LockVaultPool is Ownable, Pausable, ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private _initialExchangeRate;

    IERC20 public lpToken;
    uint256 public withdrawPeriod = 72 hours;
    IRewardPool public rewardPool;

    struct WithDrawEntity {
        uint256 amount;
        uint256 time;
    }

    mapping (address => WithDrawEntity) private withdrawEntities;
    uint256 public totalLocked;

    bool public contractAllowed = true;

    uint constant EXP_SCALE = 1e18;

    bool private inExe = false;
    address private exeAccount = address(0);

    uint256 public feeMolecular = 2000;
    uint256 private constant FEE_DENOMINATOR = 10000;

    event WithdrawPeriodChanged(uint256 indexed _withdrawPeriod);
    event FeeChanged(uint256 indexed _fee);
    event ContractAllowed(bool _allowed);
    event Deposited(address from, address to, uint256 amount);
    event Withdrawn(address from, address to, uint256 amount);

    modifier onlyRewardPool() {
        require(msg.sender == address(rewardPool), "Not reward pool");
        _;
    }

    modifier checkContract() {
        if (!contractAllowed)  {
            require(!isContract(msg.sender), "contract is not allowed");
            require(msg.sender == tx.origin, "proxy contract is not allowed");
        }
        _;
    }

    constructor(string memory name_, string memory symbol_, uint256 initialExchangeRate_, address rewardPool_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        _initialExchangeRate = initialExchangeRate_;

        if (rewardPool_ != address(0)) {
            rewardPool = IRewardPool(rewardPool_);
            require(rewardPool.rewardToken() == rewardPool.lpToken(), "reward pool rewardToken is not equal to lpToken");
            lpToken = rewardPool.rewardToken();

            lpToken.safeApprove(rewardPool_, uint(-1));
        }

    }

    function setRewardPool(address _pool) external onlyOwner {
        require(_pool != address(0), "reward pool shouldn't be empty");

        rewardPool = IRewardPool(_pool);
        require(rewardPool.rewardToken() == rewardPool.lpToken(), "reward pool rewardToken is not equal to lpToken");
        lpToken = rewardPool.rewardToken();

        lpToken.safeApprove(_pool, uint(-1));
    }

    function setWithdrawPeriod(uint256 _withdrawPeriod) external onlyOwner {
        withdrawPeriod = _withdrawPeriod;
        emit WithdrawPeriodChanged(_withdrawPeriod);
    }

    function setFee(uint256 _fee) external onlyOwner {
        feeMolecular = _fee;
        emit FeeChanged(_fee);
    }

    function lock(address account, uint256 amount) external onlyRewardPool {
        if (inExe && exeAccount != address(0)) {
            withdrawEntities[exeAccount].amount = withdrawEntities[exeAccount].amount.add(amount);
            withdrawEntities[exeAccount].time = block.timestamp;
        } else {
            withdrawEntities[account].amount = withdrawEntities[account].amount.add(amount);
            withdrawEntities[account].time = block.timestamp;
        }
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        totalLocked = totalLocked.add(amount);
    }

    function withdraw(address account, uint256 amount) external onlyRewardPool {
        _withdraw(account, amount);
    }

    function withdrawBySender(uint256 amount) public {
        _withdraw(msg.sender, amount);
    }

    function _withdraw(address account, uint256 amount) private {
        require(withdrawEntities[account].amount > 0 && withdrawEntities[account].time > 0, "not applied!");
        if (amount > withdrawEntities[account].amount) {
            amount = withdrawEntities[account].amount;
        }
        withdrawEntities[account].amount = withdrawEntities[account].amount.sub(amount);
        if (withdrawEntities[account].amount == 0) {
            withdrawEntities[account].time = 0;
        }

        totalLocked = totalLocked.sub(amount);
        if (block.timestamp >= withdrawTime(account)) {
            lpToken.safeTransfer(account, amount);
        } else {
            uint256 fee = amount.mul(feeMolecular).div(FEE_DENOMINATOR);
            ERC20Burnable(address(lpToken)).burn(fee);
            lpToken.safeTransfer(account, amount.sub(fee));
        }
    }

    function lockedBalance(address account) external view returns (uint256) {
        return withdrawEntities[account].amount;
    }

    function withdrawTime(address account) public view returns (uint256) {
        return withdrawEntities[account].time + withdrawPeriod;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function setContractAllowed(bool _allowed) public onlyOwner {
        contractAllowed = _allowed;
        emit ContractAllowed(_allowed);
    }

    function deposit(uint256 amount, address to) external whenNotPaused checkContract {
        reinvest();
        uint256 exchangeRate = exchangeRateStored();

        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        require(avilable() >= amount, "transfer in amount error");

        rewardPool.stake(avilable());

        uint256 mintAmount = amount.mul(EXP_SCALE).div(exchangeRate);
        _mint(to, mintAmount);
        emit Deposited(msg.sender, to, amount);
    }

    function cancelLock(uint256 amount, address to) external whenNotPaused checkContract {
        require(withdrawEntities[msg.sender].amount > 0 && withdrawEntities[msg.sender].time > 0, "not applied!");
        require(withdrawEntities[msg.sender].amount >= amount, "applied amount is not enough!");

        reinvest();
        uint256 exchangeRate = exchangeRateStored();
        withdrawEntities[msg.sender].amount = withdrawEntities[msg.sender].amount.sub(amount);
        if (withdrawEntities[msg.sender].amount == 0) {
            withdrawEntities[msg.sender].time = 0;
        }

        totalLocked = totalLocked.sub(amount);

        rewardPool.stake(amount);
        uint256 mintAmount = amount.mul(EXP_SCALE).div(exchangeRate);
        _mint(to, mintAmount);
        emit Deposited(msg.sender, to, amount);
    }

    function vaultWithdraw(uint256 amount, address to) external checkContract {
        reinvest();

        uint exchangeRate = exchangeRateStored();

        _burn(msg.sender, amount);
        uint256 underlyingAmount = exchangeRate.mul(amount).div(EXP_SCALE);
        if (withdrawPeriod == 0) {
            rewardPool.withdraw(underlyingAmount);
            lpToken.safeTransfer(to, underlyingAmount);
            emit Withdrawn(msg.sender, to, underlyingAmount);
        } else {
            inExe = true;
            exeAccount = to;

            rewardPool.withdrawApplication(underlyingAmount);

            inExe = false;
            exeAccount = address(0);
        }
    }

    function vaultWithdrawUnderlying(uint256 amount, address to) external checkContract {
        reinvest();

        uint256 tokenAmount = amount.mul(EXP_SCALE).div(exchangeRateStored());
        _burn(msg.sender, tokenAmount);

        if (withdrawPeriod == 0) {
            rewardPool.withdraw(amount);
            lpToken.safeTransfer(to, amount);
            emit Withdrawn(msg.sender, to, amount);
        } else {
            inExe = true;
            exeAccount = to;

            rewardPool.withdrawApplication(amount);

            inExe = false;
            exeAccount = address(0);
        }
    }

    function reinvest() public checkContract {
        rewardPool.getReward();
        uint256 avl = avilable();
        if (avl > 0) {
            rewardPool.stake(avl);
        }
    }

    function exchangeRate() public returns (uint256) {
        reinvest();
        return exchangeRateStored();
    }

    function exchangeRateStored() public view returns (uint256) {
        if (totalSupply() == 0) {
            return _initialExchangeRate;
        } else {
            uint256 balance = rewardPool.balanceOf(address(this)).add(avilable());
            return balance.mul(EXP_SCALE).div(totalSupply());
        }
    }

    function balanceOfUnderlying(address account) public returns(uint256) {
        return exchangeRate().mul(balanceOf(account)).div(EXP_SCALE);
    }

    function avilable() internal view returns(uint256) {
        return lpToken.balanceOf(address(this)).sub(totalLocked);
    }

    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}
