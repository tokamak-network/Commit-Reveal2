// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./shared/BaseTest.t.sol";
import {CommitReveal2OnChain} from "../src/CommitReveal2OnChain.sol";
import {console2} from "forge-std/Test.sol";
import {QuickSort} from "./shared/QuickSort.sol";
import {Utils} from "./shared/Utils.t.sol";

contract CommitReveal2Test is BaseTest, Utils {
    CommitReveal2OnChain commitReveal2;

    uint256 public s_commitDuration = 120;
    uint256 public s_reveaDuration = 120;

    function setUp() public override {
        BaseTest.setUp(); // Start Prank
        commitReveal2 = new CommitReveal2OnChain(
            s_activationThreshold,
            s_requestFee,
            s_commitDuration,
            s_reveaDuration
        );
        vm.stopPrank();
        for (uint256 i = 0; i < s_maxOperators; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            commitReveal2.deposit{value: s_activationThreshold}();
            vm.stopPrank();
        }
    }

    function mine() public {
        vm.warp(block.timestamp + 121);
        vm.roll(block.number + 10);
    }

    function test_OnChainCommitReveal2() public {
        uint256 requestTestNum = s_requestTestNum;
        console2.log("gasUsed of commmitReveal2OnChain");
        console2.log("---------------------------");
        uint256 i = 0;
        for (
            uint256 numOfOperators = 2;
            numOfOperators <= s_maxOperators;
            numOfOperators++
        ) {
            console2.log("Number of Operators: ", numOfOperators);
            uint256[] memory gasUsedRequest = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedCommit = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedReveal1 = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedReveal2 = new uint256[](requestTestNum - 1);
            for (
                uint256 round = i++ * requestTestNum;
                round < requestTestNum * i;
                round++
            ) {
                // ** Request Random Number
                commitReveal2.requestRandomNumber{value: s_requestFee}();
                if (round % requestTestNum != 0) {
                    gasUsedRequest[(round % requestTestNum) - 1] = vm
                        .lastCallGas()
                        .gasTotalUsed;
                }

                // * Create secretValues, cos, cvs
                bytes32[] memory secretValues = new bytes32[](numOfOperators);
                bytes32[] memory cos = new bytes32[](numOfOperators);
                bytes32[] memory cvs = new bytes32[](numOfOperators);
                for (uint256 j; j < numOfOperators; j++) {
                    secretValues[j] = keccak256(
                        abi.encodePacked(
                            numOfOperators,
                            round,
                            j,
                            block.timestamp
                        )
                    );
                    cos[j] = keccak256(abi.encodePacked(secretValues[j]));
                    cvs[j] = keccak256(abi.encodePacked(cos[j]));
                }

                // ** Commit
                uint256 sum;
                for (uint256 j; j < numOfOperators; j++) {
                    vm.startPrank(s_anvilDefaultAddresses[j]);
                    commitReveal2.commit(uint256(cvs[j]));
                    vm.stopPrank();
                    if (round % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                }
                if (round % requestTestNum != 0) {
                    gasUsedCommit[(round % requestTestNum) - 1] = sum;
                }
                sum = 0;
                mine();

                // ** Reveal
                for (uint256 j; j < numOfOperators; j++) {
                    vm.startPrank(s_anvilDefaultAddresses[j]);
                    commitReveal2.reveal1(cos[j]);
                    vm.stopPrank();
                    if (round % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                }
                if (round % requestTestNum != 0) {
                    gasUsedReveal1[(round % requestTestNum) - 1] = sum;
                }
                sum = 0;
                mine();

                // ** Reveal2
                // * calculate revealorders
                uint256[] memory dis = new uint256[](numOfOperators);
                uint256[] memory revealOrders = new uint256[](numOfOperators);
                bytes32 rv = keccak256(abi.encodePacked(cos));
                for (uint256 j; j < numOfOperators; j++) {
                    dis[j] = rv > cvs[j]
                        ? uint256(rv) - uint256(cvs[j])
                        : uint256(cvs[j]) - uint256(rv);
                    revealOrders[j] = j;
                }
                QuickSort.sort(dis, revealOrders);

                vm.startPrank(s_anvilDefaultAddresses[revealOrders[0]]);
                commitReveal2.firstReveal2(
                    secretValues[revealOrders[0]],
                    revealOrders
                );
                if (round % requestTestNum != 0) {
                    if (round % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                }
                vm.stopPrank();

                for (uint256 j = 1; j < numOfOperators; j++) {
                    vm.startPrank(s_anvilDefaultAddresses[revealOrders[j]]);
                    commitReveal2.reveal2(secretValues[revealOrders[j]]);
                    vm.stopPrank();
                    if (round % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                }
                if (round % requestTestNum != 0) {
                    gasUsedReveal2[(round % requestTestNum) - 1] = sum;
                }

                // ** Assert
                bytes32[] memory secretsInRevealOrder = new bytes32[](
                    numOfOperators
                );
                for (uint256 j; j < numOfOperators; j++) {
                    secretsInRevealOrder[j] = secretValues[revealOrders[j]];
                }
                uint256 calculatedRandomNum = uint256(
                    keccak256(abi.encodePacked(secretsInRevealOrder))
                );
                uint256 randomNum = commitReveal2.s_randomNum(round + 1);
                assertEq(calculatedRandomNum, randomNum);
            }
            console2.log("Request:");
            console2.log("Average:", getAverage(gasUsedRequest));
            console2.log("Commit:");
            console2.log("Average:", getAverage(gasUsedCommit));
            console2.log("Reveal1:");
            console2.log("Average:", getAverage(gasUsedReveal1));
            console2.log("Reveal2:");
            console2.log("Average:", getAverage(gasUsedReveal2));
        }
    }
}
