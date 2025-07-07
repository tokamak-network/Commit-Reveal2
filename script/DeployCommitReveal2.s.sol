// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {CommitReveal2} from "../src/CommitReveal2.sol";
import {CommitReveal2L1} from "../src/CommitReveal2L1.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";
import {CommitReveal2Helper} from "./../test/shared/CommitReveal2Helper.sol";
import {DeployMockGasPriceOracle} from "./../test/shared/DeployMockGasPriceOracle.sol";

contract DeployCommitReveal2 is Script, CommitReveal2Helper {
    function run() public returns (address commitReveal2, NetworkHelperConfig networkHelperConfig) {
        networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig memory activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();

        vm.startBroadcast(activeNetworkConfig.deployer);
        if (block.chainid == 31337 || block.chainid == 11155111) {
            commitReveal2 = address(
                new CommitReveal2L1{value: activeNetworkConfig.activationThreshold}(
                    activeNetworkConfig.activationThreshold,
                    activeNetworkConfig.flatFee,
                    activeNetworkConfig.name,
                    activeNetworkConfig.version,
                    activeNetworkConfig.offChainSubmissionPeriod,
                    activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
                    activeNetworkConfig.onChainSubmissionPeriod,
                    activeNetworkConfig.offChainSubmissionPeriodPerOperator,
                    activeNetworkConfig.onChainSubmissionPeriodPerOperator
                )
            );
        } else {
            commitReveal2 = address(
                new CommitReveal2{value: activeNetworkConfig.activationThreshold}(
                    activeNetworkConfig.activationThreshold,
                    activeNetworkConfig.flatFee,
                    activeNetworkConfig.name,
                    activeNetworkConfig.version,
                    activeNetworkConfig.offChainSubmissionPeriod,
                    activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
                    activeNetworkConfig.onChainSubmissionPeriod,
                    activeNetworkConfig.offChainSubmissionPeriodPerOperator,
                    activeNetworkConfig.onChainSubmissionPeriodPerOperator
                )
            );
        }
        vm.stopBroadcast();
    }

    function runForTest() public returns (address commitReveal2, NetworkHelperConfig networkHelperConfig) {
        networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig memory activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();

        vm.startBroadcast(activeNetworkConfig.deployer);
        commitReveal2 = address(
            new CommitReveal2{value: activeNetworkConfig.activationThreshold}(
                activeNetworkConfig.activationThreshold,
                activeNetworkConfig.flatFee,
                activeNetworkConfig.name,
                activeNetworkConfig.version,
                activeNetworkConfig.offChainSubmissionPeriod,
                activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
                activeNetworkConfig.onChainSubmissionPeriod,
                activeNetworkConfig.offChainSubmissionPeriodPerOperator,
                activeNetworkConfig.onChainSubmissionPeriodPerOperator
            )
        );
        DeployMockGasPriceOracle mockGasPriceOracle = new DeployMockGasPriceOracle();
        mockGasPriceOracle.deployMockGasPriceOracle();
        vm.stopBroadcast();
    }
}
