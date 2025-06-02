// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseScript, console2} from "./shared/BaseScript.s.sol";
import {CommitReveal2} from "./../src/CommitReveal2.sol";

contract FailToRequestSubmitCvOrSubmitMerkleRoot is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        if (block.chainid == 31337) {
            vm.warp(block.timestamp + 40);
            vm.roll(block.number + 1);
        }
        vm.startBroadcast();
        s_commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot();
        vm.stopBroadcast();
    }
}

contract Resume is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        vm.startBroadcast(s_activeNetworkConfig.deployer);
        s_commitReveal2.resume{value: s_activationThreshold}();
        vm.stopBroadcast();
    }
}

contract RequestToSubmitCv is BaseScript {
    uint256[] public s_requestToSubmitCvIndices;

    function run() public {
        BaseScript.scriptSetUp();
        s_requestToSubmitCvIndices = [1, 2];
        uint256 packedIndices;
        for (uint256 i; i < s_requestToSubmitCvIndices.length; i++) {
            packedIndices = packedIndices | (s_requestToSubmitCvIndices[i] << (i * 8));
        }
        vm.startBroadcast(s_activeNetworkConfig.deployer);
        s_commitReveal2.requestToSubmitCv(packedIndices);
        vm.stopBroadcast();
    }
}
