pragma solidity ^0.5.0;

contract NoteVoting {
    function userInfo(uint256 pid, address user) external view returns(uint256 amount, uint256 rewardDebt);
}

contract HtNodeVoteWhitelist {
    NoteVoting public votePool;
    uint256 public votePoolId;

    constructor(address _votePool, uint256 _votePoolId) public {
        require(_votePool != address(0), "zero vote pool address");
        votePool = NoteVoting(_votePool);
        votePoolId = _votePoolId;
    }

    function exist(address _target) public view returns (bool) {
        (uint256 voteAmount,) = votePool.userInfo(votePoolId, _target);
        return voteAmount > 0;
    }
}