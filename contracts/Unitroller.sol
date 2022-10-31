pragma solidity ^0.5.16;

import "./ErrorReporter.sol";
import "./ComptrollerStorage.sol";

/**
 * @title ComptrollerCore
 * @dev 审计员的存储在这个地址，而执行被委托给`comptrollerImplementation`。
 * CTokens 应该将此合约作为他们的主计长。
 */
// 代理合约
contract Unitroller is UnitrollerAdminStorage, ComptrollerErrorReporter {
    /**
     * @notice Emitted when pendingComptrollerImplementation is changed
     */
    event NewPendingImplementation(
        address oldPendingImplementation,
        address newPendingImplementation
    );

    /**
     * @notice Emitted when pendingComptrollerImplementation is accepted, which means comptroller implementation is updated
     */
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

    /**
     * @notice Emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    constructor() public {
        // Set admin to caller
        admin = msg.sender;
    }

    /*** Admin Functions ***/
    // 管理员函数
    function _setPendingImplementation(address newPendingImplementation)
        public
        returns (uint)
    {
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PENDING_IMPLEMENTATION_OWNER_CHECK
                );
        }

        address oldPendingImplementation = pendingComptrollerImplementation;

        pendingComptrollerImplementation = newPendingImplementation;

        emit NewPendingImplementation(
            oldPendingImplementation,
            pendingComptrollerImplementation
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice 接受审计员的新实现。 msg.sender 必须是 pendingImplementation
     * @dev 新实现的管理功能接受它作为实现的角色
     */
    //  * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
    function _acceptImplementation() public returns (uint) {
        // Check caller is pendingImplementation and pendingImplementation ≠ address(0)
        if (
            msg.sender != pendingComptrollerImplementation ||
            pendingComptrollerImplementation == address(0)
        ) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.ACCEPT_PENDING_IMPLEMENTATION_ADDRESS_CHECK
                );
        }

        // Save current values for inclusion in log
        address oldImplementation = comptrollerImplementation;
        address oldPendingImplementation = pendingComptrollerImplementation;

        comptrollerImplementation = pendingComptrollerImplementation;

        pendingComptrollerImplementation = address(0);

        emit NewImplementation(oldImplementation, comptrollerImplementation);
        emit NewPendingImplementation(
            oldPendingImplementation,
            pendingComptrollerImplementation
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice 开始转移管理员权限。 newPendingAdmin 必须调用 `_acceptAdmin` 来完成传输。
     * @dev 管理员功能开始更改管理员。 newPendingAdmin 必须调用 `_acceptAdmin` 来完成传输。
     * @param newPendingAdmin 新的待处理管理员。
     */
    //  * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
    // 转移管理员权限
    function _setPendingAdmin(address newPendingAdmin) public returns (uint) {
        // Check caller = admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PENDING_ADMIN_OWNER_CHECK
                );
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice 接受管理员权限的转移。 msg.sender 必须是 pendingAdmin
     * @dev 管理员功能，用于待定管理员接受角色并更新管理员
     */
    //  * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
    // 接收管理员权限
    function _acceptAdmin() public returns (uint) {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        if (msg.sender != pendingAdmin || msg.sender == address(0)) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.ACCEPT_ADMIN_PENDING_ADMIN_CHECK
                );
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
     * @dev 将执行委托给实现合同。
     * 无论实现返回什么，它都会返回给外部调用者
     * 或转发还原。
     */
    function() external payable {
        // delegate all other functions to current implementation
        (bool success, ) = comptrollerImplementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize)

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize)
            }
            default {
                return(free_mem_ptr, returndatasize)
            }
        }
    }
}
