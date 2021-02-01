pragma solidity ^0.5.0;

import "./GovernableInitiable.sol";

contract PoolManager is GovernableInitiable {

    struct PoolEntity {
        bool visible;
        uint index;
    }
    mapping (address => PoolEntity) poolEntities;
    address[] public poolList;

    event PoolVisibilityChanged(address pool, bool visible, uint index);
    event PoolDeleted(address pool);

    function initialize(address _governance) public initializer {
        GovernableInitiable.initialize(_governance);
    }

    function exist(address pool) public view returns (bool) {
        if(poolList.length == 0 || poolEntities[pool].index >= poolList.length) return false;
        return (poolList[poolEntities[pool].index] == pool);
    }

    function register(address pool, bool visible) public onlyGovernance returns (uint) {
        require(!exist(pool), "aready exist!");
        uint index = poolList.push(pool) - 1;
        poolEntities[pool].visible = visible;
        poolEntities[pool].index = index;
        return index;
    }

    function getLength() public view returns (uint) {
        return poolList.length;
    }

    function isVisible(address pool) public view returns (bool) {
        if(!exist(pool)) return false;
        return poolEntities[pool].visible;
    }

    function updateVisibility(address pool, bool visible) public onlyGovernance {
        require(exist(pool), "not registered");
        poolEntities[pool].visible = visible;
        emit PoolVisibilityChanged(pool, visible, poolEntities[pool].index);
    }

    function unregister(address pool) external onlyGovernance returns (uint) {
        require(exist(pool), "not exist");
        if (poolList.length == 1) {
            reduceList(pool);
            return 0;
        }
        uint rowToDelete = poolEntities[pool].index;
        address keyToMove = poolList[poolList.length-1];
        poolList[rowToDelete] = keyToMove;
        poolEntities[keyToMove].index = rowToDelete;
        reduceList(pool);
        return rowToDelete;
    }

    function reduceList(address pool) private {
        poolList.length--;
        emit PoolDeleted(pool);
    }
}
