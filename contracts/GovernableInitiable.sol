pragma solidity ^0.5.0;

import "@openzeppelin/upgrades/contracts/Initializable.sol";

contract GovernableInitiable is Initializable {

    bytes32 internal constant _GAVERNANCE_SLOT = bytes32(uint256(keccak256("filda.Governance.slot")) - 1);

    function initialize(address _governance) public initializer {
        _setGovernance(_governance);
    }

    modifier onlyGovernance() {
        require(isGovernance(msg.sender), "Not governance");
        _;
    }

    function setGovernance(address _governance) public onlyGovernance {
        require(_governance != address(0), "new governance shouldn't be empty");
        _setGovernance(_governance);
    }

    function _setGovernance(address _governance) private {
        bytes32 slot = _GAVERNANCE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _governance)
        }
    }

    function governance() public view returns (address str) {
        bytes32 slot = _GAVERNANCE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            str := sload(slot)
        }
    }

    function isGovernance(address account) public view returns (bool) {
        return account == governance();
    }
}
