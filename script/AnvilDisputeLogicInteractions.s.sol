// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript, console2} from "./shared/BaseScript.s.sol";
import {CommitReveal2} from "./../src/CommitReveal2.sol";

contract FailToRequestSubmitCvOrSubmitMerkleRoot is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        if (block.chainid == 31337) {
            vm.warp(block.timestamp + 50);
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

contract RequestToSubmitCo is BaseScript {
    uint256[] public s_requestToSubmitCoIndices;

    function run() public {
        BaseScript.scriptSetUp();
        BaseScript.generateSCoCv();
        s_requestToSubmitCoIndices = [0, 2];
        _setParametersForRequestToSubmitCo(s_requestToSubmitCoIndices);
        console2.log("s_indicesFirstCvNotOnChainRestCvOnChain", s_indicesFirstCvNotOnChainRestCvOnChain);
        vm.startBroadcast(s_activeNetworkConfig.deployer);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        vm.stopBroadcast();
    }
}

contract RequestToSubmitS is BaseScript {
    uint256 public indexK;

    function run() public {
        BaseScript.scriptSetUp();
        uint256[] memory revealOrders = BaseScript.generateSCoCv();
        indexK = 2;
        _setParametersForRequestToSubmitS(indexK, revealOrders);
        vm.startBroadcast(s_activeNetworkConfig.deployer);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        vm.stopBroadcast();
    }
}

contract SubmitCv is BaseScript {
    function run(uint256 index) public {
        BaseScript.scriptSetUp();
        BaseScript.generateSCoCv();
        console2.log("regular node address:", s_operators[index]);
        console2.log("C_vi :");
        console2.logBytes32(s_cvs[index]);
        vm.startBroadcast(s_privateKeysForRealNetwork[index]);
        s_commitReveal2.submitCv(s_cvs[index]);
        vm.stopBroadcast();
    }
}

contract SubmitCo is BaseScript {
    function run(uint256 index) public {
        BaseScript.scriptSetUp();
        BaseScript.generateSCoCv();
        console2.log("regular node address:", s_operators[index]);
        console2.log("C_oi :");
        console2.logBytes32(s_cos[index]);
        vm.startBroadcast(s_privateKeysForRealNetwork[index]);
        s_commitReveal2.submitCo(s_cos[index]);
        vm.stopBroadcast();
    }
}

contract SubmitS is BaseScript {
    function run(uint256 index) public {
        BaseScript.scriptSetUp();
        BaseScript.generateSCoCv();
        console2.log("regular node address:", s_operators[index]);
        console2.log("S :");
        console2.logBytes32(s_secrets[index]);
        vm.startBroadcast(s_privateKeysForRealNetwork[index]);
        s_commitReveal2.submitS(s_secrets[index]);
        vm.stopBroadcast();
    }
}

contract GenerateRandomNumberWhenSomeCvsAreOnChain is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        BaseScript.generateSCoCv();
        _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain();
        vm.startBroadcast(s_activeNetworkConfig.deployer);
        s_commitReveal2.generateRandomNumberWhenSomeCvsAreOnChain(
            s_secrets, s_sigRSsForAllCvsNotOnChain, s_packedVsForAllCvsNotOnChain, s_packedRevealOrders
        );
        vm.stopBroadcast();
    }
}

contract FailToRequestSorGenerateRandomNumber is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        vm.startBroadcast();
        s_commitReveal2.failToRequestSorGenerateRandomNumber();
        vm.stopBroadcast();
    }
}

contract FailToSubmitMerkleRootAfterDispute is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        vm.startBroadcast();
        s_commitReveal2.failToSubmitMerkleRootAfterDispute();
        vm.stopBroadcast();
    }
}

contract FailToSubmitS is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        vm.startBroadcast();
        s_commitReveal2.failToSubmitS();
        vm.stopBroadcast();
    }
}
