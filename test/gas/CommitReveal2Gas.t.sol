// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2, Vm} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./../../script/NetworkHelperConfig.s.sol";
import {Sort} from "./../shared/Sort.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";

contract CommitReveal2Gas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    // *** Gas variables
    uint256[] public s_depositAndActivateGas;
    uint256[] public s_requestRandomNumberGas;
    uint256[] public s_submitMerkleRootGas;
    uint256[] public s_generateRandomNumberGas;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        vm.stopPrank();
        s_numOfTests = 10;
    }

    function _consoleAverageExceptIndex0(uint256[] memory arr, string memory msg1) internal pure {
        uint256 sum;
        uint256 len = arr.length;
        for (uint256 i = 1; i < len; i++) {
            sum += arr[i];
        }
        console2.log(msg1, sum / (len - 1));
    }

    function test_optimisticCaseGas() public {
        for (s_numOfOperators = 2; s_numOfOperators < 10; s_numOfOperators++) {
            // ** Deploy CommitReveal2
            (s_commitReveal2Address, s_networkHelperConfig) = (new DeployCommitReveal2()).run();
            s_commitReveal2 = CommitReveal2(s_commitReveal2Address);
            s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
            s_nameHash = keccak256(bytes(s_activeNetworkConfig.name));
            s_versionHash = keccak256(bytes(s_activeNetworkConfig.version));
            // ** Deploy ConsumerExample
            s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));

            // *** Deposit And Activate Operators
            for (uint256 i; i < s_numOfOperators; i++) {
                vm.startPrank(s_anvilDefaultAddresses[i]);
                s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
                s_depositAndActivateGas.push(vm.lastCallGas().gasTotalUsed);
            }

            s_anyAddress = makeAddr("any");
            vm.deal(s_anyAddress, 10000 ether);

            // ** 1 -> 2 -> 12
            s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);

            vm.startPrank(s_anyAddress);
            for (uint256 i; i < s_numOfTests; i++) {
                s_consumerExample.requestRandomNumber{value: s_requestFee}();
                s_requestRandomNumberGas.push(vm.lastCallGas().gasTotalUsed);

                // ** Off-chain: Cv submission
                uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                // ** 2. submitMerkleRoot()
                vm.startPrank(LEADERNODE);
                mine(1);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas.push(vm.lastCallGas().gasTotalUsed);
                mine(1);

                // ** 12. generateRandomNumber()
                mine(1);
                s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss, revealOrders);
                s_generateRandomNumberGas.push(vm.lastCallGas().gasTotalUsed);
                mine(1);
            }
            console2.log("s_numOfOperators:", s_numOfOperators);
            _consoleAverageExceptIndex0(s_depositAndActivateGas, "depositAndActivateGas:");
            _consoleAverageExceptIndex0(s_requestRandomNumberGas, "requestRandomNumberGas:");
            _consoleAverageExceptIndex0(s_submitMerkleRootGas, "submitMerkleRootGas:");
            _consoleAverageExceptIndex0(s_generateRandomNumberGas, "generateRandomNumberGas:");
            console2.log("--------------------");
            vm.stopPrank();
        }
    }
}
