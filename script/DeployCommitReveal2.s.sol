// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CommitReveal2} from "../src/CommitReveal2.sol";
import {CommitReveal2L1} from "../src/test/CommitReveal2L1.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";
import {CommitReveal2Helper} from "./../test/shared/CommitReveal2Helper.sol";

contract DeployCommitReveal2 is Script, CommitReveal2Helper {
    function run()
        public
        returns (address commitReveal2, NetworkHelperConfig networkHelperConfig)
    {
        networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig
            memory activeNetworkConfig = networkHelperConfig
                .getActiveNetworkConfig();
        uint256[11] memory phaseStartOffsets;
        phaseStartOffsets = _getEachPhaseStartOffset(
            activeNetworkConfig.phaseDuration
        );
        vm.startBroadcast(activeNetworkConfig.deployer);
        if (block.chainid == 31337) {
            commitReveal2 = address(
                new CommitReveal2L1(
                    activeNetworkConfig.activationThreshold,
                    activeNetworkConfig.flatFee,
                    activeNetworkConfig.maxActivatedOperators,
                    activeNetworkConfig.name,
                    activeNetworkConfig.version,
                    phaseStartOffsets[1],
                    phaseStartOffsets[2],
                    phaseStartOffsets[3],
                    phaseStartOffsets[4],
                    phaseStartOffsets[5],
                    phaseStartOffsets[6],
                    phaseStartOffsets[7],
                    phaseStartOffsets[8],
                    phaseStartOffsets[9],
                    phaseStartOffsets[10]
                )
            );
        } else {
            commitReveal2 = address(
                new CommitReveal2(
                    activeNetworkConfig.activationThreshold,
                    activeNetworkConfig.flatFee,
                    activeNetworkConfig.maxActivatedOperators,
                    activeNetworkConfig.name,
                    activeNetworkConfig.version,
                    phaseStartOffsets[1],
                    phaseStartOffsets[2],
                    phaseStartOffsets[3],
                    phaseStartOffsets[4],
                    phaseStartOffsets[5],
                    phaseStartOffsets[6],
                    phaseStartOffsets[7],
                    phaseStartOffsets[8],
                    phaseStartOffsets[9],
                    phaseStartOffsets[10]
                )
            );
        }
        vm.stopBroadcast();
    }
}
