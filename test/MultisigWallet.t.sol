// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {MultisigWallet} from "../src/governance/MultisigWallet.sol";
import {CommitReveal2L2} from "../src/CommitReveal2L2.sol";
import {ICommitReveal2Governance, ICommitReveal2L2Governance} from "../src/governance/ICommitReveal2Governance.sol";

contract MultisigWalletTest is Test {
    MultisigWallet public multisigWallet;
    CommitReveal2L2 public commitReveal2L2;
    
    address[] public owners;
    uint256 public constant REQUIRED_CONFIRMATIONS = 3;
    uint256 public constant MIN_DELAY = 48 hours;
    
    address public owner1 = makeAddr("owner1");
    address public owner2 = makeAddr("owner2"); 
    address public owner3 = makeAddr("owner3");
    address public owner4 = makeAddr("owner4");
    address public owner5 = makeAddr("owner5");
    address public nonOwner = makeAddr("nonOwner");
    
    uint256 public constant INITIAL_ACTIVATION_THRESHOLD = 1 ether;
    uint256 public constant INITIAL_FLAT_FEE = 0.01 ether;
    
    function setUp() public {
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);
        owners.push(owner4);
        owners.push(owner5);
        
        multisigWallet = new MultisigWallet(owners, REQUIRED_CONFIRMATIONS, MIN_DELAY);
        
        vm.deal(address(this), 5 ether);
        commitReveal2L2 = new CommitReveal2L2{value: 2 ether}(
            INITIAL_ACTIVATION_THRESHOLD,
            INITIAL_FLAT_FEE,
            "CommitReveal2",
            "1.0.0",
            300,
            60,
            300,
            30,
            30,
            1000 gwei,
            address(multisigWallet.timelock())
        );
    }
    
    function testMultisigWalletSetup() public {
        assertEq(multisigWallet.requiredConfirmations(), REQUIRED_CONFIRMATIONS);
        
        address[] memory walletOwners = multisigWallet.getOwners();
        assertEq(walletOwners.length, 5);
        assertTrue(multisigWallet.isOwner(owner1));
        assertTrue(multisigWallet.isOwner(owner5));
        assertFalse(multisigWallet.isOwner(nonOwner));
    }
    
    function testCompleteMultisigFlow() public {
        uint256 newActivationThreshold = 2 ether;
        uint256 newFlatFee = 0.02 ether;
        
        bytes memory callData = abi.encodeWithSelector(
            ICommitReveal2Governance.setEconomicParameters.selector,
            newActivationThreshold,
            newFlatFee
        );
        
        // Step 1: Owner1 submits transaction
        vm.prank(owner1);
        uint256 txId = multisigWallet.submitTransaction(
            address(commitReveal2L2),
            0,
            callData,
            bytes32(0),
            keccak256("economic-params-update"),
            MIN_DELAY
        );
        
        // Check transaction was created and owner1 auto-confirmed
        assertEq(multisigWallet.getConfirmationCount(txId), 1);
        assertTrue(multisigWallet.isConfirmed(txId, owner1));
        
        // Step 2: Owner2 confirms
        vm.prank(owner2);
        multisigWallet.confirmTransaction(txId);
        assertEq(multisigWallet.getConfirmationCount(txId), 2);
        
        // Step 3: Owner3 confirms (reaches required confirmations)
        vm.prank(owner3);
        multisigWallet.confirmTransaction(txId);
        assertEq(multisigWallet.getConfirmationCount(txId), 3);
        
        // Step 4: Schedule transaction in timelock
        vm.prank(owner1);
        multisigWallet.scheduleTransaction(txId);
        
        // Should fail if executed before delay
        vm.prank(owner1);
        vm.expectRevert();
        multisigWallet.executeTransaction(txId);
        
        // Step 5: Wait for timelock delay
        vm.warp(block.timestamp + MIN_DELAY + 1);
        
        // Step 6: Execute transaction
        vm.prank(owner1);
        multisigWallet.executeTransaction(txId);
        
        // Verify the parameters were changed
        assertEq(commitReveal2L2.s_activationThreshold(), newActivationThreshold);
        assertEq(commitReveal2L2.s_flatFee(), newFlatFee);
    }
    
    function testInsufficientConfirmations() public {
        bytes memory callData = abi.encodeWithSelector(
            ICommitReveal2Governance.setEconomicParameters.selector,
            2 ether,
            0.02 ether
        );
        
        vm.prank(owner1);
        uint256 txId = multisigWallet.submitTransaction(
            address(commitReveal2L2),
            0,
            callData,
            bytes32(0),
            keccak256("insufficient-test"),
            MIN_DELAY
        );
        
        // Only 1 confirmation (from submitter)
        assertEq(multisigWallet.getConfirmationCount(txId), 1);
        
        // Should fail to schedule with insufficient confirmations
        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.InsufficientConfirmations.selector);
        multisigWallet.scheduleTransaction(txId);
        
        // Add second confirmation
        vm.prank(owner2);
        multisigWallet.confirmTransaction(txId);
        
        // Still insufficient (need 3)
        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.InsufficientConfirmations.selector);
        multisigWallet.scheduleTransaction(txId);
    }
    
    function testRevokeConfirmation() public {
        bytes memory callData = abi.encodeWithSelector(
            ICommitReveal2Governance.setEconomicParameters.selector,
            2 ether,
            0.02 ether
        );
        
        vm.prank(owner1);
        uint256 txId = multisigWallet.submitTransaction(
            address(commitReveal2L2),
            0,
            callData,
            bytes32(0),
            keccak256("revoke-test"),
            MIN_DELAY
        );
        
        vm.prank(owner2);
        multisigWallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        multisigWallet.confirmTransaction(txId);
        
        assertEq(multisigWallet.getConfirmationCount(txId), 3);
        
        // Owner2 revokes confirmation
        vm.prank(owner2);
        multisigWallet.revokeConfirmation(txId);
        
        assertEq(multisigWallet.getConfirmationCount(txId), 2);
        assertFalse(multisigWallet.isConfirmed(txId, owner2));
        
        // Should fail to schedule with insufficient confirmations
        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.InsufficientConfirmations.selector);
        multisigWallet.scheduleTransaction(txId);
    }
    
    function testNonOwnerCannotSubmit() public {
        bytes memory callData = abi.encodeWithSelector(
            ICommitReveal2Governance.setEconomicParameters.selector,
            2 ether,
            0.02 ether
        );
        
        vm.prank(nonOwner);
        vm.expectRevert(MultisigWallet.NotOwner.selector);
        multisigWallet.submitTransaction(
            address(commitReveal2L2),
            0,
            callData,
            bytes32(0),
            keccak256("unauthorized-test"),
            MIN_DELAY
        );
    }
    
    function testNonOwnerCannotConfirm() public {
        bytes memory callData = abi.encodeWithSelector(
            ICommitReveal2Governance.setEconomicParameters.selector,
            2 ether,
            0.02 ether
        );
        
        vm.prank(owner1);
        uint256 txId = multisigWallet.submitTransaction(
            address(commitReveal2L2),
            0,
            callData,
            bytes32(0),
            keccak256("confirm-test"),
            MIN_DELAY
        );
        
        vm.prank(nonOwner);
        vm.expectRevert(MultisigWallet.NotOwner.selector);
        multisigWallet.confirmTransaction(txId);
    }
    
    function testL1FeeCoefficientGovernance() public {
        uint8 newCoefficient = 75;
        
        bytes memory callData = abi.encodeWithSelector(
            ICommitReveal2L2Governance.setL1FeeCoefficient.selector,
            newCoefficient
        );
        
        // Complete multisig flow
        vm.prank(owner1);
        uint256 txId = multisigWallet.submitTransaction(
            address(commitReveal2L2),
            0,
            callData,
            bytes32(0),
            keccak256("l1-fee-test"),
            MIN_DELAY
        );
        
        vm.prank(owner2);
        multisigWallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        multisigWallet.confirmTransaction(txId);
        
        vm.prank(owner1);
        multisigWallet.scheduleTransaction(txId);
        
        vm.warp(block.timestamp + MIN_DELAY + 1);
        
        vm.prank(owner1);
        multisigWallet.executeTransaction(txId);
        
        assertEq(commitReveal2L2.s_l1FeeCoefficient(), newCoefficient);
    }
    
    function testDirectCallsToGovernanceFunctionsFail() public {
        // Should fail when called directly (not through multisig timelock)
        vm.prank(owner1);
        vm.expectRevert();
        commitReveal2L2.setEconomicParameters(2 ether, 0.02 ether);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        commitReveal2L2.setL1FeeCoefficient(75);
    }
}