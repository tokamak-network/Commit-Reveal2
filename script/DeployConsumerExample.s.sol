// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ConsumerExample} from "../src/ConsumerExample.sol";

contract DeployConsumerExample is Script {
    error CommitReveal2NotDeployed();

    function run() public {
        address commitReveal2 = DevOpsTools.get_most_recent_deployment(
            "CommitReveal2L2",
            block.chainid
        );
        vm.startBroadcast();
        ConsumerExample consumer = new ConsumerExample(commitReveal2);
        vm.stopBroadcast();
        console2.log("Deployed ConsumerExample at:", address(consumer));
    }
}
