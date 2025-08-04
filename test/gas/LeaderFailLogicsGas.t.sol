// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract LeaderFailLogicsGas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    // *** Gas variables
    uint256[] public s_failToRequestSubmitCvOrSubmitMerkleRootGas;
    uint256[] public s_failToSubmitMerkleRootAfterDisputeGas;
    uint256[] public s_failToRequestSorGenerateRandomNumberGas;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 5;
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
        // ** Deploy ConsumerExample
        s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));
        s_callbackGas = s_consumerExample.CALLBACK_GAS_LIMIT();
        (
            s_offChainSubmissionPeriod,
            s_requestOrSubmitOrFailDecisionPeriod,
            s_onChainSubmissionPeriod,
            s_offChainSubmissionPeriodPerOperator,
            s_onChainSubmissionPeriodPerOperator
        ) = s_commitReveal2.getPeriods();
    }

    // ** 1 -> 4
    function test_failToRequestSubmitCvOrSubmitMerkleRootGas() public {
        string memory gasOutput;
        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_failToRequestSubmitCvOrSubmitMerkleRootGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_consumerExample.requestRandomNumber{value: requestFee}();
                mine(s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod);
                s_commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot();
                vm.stopPrank();

                s_failToRequestSubmitCvOrSubmitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;

                vm.startPrank(LEADERNODE);
                s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
            }
            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            gasOutput = vm.serializeUint(
                "gasObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getAverageExceptIndex0(s_failToRequestSubmitCvOrSubmitMerkleRootGas)
            );
        }
        string memory finalOutput = vm.serializeString("any string", "numOfOperators: gasUsed", gasOutput);
        finalOutput = vm.serializeUint(
            "any string",
            "calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot.selector).length
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".failToRequestSubmitCvOrSubmitMerkleRootGas");
    }

    // ** 1 -> 2 -> 3 -> 7
    function test_failToSubmitMerkleRootAfterDisputeGas() public {
        string memory gasOutput;
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_failToSubmitMerkleRootAfterDisputeGas = new uint256[](s_numOfTests);
            s_tempArray = new uint256[](s_numOfOperators);
            for (uint256 i; i < s_numOfOperators; i++) {
                s_tempArray[i] = i;
            }
            s_packedIndices = 0;
            for (uint256 i; i < s_tempArray.length; i++) {
                s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
            }
            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_consumerExample.requestRandomNumber{value: requestFee}();
                vm.stopPrank();
                _setSCoCvRevealOrders(s_privateKeys);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.requestToSubmitCv(s_packedIndices);
                vm.stopPrank();
                for (uint256 j; j < s_numOfOperators; j++) {
                    vm.startPrank(s_operatorAddresses[j]);
                    s_commitReveal2.submitCv(s_cvs[j]);
                    vm.stopPrank();
                }
                mine(s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod);
                vm.startPrank(s_anyAddress);
                s_commitReveal2.failToSubmitMerkleRootAfterDispute();
                vm.stopPrank();
                s_failToSubmitMerkleRootAfterDisputeGas[i] = vm.lastCallGas().gasTotalUsed;

                vm.startPrank(LEADERNODE);
                s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
            }
            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            gasOutput = vm.serializeUint(
                "gasObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getAverageExceptIndex0(s_failToSubmitMerkleRootAfterDisputeGas)
            );
        }
        string memory finalOutput = vm.serializeString("any string", "numOfOperators: gasUsed", gasOutput);
        finalOutput = vm.serializeUint(
            "any string",
            "calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.failToSubmitMerkleRootAfterDispute.selector).length
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".failToSubmitMerkleRootAfterDisputeGas");
    }

    // * 1 -> 5 -> 14
    function test_failToRequestSorGenerateRandomNumberGas() public {
        string memory gasOutput;
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_failToRequestSorGenerateRandomNumberGas = new uint256[](s_numOfTests);
            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_consumerExample.requestRandomNumber{value: requestFee}();
                vm.stopPrank();
                _setSCoCvRevealOrders(s_privateKeys);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                vm.stopPrank();
                mine(
                    s_offChainSubmissionPeriod
                        + (s_offChainSubmissionPeriodPerOperator * s_commitReveal2.getActivatedOperators().length)
                        + s_requestOrSubmitOrFailDecisionPeriod
                );
                vm.startPrank(s_anyAddress);
                s_commitReveal2.failToRequestSorGenerateRandomNumber();
                vm.stopPrank();
                s_failToRequestSorGenerateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;

                vm.startPrank(LEADERNODE);
                s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
            }
            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            gasOutput = vm.serializeUint(
                "gasObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getAverageExceptIndex0(s_failToRequestSorGenerateRandomNumberGas)
            );
        }
        string memory finalOutput = vm.serializeString("any string", "numOfOperators: gasUsed", gasOutput);
        finalOutput = vm.serializeUint(
            "any string",
            "calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.failToRequestSorGenerateRandomNumber.selector).length
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".failToRequestSorGenerateRandomNumberGas");
    }
}
