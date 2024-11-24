// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {CommitReveal2} from "../src/CommitReveal2.sol";
import {console2} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";

contract DeployCommitReveal2 is Script {
    uint256 s_maxActivatedOperators = 10;
    string public name = "Tokamak DRB";
    string public version = "1";
    bytes32 public nameHash = keccak256(bytes(name));
    bytes32 public versionHash = keccak256(bytes(version));

    function deployCommitReveal2UsingConfig()
        public
        returns (CommitReveal2 commitReveal2)
    {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        (
            uint256 activationThreshold,
            ,
            uint256 flatFee,
            uint256 l1GasCostMode,
            ,
            ,

        ) = networkHelperConfig.activeNetworkConfig();
        console2.log("activationThreshold:", activationThreshold);
        commitReveal2 = deployCommitReveal2(
            activationThreshold,
            flatFee,
            l1GasCostMode
        );
    }

    function deployCommitReveal2(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 l1GasCostMode
    ) public returns (CommitReveal2 commitReveal2) {
        vm.startBroadcast();
        commitReveal2 = new CommitReveal2(
            activationThreshold,
            flatFee,
            s_maxActivatedOperators,
            name,
            version
        );
        vm.stopBroadcast();
        (uint8 mode, ) = commitReveal2.getL1FeeCalculationMode();
        if (uint256(mode) != l1GasCostMode) {
            vm.startBroadcast();
            commitReveal2.setL1FeeCalculation(uint8(l1GasCostMode), 100);
            vm.stopBroadcast();
            console2.log("Set L1 fee calculation mode to:", l1GasCostMode);
        }
    }

    function run() public returns (CommitReveal2 commitReveal2) {
        commitReveal2 = deployCommitReveal2UsingConfig();
        console2.log("Deployed CommitReveal2 at:", address(commitReveal2));
    }
}
