// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ConsumerExample} from "../src/ConsumerExample.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";

contract DeployConsumerExample is Script {
    error CommitReveal2NotDeployed();

    function deployUsingDevOpsTools()
        public
        returns (ConsumerExample consumer)
    {
        address commitReveal2 = DevOpsTools.get_most_recent_deployment(
            "CommitReveal2",
            block.chainid
        );
        if (commitReveal2 == address(0)) revert CommitReveal2NotDeployed();
        consumer = deployConsumerExampleUsingConfig(commitReveal2);
    }

    function deployConsumerExampleUsingConfig(
        address commitReveal2
    ) public returns (ConsumerExample consumer) {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig
            memory activeNetworkConfig = networkHelperConfig
                .getActiveNetworkConfig();
        vm.startBroadcast(activeNetworkConfig.deployer);
        consumer = new ConsumerExample(commitReveal2);
        vm.stopBroadcast();
    }

    function run() public returns (ConsumerExample consumer) {
        vm.startBroadcast();
        consumer = deployUsingDevOpsTools();
        vm.stopBroadcast();
    }
}
