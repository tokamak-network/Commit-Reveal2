// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2HybridL1} from "./../src/CommitReveal2HybridL1.sol";
import {BaseTest} from "./shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";
import {Sort} from "./../src/Sort.sol";
import {CommitReveal2StorageHybridL1} from "./../src/CommitReveal2StorageHybridL1.sol";

contract CommitReveal2L1Test is BaseTest {
    CommitReveal2HybridL1 public s_commitReveal2HybridL1;

    uint256 public s_activationThreshold = 0.01 ether;
    uint256 s_requestFee = 0.001 ether;
    string public name = "Commit Reveal2";
    string public version = "1";

    bytes32 public nameHash = keccak256(bytes(name));
    bytes32 public versionHash = keccak256(bytes(version));

    uint256 public s_maxNum = 10;

    function setUp() public override {
        BaseTest.setUp(); // Start Prank
        // *** Deploy
        s_commitReveal2HybridL1 = new CommitReveal2HybridL1(
            s_activationThreshold,
            s_requestFee,
            name,
            version
        );
        // *** Deposit And Activate
        vm.stopPrank();
        for (uint256 i; i < s_maxNum; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2HybridL1.deposit{value: 1000 ether}();
            vm.stopPrank();
        }
        vm.startPrank(OWNER);
        for (uint256 i; i < s_maxNum; i++) {
            s_commitReveal2HybridL1.activate(s_anvilDefaultAddresses[i]);
        }
    }

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function getAverage(uint256[] memory data) public pure returns (uint256) {
        uint256 sum;
        for (uint256 i; i < data.length; i++) {
            sum += data[i];
        }
        return sum / data.length;
    }

    function test_L1HybridcommitReveal2Gas() public {
        uint256 requestTestNum = 20;
        console2.log("gasUsed of commmitReveal2L1Hybrid");
        console2.log("---------------------------");
        // *** activated Operators 2~10
        uint256 i = 0;
        for (
            uint256 numOfOperators = 2;
            numOfOperators <= 10;
            numOfOperators++
        ) {
            console2.log("Number of Operators: ", numOfOperators);
            uint256[] memory gasUsedRequest = new uint256[](requestTestNum - 1);
            uint256[] memory gasUsedSubmitMerkleRoot = new uint256[](
                requestTestNum - 1
            );
            uint256[] memory gasUsedGenerateRandomNumber = new uint256[](
                requestTestNum - 1
            );

            // *** Request Random Number
            for (
                uint256 round = i++ * requestTestNum;
                round < requestTestNum * i;
                round++
            ) {
                s_commitReveal2HybridL1.requestRandomNumber{
                    value: s_requestFee
                }();
                //console2.log("Request:", vm.lastCallGas().gasTotalUsed);
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

                bytes32 merkleRoot = s_commitReveal2HybridL1.getMerkleRoot(cvs);
                // *** Submit MerkleRoot
                vm.stopPrank();
                vm.startPrank(s_anvilDefaultAddresses[round % numOfOperators]);
                s_commitReveal2HybridL1.submitMerkleRoot(merkleRoot);
                vm.stopPrank();
                if (round % requestTestNum != 0) {
                    gasUsedSubmitMerkleRoot[(round % requestTestNum) - 1] = vm
                        .lastCallGas()
                        .gasTotalUsed;
                }

                // console2.log(
                //     "Submit MerkleRoot:",
                //     vm.lastCallGas().gasTotalUsed
                // );

                // *** Reveal1, calculate rv and reveal orders
                bytes32 rv = keccak256(abi.encodePacked(cos));
                uint256[] memory revealOrders = new uint256[](numOfOperators);
                uint256[] memory revealOrdersIndex = new uint256[](
                    numOfOperators
                );
                for (uint256 j; j < numOfOperators; j++) {
                    revealOrders[j] = uint256(rv) > uint256(cvs[j])
                        ? uint256(rv) - uint256(cvs[j])
                        : uint256(cvs[j]) - uint256(rv);
                    revealOrdersIndex[j] = j;
                }
                Sort.sort(revealOrders, revealOrdersIndex);

                // *** 4. Reveal2, Broadcast
                bytes32[] memory secretValuesInRevealOrder = new bytes32[](
                    numOfOperators
                );
                for (uint256 j; j < numOfOperators; j++) {
                    secretValuesInRevealOrder[j] = secretValues[
                        revealOrdersIndex[j]
                    ];
                }
                uint8[] memory vs = new uint8[](numOfOperators);
                bytes32[] memory rs = new bytes32[](numOfOperators);
                bytes32[] memory ss = new bytes32[](numOfOperators);
                for (uint256 j; j < numOfOperators; j++) {
                    bytes32 typedDataHash = keccak256(
                        abi.encodePacked(
                            hex"19_01",
                            keccak256(
                                abi.encode(
                                    keccak256(
                                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                                    ),
                                    nameHash,
                                    versionHash,
                                    block.chainid,
                                    address(s_commitReveal2HybridL1)
                                )
                            ),
                            keccak256(
                                abi.encode(
                                    keccak256(
                                        "Message(uint256 round,bytes32 cv)"
                                    ),
                                    CommitReveal2StorageHybridL1.Message({
                                        round: round + 1,
                                        cv: cvs[j]
                                    })
                                )
                            )
                        )
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
                s_commitReveal2HybridL1.generateRandomNumber(
                    secretValues,
                    vs,
                    rs,
                    ss,
                    revealOrdersIndex
                );
                // console2.log(
                //     "Generate Random Number:",
                //     vm.lastCallGas().gasTotalUsed
                // );
                if (round % requestTestNum != 0) {
                    gasUsedGenerateRandomNumber[
                        (round % requestTestNum) - 1
                    ] = vm.lastCallGas().gasTotalUsed;
                }
                assertEq(
                    s_commitReveal2HybridL1.s_randomNum(round + 1),
                    uint256(
                        keccak256(abi.encodePacked(secretValuesInRevealOrder))
                    )
                );
            }
            mine();
            console2.log("Request:");
            console2.log(getAverage(gasUsedRequest));
            console2.log("Submit MerkleRoot:");
            console2.log(getAverage(gasUsedSubmitMerkleRoot));
            console2.log("Generate Random Number:");
            console2.log(getAverage(gasUsedGenerateRandomNumber));
        }
    }
}
