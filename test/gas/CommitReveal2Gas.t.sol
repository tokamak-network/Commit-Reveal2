// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CommitReveal2Gas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    // *** Gas variables
    uint256[] public s_submitMerkleRootGas;
    uint256[] public s_generateRandomNumberGas;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 10;

        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAddresses(32);
    }

    function _deployContracts() internal {
        // ** Deploy CommitReveal2
        address commitRevealAddress;
        (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).runForTest();
        s_commitReveal2 = CommitReveal2(commitRevealAddress);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
    }

    function test_commitReveal2Gas() public {
        string memory gasOutput;
        string memory gasOutputMax;
        string memory gasOutput2;
        string memory calldataSizeOutput;
        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_submitMerkleRootGas = new uint256[](s_numOfTests);
            s_generateRandomNumberGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            console2.log("s_numOfOperators", s_numOfOperators);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_commitReveal2.requestRandomNumber{value: requestFee}(90000);
                vm.stopPrank();
            }
            for (uint256 i; i < s_numOfTests; i++) {
                _setSCoCvRevealOrders(s_privateKeys);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;

                s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                s_generateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
                vm.stopPrank();
            }

            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            // For generateRandomNumber - use average except index 0
            gasOutput = vm.serializeUint(
                "gasObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getAverageExceptIndex0(s_generateRandomNumberGas)
            );

            // For generateRandomNumber - use max except index 0
            gasOutputMax = vm.serializeUint(
                "gasObjectMax",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getMaxExceptIndex0(s_generateRandomNumberGas)
            );

            // For submitMerkleRoot - use any value except index 0 (since it's constant)
            gasOutput2 = vm.serializeUint(
                "gasObject2",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                s_submitMerkleRootGas[1] // Just use index 1 since it's constant
            );

            // For generateRandomNumber calldata size - measure for each numOfOperators
            calldataSizeOutput = vm.serializeUint(
                "calldataSizeObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                abi.encodeWithSelector(
                    s_commitReveal2.generateRandomNumber.selector, s_secretSigRSs, s_packedVs, s_packedRevealOrders
                ).length
            );
        }

        // Create final JSON output
        string memory finalOutput =
            vm.serializeString("commitReveal2Gas", "generateRandomNumber_numOfOperators_gasUsed_average", gasOutput);
        finalOutput =
            vm.serializeString("commitReveal2Gas", "generateRandomNumber_numOfOperators_gasUsed_max", gasOutputMax);
        finalOutput = vm.serializeString("commitReveal2Gas", "submitMerkleRoot_numOfOperators_gasUsed", gasOutput2);
        finalOutput = vm.serializeString(
            "commitReveal2Gas", "generateRandomNumber_numOfOperators_calldataSizeInBytes", calldataSizeOutput
        );

        // Add submitMerkleRoot calldata size (constant)
        finalOutput = vm.serializeUint(
            "commitReveal2Gas",
            "submitMerkleRoot_calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.submitMerkleRoot.selector, type(uint256).max).length
        );

        vm.writeJson(finalOutput, s_gasReportPath, ".commitReveal2Gas");

        console2.log(
            "submitMerkleRootGas Calldata Size In Bytes:",
            abi.encodeWithSelector(s_commitReveal2.submitMerkleRoot.selector, type(uint256).max).length
        );
    }
}
