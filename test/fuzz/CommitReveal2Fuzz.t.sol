// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CreateMerkleRootSolidity, CreateMerkleRootInlineAssembly} from "./../shared/CommitReveal2Test.sol";

import {NetworkHelperConfig} from "./../../script/NetworkHelperConfig.s.sol";
import {Test, console2} from "forge-std/Test.sol";

contract CommitReveal2Fuzz is Test {
    CreateMerkleRootSolidity createMerkleRootSolidity;
    CreateMerkleRootInlineAssembly createMerkleRootInlineAssembly;

    function setUp() public {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig memory activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();
        vm.deal(address(this), 10000 ether);

        createMerkleRootSolidity = new CreateMerkleRootSolidity{value: activeNetworkConfig.activationThreshold}(
            activeNetworkConfig.activationThreshold,
            activeNetworkConfig.flatFee,
            activeNetworkConfig.maxActivatedOperators,
            activeNetworkConfig.name,
            activeNetworkConfig.version,
            activeNetworkConfig.offChainSubmissionPeriod,
            activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
            activeNetworkConfig.onChainSubmissionPeriod,
            activeNetworkConfig.offChainSubmissionPeriodPerOperator,
            activeNetworkConfig.onChainSubmissionPeriodPerOperator
        );

        createMerkleRootInlineAssembly = new CreateMerkleRootInlineAssembly{
            value: activeNetworkConfig.activationThreshold
        }(
            activeNetworkConfig.activationThreshold,
            activeNetworkConfig.flatFee,
            activeNetworkConfig.maxActivatedOperators,
            activeNetworkConfig.name,
            activeNetworkConfig.version,
            activeNetworkConfig.offChainSubmissionPeriod,
            activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
            activeNetworkConfig.onChainSubmissionPeriod,
            activeNetworkConfig.offChainSubmissionPeriodPerOperator,
            activeNetworkConfig.onChainSubmissionPeriodPerOperator
        );
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
