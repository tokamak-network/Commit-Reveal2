// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CreateMerkleRootSolidity, CreateMerkleRootInlineAssembly} from "./../../src/test/CreateMerkleRoot.sol";
import {Test, console2} from "forge-std/Test.sol";

contract CommitReveal2Fuzz is Test {
    CreateMerkleRootSolidity createMerkleRootSolidity;
    CreateMerkleRootInlineAssembly createMerkleRootInlineAssembly;

    function setUp() public {
        vm.deal(address(this), 10000 ether);
        createMerkleRootSolidity = new CreateMerkleRootSolidity();
        createMerkleRootInlineAssembly = new CreateMerkleRootInlineAssembly();
    }

    function testFuzz_CreateMerkleRoot(bytes32[] memory leaves) public view {
        vm.assume(leaves.length > 1);
        bytes32 rootSolidity = createMerkleRootSolidity.createMR(leaves);
        uint256 gasUsedSolidity = vm.lastCallGas().gasTotalUsed;
        bytes32 rootInlineAssembly = createMerkleRootInlineAssembly.createMR(leaves);
        uint256 gasUsedInlineAssembly = vm.lastCallGas().gasTotalUsed;
        assertGt(gasUsedSolidity, gasUsedInlineAssembly);
        assertEq(rootSolidity, rootInlineAssembly);
    }
}
