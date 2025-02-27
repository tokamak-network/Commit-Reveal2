// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2Hybrid} from "./../src/CommitReveal2Hybrid.sol";
import {BaseTest} from "./shared/BaseTest.t.sol";
import {Utils} from "./shared/Utils.t.sol";
import {console2} from "forge-std/Test.sol";
import {QuickSort} from "./shared/QuickSort.sol";

contract CommitReveal2Test is BaseTest, Utils {
    CommitReveal2Hybrid public s_commitReveal2Hybrid;

    function setUp() public override {
        BaseTest.setUp(); // Start Prank
        // *** Deploy
        s_commitReveal2Hybrid = new CommitReveal2Hybrid(
            s_activationThreshold,
            s_requestFee,
            name,
            version
        );
        // *** Deposit And Activate
        vm.stopPrank();
        for (uint256 i; i < s_maxOperators; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2Hybrid.deposit{value: 1000 ether}();
            vm.stopPrank();
        }
        vm.startPrank(OWNER);
        for (uint256 i; i < s_maxOperators; i++) {
            s_commitReveal2Hybrid.activate(s_anvilDefaultAddresses[i]);
        }
    }

    function test_HybridCommitReveal2() public {
        console2.log("gasUsed of commmitReveal2Hybrid");
        console2.log("---------------------------");
        // *** activated Operators 2~10
        uint256 i;
        for (
            uint256 numOfOperators = 2;
            numOfOperators <= 10;
            numOfOperators++
        ) {
            console2.log("Number of Operators: ", numOfOperators);
            uint256[] memory gasUsedRequest = new uint256[](
                s_requestTestNum - 1
            );
            uint256[] memory gasUsedSubmitMerkleRoot = new uint256[](
                s_requestTestNum - 1
            );
            uint256[] memory gasUsedGenerateRandomNumber = new uint256[](
                s_requestTestNum - 1
            );

            // *** Request Random Number
            for (
                uint256 round = i++ * s_requestTestNum;
                round < s_requestTestNum * i;
                round++
            ) {
                s_commitReveal2Hybrid.requestRandomNumber{
                    value: s_requestFee
                }();
                if (round % s_requestTestNum != 0) {
                    gasUsedRequest[(round % s_requestTestNum) - 1] = vm
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

                // *** Submit MerkleRoot
                vm.stopPrank();
                vm.startPrank(s_anvilDefaultAddresses[round % numOfOperators]);
                s_commitReveal2Hybrid.submitMerkleRoot(getMerkleRoot(cvs));
                vm.stopPrank();
                if (round % s_requestTestNum != 0) {
                    gasUsedSubmitMerkleRoot[(round % s_requestTestNum) - 1] = vm
                        .lastCallGas()
                        .gasTotalUsed;
                }

                // *** Reveal, calculate rv and reveal orders
                bytes32 rv = keccak256(abi.encodePacked(cos));
                uint256[] memory revealOrders = new uint256[](numOfOperators);
                uint256[] memory revealOrdersIndex = new uint256[](
                    numOfOperators
                );
                for (uint256 j; j < numOfOperators; j++) {
                    revealOrders[j] = uint256(rv) > uint256(cvs[j])
                        ? uint256(
                            keccak256(
                                abi.encodePacked(uint256(rv) - uint256(cvs[j]))
                            )
                        )
                        : uint256(
                            keccak256(
                                abi.encodePacked(uint256(cvs[j]) - uint256(rv))
                            )
                        );
                    revealOrdersIndex[j] = j;
                }
                QuickSort.sort(revealOrders, revealOrdersIndex);

                // *** 4. Reveal2, Broadcast
                uint8[] memory vs = new uint8[](numOfOperators);
                bytes32[] memory rs = new bytes32[](numOfOperators);
                bytes32[] memory ss = new bytes32[](numOfOperators);
                for (uint256 j; j < numOfOperators; j++) {
                    bytes32 typedDataHash = getHashTypedDataV4(
                        address(s_commitReveal2Hybrid),
                        round + 1,
                        cvs[j]
                    );
                    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                        s_anvilDefaultPrivateKeys[j],
                        typedDataHash
                    );
                    vs[j] = v;
                    rs[j] = r;
                    ss[j] = s;
                }
                // * broadcast
                s_commitReveal2Hybrid.generateRandomNumber(
                    secretValues,
                    vs,
                    rs,
                    ss
                );
                if (round % s_requestTestNum != 0) {
                    gasUsedGenerateRandomNumber[
                        (round % s_requestTestNum) - 1
                    ] = vm.lastCallGas().gasTotalUsed;
                }
                assertEq(
                    s_commitReveal2Hybrid.s_randomNum(round + 1),
                    uint256(keccak256(abi.encodePacked(secretValues)))
                );
            }
            console2.log("Request:");
            console2.log(getAverage(gasUsedRequest));
            console2.log("Submit MerkleRoot:");
            console2.log(getAverage(gasUsedSubmitMerkleRoot));
            console2.log("Generate Random Number:");
            console2.log(getAverage(gasUsedGenerateRandomNumber));
        }
    }
}
