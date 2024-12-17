// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./shared/BaseTest.t.sol";
import {CommitReveal2L1} from "../src/CommitReveal2L1.sol";
import {console2} from "forge-std/Test.sol";
import {Sort} from "./../src/Sort.sol";

contract CommitReveal2L1Test is BaseTest {
    CommitReveal2L1 commitReveal2L1;
    uint256 s_activationThreshold;
    uint256 s_requestFee;
    uint256 s_commitDuration;
    uint256 s_reveal1Duration;
    uint256 s_maxActivatedOperators;

    function setUp() public override {
        BaseTest.setUp(); // Start Prank
        s_activationThreshold = 0.1 ether;
        s_requestFee = 0.01 ether;
        s_commitDuration = 120;
        s_reveal1Duration = 120;
        commitReveal2L1 = new CommitReveal2L1(
            s_activationThreshold,
            s_requestFee,
            s_commitDuration,
            s_reveal1Duration
        );
        s_maxActivatedOperators = 10;
        vm.stopPrank();
        for (uint256 i = 0; i < s_maxActivatedOperators; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            commitReveal2L1.deposit{value: s_activationThreshold}();
            vm.stopPrank();
        }
    }

    function mine() public {
        vm.warp(block.timestamp + 121);
        vm.roll(block.number + 10);
    }

    function getAverage(uint256[] memory data) public pure returns (uint256) {
        uint256 sum;
        for (uint256 i; i < data.length; i++) {
            sum += data[i];
        }
        return sum / data.length;
    }

    function test_L1commitReveal2Gas() public {
        uint256 requestTestNum = 21;
        console2.log("gasUsed of commmitReveal2L1");
        console2.log("---------------------------");
        uint256 i = 0;
        for (
            uint256 numOfOperators = 2;
            numOfOperators <= s_maxActivatedOperators;
            numOfOperators++
        ) {
            console2.log("Number of Operators: ", numOfOperators);
            uint256[] memory gasUsedRequest = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedCommit = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedReveal1 = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedReveal2 = new uint256[](requestTestNum - 1);
            for (
                uint256 requestId = i++ * requestTestNum;
                requestId < requestTestNum * i;
                requestId++
            ) {
                // ** Request Random Number
                commitReveal2L1.requestRandomNumber{value: s_requestFee}();
                // from second request
                if (requestId % requestTestNum != 0) {
                    gasUsedRequest[(requestId % requestTestNum) - 1] = vm
                        .lastCallGas()
                        .gasTotalUsed;
                }
                //console2.log("Request:", vm.lastCallGas().gasTotalUsed);

                // * Create secretValues, cos, cvs
                bytes32[] memory secretValues = new bytes32[](numOfOperators);
                bytes32[] memory cos = new bytes32[](numOfOperators);
                bytes32[] memory cvs = new bytes32[](numOfOperators);
                for (uint256 j; j < numOfOperators; j++) {
                    secretValues[j] = keccak256(
                        abi.encodePacked(
                            numOfOperators,
                            requestId,
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
                    commitReveal2L1.commit(uint256(cvs[j]));
                    vm.stopPrank();
                    //console2.log("Commit:", vm.lastCallGas().gasTotalUsed);
                    if (requestId % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                }
                if (requestId % requestTestNum != 0) {
                    gasUsedCommit[(requestId % requestTestNum) - 1] = sum;
                }
                sum = 0;
                mine();

                // ** Reveal1
                for (uint256 j; j < numOfOperators; j++) {
                    vm.startPrank(s_anvilDefaultAddresses[j]);
                    commitReveal2L1.reveal1(cos[j]);
                    vm.stopPrank();
                    if (requestId % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                    // if (requestId % requestTestNum != 0) {
                    //     gasUsedReveal1[
                    //         ((requestId % requestTestNum) - 1) *
                    //             numOfOperators +
                    //             j
                    //     ] = vm.lastCallGas().gasTotalUsed;
                    // }
                }
                if (requestId % requestTestNum != 0) {
                    gasUsedReveal1[(requestId % requestTestNum) - 1] = sum;
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
                Sort.sort(dis, revealOrders);

                vm.startPrank(s_anvilDefaultAddresses[revealOrders[0]]);
                commitReveal2L1.firstReveal2(
                    secretValues[revealOrders[0]],
                    revealOrders
                );
                //console2.log("FirstReveal2:", vm.lastCallGas().gasTotalUsed);
                if (requestId % requestTestNum != 0) {
                    // gasUsedReveal2[
                    //     ((requestId % requestTestNum) - 1) * numOfOperators
                    // ] = vm.lastCallGas().gasTotalUsed;
                    if (requestId % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                }
                vm.stopPrank();

                for (uint256 j = 1; j < numOfOperators; j++) {
                    vm.startPrank(s_anvilDefaultAddresses[revealOrders[j]]);
                    commitReveal2L1.reveal2(secretValues[revealOrders[j]]);
                    vm.stopPrank();
                    //console2.log("Reveal2:", vm.lastCallGas().gasTotalUsed);
                    if (requestId % requestTestNum != 0) {
                        sum += vm.lastCallGas().gasTotalUsed;
                    }
                    // if (requestId % requestTestNum != 0) {
                    //     gasUsedReveal2[
                    //         ((requestId % requestTestNum) - 1) *
                    //             numOfOperators +
                    //             j
                    //     ] = vm.lastCallGas().gasTotalUsed;
                    // }
                }
                if (requestId % requestTestNum != 0) {
                    gasUsedReveal2[(requestId % requestTestNum) - 1] = sum;
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
                uint256 randomNum = commitReveal2L1.s_randomNum(requestId + 1);
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
