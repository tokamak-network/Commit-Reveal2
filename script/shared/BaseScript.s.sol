// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sort} from "../../test/shared/Sort.sol";

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Script, console2} from "forge-std/Script.sol";
import {CommitReveal2Helper, CommitReveal2Storage} from "./../../test/shared/CommitReveal2Helper.sol";
import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {NetworkHelperConfig} from "./../NetworkHelperConfig.s.sol";

contract BaseScript is Script, CommitReveal2Helper {
    uint256[3] public s_privateKeysForRealNetwork;
    address[3] public s_operators;
    uint256 s_activationThreshold;
    mapping(address => uint256) s_privateKeysForAnvil;

    function anvilSetUp() public {
        // *** Get the most recent deployment of CommitReveal2 ***
        // ** //////////////////////////////////////////////// **
        string memory contractName =
            (block.chainid == 31337 || block.chainid == 11155111) ? "CommitReveal2L1" : "CommitReveal2";
        s_commitReveal2 = CommitReveal2(DevOpsTools.get_most_recent_deployment(contractName, block.chainid));

        // *** Get most recent deployment of ConsumerExample **
        // ** //////////////////////////////////////////////// **
        s_consumerExample =
            ConsumerExample(payable(DevOpsTools.get_most_recent_deployment("ConsumerExampleV2", block.chainid)));
    }

    function scriptSetUp() public {
        s_numOfOperators = 3;
        // *** Get the most recent deployment of CommitReveal2 ***
        // ** //////////////////////////////////////////////// **
        string memory contractName =
            (block.chainid == 31337 || block.chainid == 11155111) ? "CommitReveal2L1" : "CommitReveal2";
        s_commitReveal2 = CommitReveal2(DevOpsTools.get_most_recent_deployment(contractName, block.chainid));
        console2.log("commitReveal2", address(s_commitReveal2));

        // *** Get most recent deployment of ConsumerExample **
        // ** //////////////////////////////////////////////// **
        s_consumerExample =
            ConsumerExample(payable(DevOpsTools.get_most_recent_deployment("ConsumerExampleV2", block.chainid)));
        console2.log("ConsumerExampleV2", address(s_consumerExample));

        // *** Get accounts ***
        // ** //////////////////////////////////////////////// **
        string[3] memory keys = ["PRIVATE_KEY2", "PRIVATE_KEY3", "PRIVATE_KEY4"];
        s_privateKeysForRealNetwork =
            [uint256(vm.envBytes32(keys[0])), uint256(vm.envBytes32(keys[1])), uint256(vm.envBytes32(keys[2]))];
        s_operators = [
            vm.addr(s_privateKeysForRealNetwork[0]),
            vm.addr(s_privateKeysForRealNetwork[1]),
            vm.addr(s_privateKeysForRealNetwork[2])
        ];
        s_privateKeysForAnvil[s_operators[0]] = s_privateKeysForRealNetwork[0];
        s_privateKeysForAnvil[s_operators[1]] = s_privateKeysForRealNetwork[1];
        s_privateKeysForAnvil[s_operators[2]] = s_privateKeysForRealNetwork[2];
        s_activationThreshold = s_commitReveal2.s_activationThreshold();
        console2.log("activationThreshold %e", s_activationThreshold);

        // *** Set CommitReveal2Helper states
        // ** //////////////////////////////////////////////// **
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        s_activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();
    }

    function generateSCoCv() public returns (uint256[] memory revealOrders) {
        revealOrders = _setSCoCvRevealOrders(s_privateKeysForAnvil);
    }
}
