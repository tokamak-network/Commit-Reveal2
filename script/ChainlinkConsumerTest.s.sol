// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ConsumerExampleChainlink} from "../src/chainlinkVrfTest/ConsumerExampleChainlink.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract DeployChainlinkConsumer is Script {
    address opSepoliaWrapper = address(0xA8A278BF534BCa72eFd6e6C9ac573E98c21A6171);
    address sepoliaWrapper = address(0x195f15F2d49d693cE265b4fB0fdDbE15b1850Cc1);
    address mainnetWrapper = address(0x02aae1A04f9828517b3007f83f6181900CaD910c);

    function run() public returns (address consumer) {
        address wrapper;
        if (block.chainid == 11155111) wrapper = sepoliaWrapper;
        else if (block.chainid == 11155420) wrapper = opSepoliaWrapper;
        else if (block.chainid == 1) wrapper = mainnetWrapper;
        else revert("Unsupported chainid");
        vm.startBroadcast();
        consumer = address(new ConsumerExampleChainlink(wrapper));
        vm.stopBroadcast();
    }
}

contract RequestRandomNumber is Script {
    function run() public {
        ConsumerExampleChainlink consumer =
            ConsumerExampleChainlink(DevOpsTools.get_most_recent_deployment("ConsumerExampleChainlink", block.chainid));
        vm.startBroadcast();
        consumer.requestRandomNumber{value: 0.1 ether}();
        vm.stopBroadcast();
    }
}
