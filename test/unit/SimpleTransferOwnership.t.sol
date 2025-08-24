// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OperatorManager} from "src/OperatorManager.sol";

contract SimpleTransferOwnership is Test {
    OperatorManager private s_operatorManager;

    // Custom error selectors used by OperatorManager and Solady Ownable
    bytes4 private constant NEW_OWNER_CANNOT_BE_ACTIVATED_OPERATOR = 0x9279dd8e;
    bytes4 private constant NEW_OWNER_IS_ZERO_ADDRESS = 0x7448fbae;
    bytes4 private constant PENDING_OWNER_CANNOT_BE_ACTIVATED_OPERATOR = 0x5df6bf29;

    function setUp() public {
        s_operatorManager = new OperatorManager();
    }

    function test_transferOwnership_succeeds_forNonActivatedNonZero() public {
        address newOwner = address(0x1234);
        s_operatorManager.transferOwnership(newOwner);
        assertEq(s_operatorManager.owner(), newOwner, "owner not updated");
    }

    function test_transferOwnership_reverts_forZeroAddress() public {
        vm.expectRevert(NEW_OWNER_IS_ZERO_ADDRESS);
        s_operatorManager.transferOwnership(address(0));
    }

    function test_transferOwnership_reverts_forActivatedOperator() public {
        address operator = address(0xBEEF);
        vm.prank(operator);
        s_operatorManager.activate();

        vm.expectRevert(NEW_OWNER_CANNOT_BE_ACTIVATED_OPERATOR);
        s_operatorManager.transferOwnership(operator);
    }

    function test_requestAndCompleteOwnershipHandover_succeeds() public {
        address pendingOwner = address(0xABCD);

        // pending owner requests handover
        vm.prank(pendingOwner);
        s_operatorManager.requestOwnershipHandover();

        // current owner completes handover
        address currentOwner = s_operatorManager.owner();
        vm.prank(currentOwner);
        s_operatorManager.completeOwnershipHandover(pendingOwner);

        assertEq(s_operatorManager.owner(), pendingOwner, "handover did not transfer ownership");
    }

    function test_requestOwnershipHandover_reverts_whenCallerIsActivatedOperator() public {
        address operator = address(0xC0FFEE);
        vm.prank(operator);
        s_operatorManager.activate();

        vm.prank(operator);
        vm.expectRevert(NEW_OWNER_CANNOT_BE_ACTIVATED_OPERATOR);
        s_operatorManager.requestOwnershipHandover();
    }

    function test_completeOwnershipHandover_reverts_whenPendingOwnerIsActivatedOperator() public {
        address operator = address(0xDEAD);
        vm.prank(operator);
        s_operatorManager.activate();

        vm.expectRevert(PENDING_OWNER_CANNOT_BE_ACTIVATED_OPERATOR);
        s_operatorManager.completeOwnershipHandover(operator);
    }
}
