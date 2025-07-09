// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ConsumerExampleV2} from "../src/ConsumerExampleV2.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";

contract DeployConsumerExampleV2 is Script {
    error CommitReveal2NotDeployed();

    function deployUsingDevOpsTools() public returns (ConsumerExampleV2 consumer) {
        string memory contractName =
            (block.chainid == 31337 || block.chainid == 11155111) ? "CommitReveal2" : "CommitReveal2L2";
        address commitReveal2 = DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
        if (commitReveal2 == address(0)) revert CommitReveal2NotDeployed();
        consumer = deployConsumerExampleV2UsingConfig(commitReveal2);
    }

    function deployConsumerExampleV2UsingConfig(address commitReveal2) public returns (ConsumerExampleV2 consumer) {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig memory activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();
        vm.startBroadcast(activeNetworkConfig.deployer);
        consumer = new ConsumerExampleV2(commitReveal2);
        vm.stopBroadcast();
    }

    function run(address commitReveal2) public returns (ConsumerExampleV2 consumer) {
        if (commitReveal2 != address(0)) {
            consumer = deployConsumerExampleV2UsingConfig(commitReveal2);
        } else {
            consumer = deployUsingDevOpsTools();
        }
    }

    function run() public returns (ConsumerExampleV2 consumer) {
        consumer = deployUsingDevOpsTools();
    }
}
