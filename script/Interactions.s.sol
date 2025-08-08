// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript, console2} from "./shared/BaseScript.s.sol";
import {CommitReveal2} from "./../src/CommitReveal2.sol";
import {ConsumerExample} from "./../src/ConsumerExample.sol";

contract OperatorsActivateAndDeposit is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        for (uint256 i; i < s_numOfOperators; i++) {
            if (block.chainid == 31337) {
                vm.startBroadcast(0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897);
                (bool success,) = s_operators[i].call{value: 1000 ether}("");
                vm.stopBroadcast();
                require(success, "Failed to send Ether");
            } //vm.deal(s_operators[i], 10000 ether);

            console2.log("operator ", i);
            console2.log("operator address", s_operators[i]);
            console2.log("balance %e", s_operators[i].balance);
            uint256 depositAmount = s_commitReveal2.s_depositAmount(s_operators[i]);

            uint256 requiredDeposit = s_activationThreshold - depositAmount;
            require(s_operators[i].balance >= requiredDeposit, "Insufficient balance");
            if (depositAmount < s_activationThreshold) {
                console2.log("depositing %e...", requiredDeposit);
                vm.startBroadcast(s_privateKeysForRealNetwork[i]);
                s_commitReveal2.depositAndActivate{value: requiredDeposit}();
                vm.stopBroadcast();
                console2.log("Deposit and activate successful");
                console2.log("----");
            }
        }
    }
}

contract FundMyAccounts is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        for (uint256 i; i < s_numOfOperators; i++) {
            vm.startBroadcast(0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897);
            (bool success,) = s_operators[i].call{value: 1000 ether}("");
            require(success, "Failed to send Ether");
            vm.stopBroadcast();
        }
    }
}

contract AnvilActivateAndDeposit is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        vm.startBroadcast(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d);
        s_commitReveal2.depositAndActivate{value: s_activationThreshold}();
        vm.stopBroadcast();
        vm.startBroadcast(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a);
        s_commitReveal2.depositAndActivate{value: s_activationThreshold}();
        vm.stopBroadcast();
        vm.startBroadcast(0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6);
        s_commitReveal2.depositAndActivate{value: s_activationThreshold}();
        vm.stopBroadcast();
        console2.log("Deposit and activate successful");
        console2.log("----");
    }
}

contract Withdraw is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        s_commitReveal2 = CommitReveal2(address(0xA87c2DE14Fc3F91e9E53854f3707b5e86cF7C3F7));
        vm.startBroadcast();
        s_commitReveal2.withdraw();
        vm.stopBroadcast();
        for (uint256 i; i < s_numOfOperators; i++) {
            vm.startBroadcast(s_privateKeysForRealNetwork[i]);
            s_commitReveal2.withdraw();
            vm.stopBroadcast();
        }
    }
}

contract RequestRandomNumber is BaseScript {
    function run(address consumer) public {
        if (consumer != address(0)) {
            s_consumerExample = ConsumerExample(payable(consumer));
            s_commitReveal2 = CommitReveal2(s_consumerExample.getCommitReveal2Address());
        } else {
            BaseScript.anvilSetUp();
        }
        console2.log("commitReveal2", address(s_commitReveal2));
        console2.log("consumerExample", address(s_consumerExample));
        uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        console2.log("current gas fee:", tx.gasprice);
        console2.log("requestFee %e", requestFee);

        vm.startBroadcast();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        vm.stopBroadcast();
    }
}

contract SuccessfulPaths is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        // * a. 1 -> 2 -> 12
        uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        console2.log("current gas fee:", tx.gasprice);
        console2.log("requestFee %e", requestFee);

        vm.startBroadcast();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        vm.stopBroadcast();

        // ** Off-chain: Cvi Submission
        // ** //////////////////////////////////////////////// **
        BaseScript.generateSCoCv();

        // ** 2. submitMerkleRoot()
        // ** //////////////////////////////////////////////// **
        bytes32 merkleRoot = _createMerkleRoot(s_cvs);
        vm.startBroadcast();
        s_commitReveal2.submitMerkleRoot(merkleRoot);
        vm.stopBroadcast();
    }

    function submitMerkleRoot() public {
        BaseScript.scriptSetUp();
        // ** Off-chain: Cvi Submission
        // ** //////////////////////////////////////////////// **
        BaseScript.generateSCoCv();

        // ** 2. submitMerkleRoot()
        // ** //////////////////////////////////////////////// **
        bytes32 merkleRoot = _createMerkleRoot(s_cvs);
        console2.log("merkleRoot");
        console2.logBytes32(merkleRoot);
        vm.startBroadcast();
        s_commitReveal2.submitMerkleRoot(merkleRoot);
        vm.stopBroadcast();
    }

    function generateRandomNumber() public {
        BaseScript.scriptSetUp();
        BaseScript.generateSCoCv();
        // uint256[] memory diffs = new uint256[](s_operators.length);
        // uint256[] memory revealOrders = new uint256[](s_operators.length);
        // s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        // for (uint256 i; i < s_operators.length; i++) {
        //     diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
        //     revealOrders[i] = i;
        // }
        // Sort.sort(diffs, revealOrders);
        // ** 12. generateRandomNumber();
        // ** //////////////////////////////////////////////// **
        vm.startBroadcast();
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        vm.stopBroadcast();
        console2.log("random number generated successfully");
    }
}

contract ETCFunctions is BaseScript {
    function run() public {
        BaseScript.scriptSetUp();
        uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        console2.log("current gas fee:", tx.gasprice);
        console2.log("requestFee %e", requestFee);
    }
}
