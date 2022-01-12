// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "./BoringOwnable.sol";
import "./RewardPool.sol";
import "@openzeppelin/contracts/lifecycle/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FiLDAVault is BoringOwnable, Pausable, ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private _initialExchangeRate;

    IERC20 public underlying;

    NoMintRewardPool public rewardPool;

    bool public contractAllowed = true;

    uint constant EXP_SCALE = 1e18;

    event ContractAllowed(bool _allowed);
    event Deposited(address from, address to, uint256 amount);
    event Withdrawn(address from, address to, uint256 amount);

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

        rewardPool = NoMintRewardPool(rewardPool_);
        require(rewardPool.rewardToken() == rewardPool.lpToken(), "reward pool rewardToken is not equal to lpToken");
        underlying = rewardPool.rewardToken();

        underlying.safeApprove(rewardPool_, uint(-1));
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

        underlying.safeTransferFrom(msg.sender, address(this), amount);
        require(avilable() >= amount, "transfer in amount error");

        rewardPool.stake(avilable());

        uint256 mintAmount = amount.mul(EXP_SCALE).div(exchangeRate);
        _mint(to, mintAmount);
        emit Deposited(msg.sender, to, amount);
    }

    function withdraw(uint256 amount, address to) external checkContract {
        rewardPool.getReward();

        uint exchangeRate = exchangeRateStored();

        _burn(msg.sender, amount);
        uint256 underlyingAmount = exchangeRate.mul(amount).div(EXP_SCALE);
        if (avilable() < underlyingAmount) {
            rewardPool.withdraw(underlyingAmount.sub(avilable()));
        } else if (avilable() > underlyingAmount) {
            rewardPool.stake(avilable().sub(underlyingAmount));
        }

        underlying.safeTransfer(to, underlyingAmount);
        emit Withdrawn(msg.sender, to, underlyingAmount);
    }

    function withdrawUnderlying(uint256 amount, address to) external checkContract {
        rewardPool.getReward();

        uint256 tokenAmount = amount.mul(EXP_SCALE).div(exchangeRateStored());
        _burn(msg.sender, tokenAmount);

        if (avilable() < amount) {
            rewardPool.withdraw(amount.sub(avilable()));
        } else if (avilable() > amount) {
            rewardPool.stake(avilable().sub(amount));
        }

        underlying.safeTransfer(to, amount);
        emit Withdrawn(msg.sender, to, amount);
    }

    function reinvest() public checkContract {
        rewardPool.getReward();
        if (avilable() > 0) {
            rewardPool.stake(avilable());
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
        return underlying.balanceOf(address(this));
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
