// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseScript, console2} from "./shared/BaseScript.s.sol";
import {CommitReveal2} from "./../src/CommitReveal2.sol";

contract FailToRequestSubmitCvOrSubmitMerkleRoot is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        vm.startBroadcast();
        s_commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot();
        vm.stopBroadcast();
    }
}
