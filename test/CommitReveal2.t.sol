// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../src/CommitReveal2.sol";
import {BaseTest} from "./shared/BaseTest.t.sol";
import {ConsumerExample} from "./../src/ConsumerExample.sol";
import {console2} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./../script/NetworkHelperConfig.s.sol";
import {Sort} from "./../src/Sort.sol";
import {CommitReveal2Storage} from "./../src/CommitReveal2Storage.sol";
import {OptimismL1FeesExternal} from "./shared/OptimismL1FeesExternal.sol";

interface L1Block {
    function baseFeeScalar() external view returns (uint32);

    function basefee() external view returns (uint256);

    function blobBaseFee() external view returns (uint256);

    function blobBaseFeeScalar() external view returns (uint32);
}

contract CommitReveal2Test is BaseTest {
    // ** Contracts
    CommitReveal2 public s_commitReveal2;
    ConsumerExample public s_consumerExample;

    // ** Constructor Parameters
    uint256 public s_activationThreshold;
    uint256 public s_flatFee;
    uint256 public s_maxActivatedOperators = 10;
    uint256 s_l1GasCostMode;

    // ** constant
    string public name = "Tokamak DRB";
    string public version = "1";
    bytes32 public nameHash = keccak256(bytes(name));
    bytes32 public versionHash = keccak256(bytes(version));

    function setUp() public override {
        BaseTest.setUp(); // Start Prank
        if (block.chainid == 31337) vm.txGasPrice(100 gwei);

        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();

        (
            s_activationThreshold,
            ,
            s_flatFee,
            s_l1GasCostMode,
            ,
            ,

        ) = networkHelperConfig.activeNetworkConfig();

        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            vm.deal(s_anvilDefaultAddresses[i], 10000 ether);
        }
    }

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function createMerkleRoot(
        bytes32[] memory leaves
    ) private pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function unchecked_inc(uint256 x) private pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    function _efficientKeccak256(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function getAverage(uint256[] memory data) public pure returns (uint256) {
        uint256 sum;
        for (uint256 i; i < data.length; i++) {
            sum += data[i];
        }
        return sum / data.length;
    }

    function test_generateRandomNumber() public {
        uint256 requestTestNum = 20;
        console2.log("l2gasUsed of commitreveal2");
        console2.log("-------------------------");
        // *** activated Operators 2~10
        for (
            uint256 numOfOperators = 2;
            numOfOperators <= s_maxActivatedOperators;
            numOfOperators++
        ) {
            console2.log("Number of Operators: ", numOfOperators);
            // *** Deploy contracts
            s_commitReveal2 = new CommitReveal2(
                s_activationThreshold,
                s_flatFee,
                s_maxActivatedOperators,
                name,
                version
            );
            (uint8 mode, ) = s_commitReveal2.getL1FeeCalculationMode();
            if (uint256(mode) != s_l1GasCostMode) {
                s_commitReveal2.setL1FeeCalculation(
                    uint8(s_l1GasCostMode),
                    100
                );
            }
            s_consumerExample = new ConsumerExample(address(s_commitReveal2));

            // *** Deposit And Activate
            vm.stopPrank();
            for (uint256 i; i < numOfOperators; i++) {
                vm.startPrank(s_anvilDefaultAddresses[i]);
                s_commitReveal2.deposit{value: 1000 ether}();
                vm.stopPrank();
            }
            vm.startPrank(OWNER);
            for (uint256 i; i < numOfOperators; i++) {
                s_commitReveal2.activate(s_anvilDefaultAddresses[i]);
            }

            // *** 1. Wait For Requests
            // ** Consumer Example Request requestTestNum times
            uint256 requestFee = s_commitReveal2.estimateRequestPrice(
                tx.gasprice,
                s_consumerExample.CALLBACK_GAS_LIMIT()
            );

            uint256[] memory gasUsedOfRequestRandomNumber = new uint256[](
                requestTestNum
            );
            for (uint256 i; i < requestTestNum; i++) {
                s_consumerExample.requestRandomNumber{value: requestFee}();
                gasUsedOfRequestRandomNumber[i] = vm.lastCallGas().gasTotalUsed;
            }
            console2.log(
                "Average Gas Used of Request Random Number: ",
                getAverage(gasUsedOfRequestRandomNumber)
            );

            // *** 2. Commit^2
            // ** Generate commit, reveal1, reveal2, merkle roots
            bytes32[][] memory secretValues = new bytes32[][](requestTestNum);
            bytes32[][] memory cos = new bytes32[][](requestTestNum);
            bytes32[][] memory cvs = new bytes32[][](requestTestNum);
            bytes32[] memory merkleRoots = new bytes32[](requestTestNum);

            for (uint256 i; i < requestTestNum; i++) {
                secretValues[i] = new bytes32[](numOfOperators);
                cos[i] = new bytes32[](numOfOperators);
                cvs[i] = new bytes32[](numOfOperators);
                for (uint256 j; j < numOfOperators; j++) {
                    secretValues[i][j] = keccak256(
                        abi.encodePacked(i, j, block.timestamp)
                    );
                    cos[i][j] = keccak256(abi.encodePacked(secretValues[i][j]));
                    cvs[i][j] = keccak256(abi.encodePacked(cos[i][j]));
                    mine();
                    merkleRoots[i] = createMerkleRoot(cvs[i]);
                }
            }
            // ** Submit Merkle Root

            uint256[] memory gasUsedOfSubmitMerkleRoot = new uint256[](
                requestTestNum
            );
            vm.stopPrank();
            for (uint256 i; i < requestTestNum; i++) {
                vm.startPrank(s_anvilDefaultAddresses[i % numOfOperators]);
                s_commitReveal2.submitMerkleRoot(i, merkleRoots[i]);
                vm.stopPrank();
                gasUsedOfSubmitMerkleRoot[i] = vm.lastCallGas().gasTotalUsed;
            }
            vm.startPrank(OWNER);

            // for (uint256 i; i < requestTestNum; i++) {
            //     console2.log(
            //         "Gas Used of Submit Merkle Root: ",
            //         gasUsedOfSubmitMerkleRoot[i]
            //     );
            // }
            console2.log(
                "Average Gas Used of Submit Merkle Root: ",
                getAverage(gasUsedOfSubmitMerkleRoot)
            );

            // *** 3. Reveal1, calculate rv and reveal orders
            bytes32[] memory rvs = new bytes32[](requestTestNum);
            uint256[][] memory revealOrders = new uint256[][](requestTestNum);
            uint256[][] memory revealOrdersIndexs = new uint256[][](
                requestTestNum
            );
            uint256[] memory gasUsedOfGenerateRandomNumber1 = new uint256[](
                requestTestNum
            );
            for (uint256 i; i < requestTestNum; i++) {
                rvs[i] = keccak256(abi.encodePacked(cos[i]));
                revealOrders[i] = new uint256[](numOfOperators);
                revealOrdersIndexs[i] = new uint256[](numOfOperators);
                for (uint256 j; j < numOfOperators; j++) {
                    revealOrders[i][j] = uint256(rvs[i]) > uint256(cvs[i][j])
                        ? uint256(rvs[i]) - uint256(cvs[i][j])
                        : uint256(cvs[i][j]) - uint256(rvs[i]);
                    revealOrdersIndexs[i][j] = j;
                }
            }
            // ** Sort reveal orders
            for (uint256 i; i < requestTestNum; i++) {
                Sort.sort(revealOrders[i], revealOrdersIndexs[i]);
            }

            // *** 4. Reveal2, Broadcast
            bytes32[][] memory secretValuesInRevealOrder = new bytes32[][](
                requestTestNum
            );
            uint8[][] memory vs = new uint8[][](requestTestNum);
            bytes32[][] memory rs = new bytes32[][](requestTestNum);
            bytes32[][] memory ss = new bytes32[][](requestTestNum);
            for (uint256 i; i < requestTestNum; i++) {
                secretValuesInRevealOrder[i] = new bytes32[](numOfOperators);
                // ** secreteValues in reveal order
                for (uint256 j; j < numOfOperators; j++) {
                    secretValuesInRevealOrder[i][j] = secretValues[i][
                        revealOrdersIndexs[i][j]
                    ];
                }

                vs[i] = new uint8[](numOfOperators);
                rs[i] = new bytes32[](numOfOperators);
                ss[i] = new bytes32[](numOfOperators);
                // ** signatures
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
                                    address(s_commitReveal2)
                                )
                            ),
                            keccak256(
                                abi.encode(
                                    keccak256(
                                        "Message(uint256 round,bytes32 cv)"
                                    ),
                                    CommitReveal2Storage.Message({
                                        round: i,
                                        cv: cvs[i][j]
                                    })
                                )
                            )
                        )
                    );
                    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                        s_anvilDefaultPrivateKeys[j],
                        typedDataHash
                    );
                    vs[i][j] = v;
                    rs[i][j] = r;
                    ss[i][j] = s;
                }
                // ** broadcast
                s_commitReveal2.generateRandomNumber(
                    i,
                    secretValues[i],
                    // revealOrdersIndexs[i],
                    vs[i],
                    rs[i],
                    ss[i]
                );
                gasUsedOfGenerateRandomNumber1[i] = vm
                    .lastCallGas()
                    .gasTotalUsed;
                (, , uint256 randomNumber) = s_consumerExample.s_requests(i);
                assertEq(
                    uint256(
                        keccak256(
                            abi.encodePacked(secretValuesInRevealOrder[i])
                        )
                    ),
                    randomNumber
                );
            }
            // for (uint256 i; i < requestTestNum; i++) {
            //     console2.log(
            //         "Gas Used of Generate Random Number: ",
            //         gasUsedOfGenerateRandomNumber1[i]
            //     );
            // }
            console2.log(
                "Average Gas Used of Generate Random Number: ",
                getAverage(gasUsedOfGenerateRandomNumber1)
            );
            for (uint256 i; i < numOfOperators; i++) {
                s_commitReveal2.deactivate(s_anvilDefaultAddresses[i]);
            }
            assertEq(
                s_commitReveal2.getActivatedOperatorsLength(),
                0,
                "Activated Operators Length"
            );
        }
    }

    function test_generateRandomNumberCalldata() public {
        string memory key = "OP_MAINNET_RPC_URL";
        string memory OP_MAINNET_RPC_URL = vm.envString(key);
        uint256 optimismFork = vm.createFork(OP_MAINNET_RPC_URL);
        vm.selectFork(optimismFork);

        L1Block l1Block = L1Block(
            address(0x4200000000000000000000000000000000000015)
        );
        console2.log("l1gasFee of commitreveal2");
        console2.log("-------------------------");
        console2.log("baseFeeScalar: ", l1Block.baseFeeScalar());
        console2.log("basefee: ", l1Block.basefee());
        console2.log("blobBaseFee: ", l1Block.blobBaseFee());
        console2.log("blobBaseFeeScalar: ", l1Block.blobBaseFeeScalar());

        OptimismL1FeesExternal optimismL1FeesExternal = new OptimismL1FeesExternal();

        optimismL1FeesExternal.setL1FeeCalculation(uint8(0), 100);

        // *** activated Operators 2~10
        for (
            uint256 numOfOperators = 2;
            numOfOperators <= s_maxActivatedOperators;
            numOfOperators++
        ) {
            console2.log("Number of Operators: ", numOfOperators);
            console2.log("calldata size of requestRandomNumber: ", uint256(4));
            console2.log(
                "l1gasFee of requestRandomNumber: ",
                optimismL1FeesExternal.getL1CostWeiForCalldataSize(4)
            );

            console2.log("calldata size of submitMerkleRoot: ", uint256(68));
            console2.log(
                "l1gasFee of submitMerkleRoot: ",
                optimismL1FeesExternal.getL1CostWeiForCalldataSize(68)
            );

            // ** broadcast
            console2.log(
                "calldata size of generateRandomNumber",
                292 + (128 * numOfOperators)
            );
            console2.log(
                "l1gasFee of generateRandomNumber",
                optimismL1FeesExternal.getL1CostWeiForCalldataSize(
                    292 + (128 * numOfOperators)
                )
            );
            console2.log("calldata size of chainlink fulfill", uint256(772));
            console2.log(
                "l1gasFee of chainlink fulfill",
                optimismL1FeesExternal.getL1CostWeiForCalldataSize(772)
            );
        }
    }
}
