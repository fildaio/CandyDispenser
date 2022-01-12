pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract LockPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public lpToken;
    uint256 public withdrawPeriod = 60 * 60 * 72;
    address public rewardPool;

    uint256 public feeMolecular = 2000;
    uint256 private constant FEE_DENOMINATOR = 10000;

    event WithdrawPeriodChanged(uint256 indexed _withdrawPeriod);
    event FeeChanged(uint256 indexed _fee);

    struct WithDrawEntity {
        uint256 amount;
        uint256 time;
    }

    mapping (address => WithDrawEntity) private withdrawEntities;

    modifier onlyRewardPool() {
        require(msg.sender == rewardPool, "Not reward pool");
        _;
    }

    function setRewardPool(address _pool, address _lpToken) external onlyOwner {
        require(_pool != address(0) && _lpToken != address(0), "reward pool and token address shouldn't be empty");
        rewardPool = _pool;
        lpToken = IERC20(_lpToken);
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
        withdrawEntities[account].amount = withdrawEntities[account].amount.add(amount);
        withdrawEntities[account].time = block.timestamp;
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
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

}
