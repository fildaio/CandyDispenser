pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IRewardPool {

    function rewardToken() external view returns (IERC20);
    function lpToken() external view returns (IERC20);

    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);

    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;

    function withdrawApplication(uint256 amount) external;
    function getReward() external;
}
