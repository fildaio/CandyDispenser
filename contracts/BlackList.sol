pragma solidity ^0.5.0;

import "./Governable.sol";

contract BlackList is Governable {
    mapping (address => bool) public blackList;

    constructor(address _governance) public Governable(_governance) {
    }

    function addToBlackList(address _target) public onlyGovernance {
        blackList[_target] = true;
    }

    function removeFromBlackList(address _target) public onlyGovernance {
        blackList[_target] = false;
    }
}
