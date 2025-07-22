// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {CommitReveal2ForGasTest} from "./../../src/test/CommitReveal2ForGasTest.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract NodesFailLogicsGas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    // *** Gas variables
    uint256[] public s_failToSubmitCvGas;
    uint256[] public s_failToSubmitCoGas;
    uint256[] public s_failToSubmitSGas;

    uint256 public s_requestedToSubmitLength;
    uint256 public s_didntSubmitLength;

    address[] public s_deactivatedOperators;
    address public s_deactivatedOperator;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 4;
        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAdresses(32);
    }

    function _deployContracts() internal {
        // ** Deploy CommitReveal2
        address commitRevealAddress;
        (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).runForGasTest();
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

    // ** 1 -> 2 -> 3 -> 6
    function test_failToSubmitCvGas() public {
        string memory numOfoperatorGasOutput;
        string memory numOfrequestedGasOutput;
        string memory finalGasOutput;

        // ** for loop of s_numOfOperators, requestToSubmitOOLength, didntSubmitOOLength
        for (s_numOfOperators = 2; s_numOfOperators <= 13; s_numOfOperators++) {
            numOfrequestedGasOutput = "";
            for (
                s_requestedToSubmitLength = 1;
                s_requestedToSubmitLength <= s_numOfOperators;
                s_requestedToSubmitLength++
            ) {
                finalGasOutput = "";
                for (s_didntSubmitLength = 1; s_didntSubmitLength <= s_requestedToSubmitLength; s_didntSubmitLength++) {
                    _deployContracts();
                    _depositAndActivateOperators(s_operatorAddresses);
                    s_failToSubmitCvGas = new uint256[](s_numOfTests);

                    uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
                    vm.startPrank(s_anyAddress);
                    s_consumerExample.requestRandomNumber{value: requestFee}();
                    vm.stopPrank();

                    for (uint256 i; i < s_numOfTests; i++) {
                        s_packedIndices = 0;
                        for (uint256 j; j < s_requestedToSubmitLength; j++) {
                            s_packedIndices = s_packedIndices | (j << (j * 8));
                        }
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.requestToSubmitCv(s_packedIndices);
                        mine(1);
                        vm.stopPrank();
                        _setSCoCvRevealOrders(s_privateKeys);
                        for (uint256 j; j < s_requestedToSubmitLength - s_didntSubmitLength; j++) {
                            vm.startPrank(s_activatedOperators[j]);
                            s_commitReveal2.submitCv(s_cvs[j]);
                            vm.stopPrank();
                        }
                        s_deactivatedOperators = new address[](s_didntSubmitLength);
                        for (
                            uint256 j = s_requestedToSubmitLength - s_didntSubmitLength;
                            j < s_requestedToSubmitLength;
                            j++
                        ) {
                            s_deactivatedOperators[j - (s_requestedToSubmitLength - s_didntSubmitLength)] =
                                s_activatedOperators[j];
                        }

                        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.failToSubmitCv();
                        s_failToSubmitCvGas[i] = vm.lastCallGas().gasTotalUsed;
                        mine(1);
                        vm.stopPrank();
                        s_activatedOperators = s_commitReveal2.getActivatedOperators();
                        for (uint256 j = 0; j < s_didntSubmitLength; j++) {
                            vm.startPrank(s_deactivatedOperators[j]);
                            s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                            vm.stopPrank();
                        }
                        if (s_commitReveal2.s_isInProcess() == 3) {
                            vm.startPrank(LEADERNODE);
                            s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                            vm.stopPrank();
                        }
                    }

                    // Create a key for didntSubmitLength level with meaningful name
                    string memory didntSubmitString = Strings.toString(s_didntSubmitLength);
                    string memory didntSubmitKey = string.concat(
                        "didntSubmit_",
                        bytes(didntSubmitString).length == 1 ? string.concat("0", didntSubmitString) : didntSubmitString
                    );

                    // Use unique object name for each combination to avoid accumulation
                    string memory didntSubmitObjectName = string.concat(
                        "didntSubmitObject_",
                        Strings.toString(s_numOfOperators),
                        "_",
                        Strings.toString(s_requestedToSubmitLength)
                    );

                    finalGasOutput = vm.serializeUint(didntSubmitObjectName, didntSubmitKey, s_failToSubmitCvGas[3]);
                }

                // Serialize the requested submit length level with meaningful name
                string memory requestedSubmitString = Strings.toString(s_requestedToSubmitLength);
                string memory requestedSubmitKey = string.concat(
                    "requested_",
                    bytes(requestedSubmitString).length == 1
                        ? string.concat("0", requestedSubmitString)
                        : requestedSubmitString
                );

                // Use unique object name for each operator count
                string memory requestedSubmitObjectName =
                    string.concat("requestedSubmitObject_", Strings.toString(s_numOfOperators));

                numOfrequestedGasOutput =
                    vm.serializeString(requestedSubmitObjectName, requestedSubmitKey, finalGasOutput);
            }

            // Serialize the operator level with meaningful name
            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            string memory operatorKey = string.concat(
                "operators_",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString
            );

            numOfoperatorGasOutput = vm.serializeString("operatorObject", operatorKey, numOfrequestedGasOutput);
        }

        // Create the final output structure with clear description
        string memory finalOutput = vm.serializeString("failToSubmitCvGas", "scenarios", numOfoperatorGasOutput);
        finalOutput = vm.serializeUint(
            "failToSubmitCvGas",
            "calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.failToSubmitCv.selector).length
        );
        finalOutput = vm.serializeString(
            "failToSubmitCvGas",
            "description",
            "Gas usage for failToSubmitCv function by scenario: operators_XX -> requested_YY -> didntSubmit_ZZ"
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".failToSubmitCvGas");
    }

    // ** 1 -> 5 -> 8 -> 10
    function test_failToSubmitCoGas() public {
        string memory numOfoperatorGasOutput;
        string memory numOfrequestedGasOutput;
        string memory finalGasOutput;

        // ** for loop of s_numOfOperators, requestToSubmitOOLength, didntSubmitOOLength
        for (s_numOfOperators = 2; s_numOfOperators <= 13; s_numOfOperators++) {
            numOfrequestedGasOutput = "";
            for (
                s_requestedToSubmitLength = 1;
                s_requestedToSubmitLength <= s_numOfOperators;
                s_requestedToSubmitLength++
            ) {
                finalGasOutput = "";
                for (s_didntSubmitLength = 1; s_didntSubmitLength <= s_requestedToSubmitLength; s_didntSubmitLength++) {
                    _deployContracts();
                    _depositAndActivateOperators(s_operatorAddresses);
                    s_failToSubmitCoGas = new uint256[](s_numOfTests);

                    uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
                    vm.startPrank(s_anyAddress);
                    s_consumerExample.requestRandomNumber{value: requestFee}();
                    vm.stopPrank();

                    for (uint256 i; i < s_numOfTests; i++) {
                        _setSCoCvRevealOrders(s_privateKeys);
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                        s_tempArray = new uint256[](s_requestedToSubmitLength);
                        for (uint256 j; j < s_requestedToSubmitLength; j++) {
                            s_tempArray[j] = j;
                        }
                        _setParametersForRequestToSubmitCo(s_tempArray);
                        s_commitReveal2.requestToSubmitCo(
                            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
                            s_packedVsForAllCvsNotOnChain,
                            s_indicesLength,
                            s_indicesFirstCvNotOnChainRestCvOnChain
                        );
                        vm.stopPrank();
                        for (uint256 j; j < s_requestedToSubmitLength - s_didntSubmitLength; j++) {
                            vm.startPrank(s_activatedOperators[j]);
                            s_commitReveal2.submitCo(s_cos[j]);
                            vm.stopPrank();
                        }
                        s_deactivatedOperators = new address[](s_didntSubmitLength);
                        for (
                            uint256 j = s_requestedToSubmitLength - s_didntSubmitLength;
                            j < s_requestedToSubmitLength;
                            j++
                        ) {
                            s_deactivatedOperators[j - (s_requestedToSubmitLength - s_didntSubmitLength)] =
                                s_activatedOperators[j];
                        }
                        mine(s_onChainSubmissionPeriod);
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.failToSubmitCo();
                        s_failToSubmitCoGas[i] = vm.lastCallGas().gasTotalUsed;
                        mine(1);
                        vm.stopPrank();
                        s_activatedOperators = s_commitReveal2.getActivatedOperators();
                        for (uint256 j = 0; j < s_didntSubmitLength; j++) {
                            vm.startPrank(s_deactivatedOperators[j]);
                            s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                            vm.stopPrank();
                        }
                        if (s_commitReveal2.s_isInProcess() == 3) {
                            vm.startPrank(LEADERNODE);
                            s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                            vm.stopPrank();
                        }
                    }
                    // Create a key for didntSubmitLength level with meaningful name
                    string memory didntSubmitString = Strings.toString(s_didntSubmitLength);
                    string memory didntSubmitKey = string.concat(
                        "didntSubmit_",
                        bytes(didntSubmitString).length == 1 ? string.concat("0", didntSubmitString) : didntSubmitString
                    );

                    // Use unique object name for each combination to avoid accumulation
                    string memory didntSubmitObjectName = string.concat(
                        "didntSubmitObject_",
                        Strings.toString(s_numOfOperators),
                        "_",
                        Strings.toString(s_requestedToSubmitLength)
                    );

                    finalGasOutput = vm.serializeUint(didntSubmitObjectName, didntSubmitKey, s_failToSubmitCoGas[3]);
                }

                // Serialize the requested submit length level with meaningful name
                string memory requestedSubmitString = Strings.toString(s_requestedToSubmitLength);
                string memory requestedSubmitKey = string.concat(
                    "requested_",
                    bytes(requestedSubmitString).length == 1
                        ? string.concat("0", requestedSubmitString)
                        : requestedSubmitString
                );

                // Use unique object name for each operator count
                string memory requestedSubmitObjectName =
                    string.concat("requestedSubmitObject_", Strings.toString(s_numOfOperators));

                numOfrequestedGasOutput =
                    vm.serializeString(requestedSubmitObjectName, requestedSubmitKey, finalGasOutput);
            }

            // Serialize the operator level with meaningful name
            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            string memory operatorKey = string.concat(
                "operators_",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString
            );

            numOfoperatorGasOutput = vm.serializeString("operatorObject", operatorKey, numOfrequestedGasOutput);
        }

        // Create the final output structure with clear description
        string memory finalOutput = vm.serializeString("failToSubmitCoGas", "scenarios", numOfoperatorGasOutput);
        finalOutput = vm.serializeUint(
            "failToSubmitCoGas",
            "calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.failToSubmitCo.selector).length
        );
        finalOutput = vm.serializeString(
            "failToSubmitCoGas",
            "description",
            "Gas usage for failToSubmitCo function by scenario: operators_XX -> requested_YY -> didntSubmit_ZZ"
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".failToSubmitCoGas");
    }

    // ** 1 -> 5 -> 12 -> 13 -> 15
    function test_failToSubmitSGas() public {
        string memory numOfoperatorGasOutput;
        string memory numOfrequestedGasOutput;
        string memory finalGasOutput;

        // ** for loop of s_numOfOperators, requestToSubmitOOLength, didntSubmitOOLength
        for (s_numOfOperators = 2; s_numOfOperators <= 13; s_numOfOperators++) {
            numOfrequestedGasOutput = "";
            for (
                s_requestedToSubmitLength = 1;
                s_requestedToSubmitLength <= s_numOfOperators;
                s_requestedToSubmitLength++
            ) {
                finalGasOutput = "";
                for (s_didntSubmitLength = 1; s_didntSubmitLength <= s_requestedToSubmitLength; s_didntSubmitLength++) {
                    _deployContracts();
                    _depositAndActivateOperators(s_operatorAddresses);
                    s_failToSubmitSGas = new uint256[](s_numOfTests);

                    uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
                    vm.startPrank(s_anyAddress);
                    s_consumerExample.requestRandomNumber{value: requestFee}();
                    vm.stopPrank();

                    for (uint256 i; i < s_numOfTests; i++) {
                        uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                        uint256 k = s_numOfOperators - s_requestedToSubmitLength;
                        _setParametersForRequestToSubmitS(k, revealOrders);
                        s_commitReveal2.requestToSubmitS(
                            s_cos,
                            s_secretsReceivedOffchainInRevealOrder,
                            s_packedVsForAllCvsNotOnChain,
                            s_sigRSsForAllCvsNotOnChain,
                            s_packedRevealOrders
                        );
                        vm.stopPrank();
                        s_deactivatedOperator = s_activatedOperators[revealOrders[k]];
                        mine(s_onChainSubmissionPeriodPerOperator);
                        vm.startPrank(s_anyAddress);
                        s_commitReveal2.failToSubmitS();
                        s_failToSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                        mine(1);
                        vm.stopPrank();
                        s_activatedOperators = s_commitReveal2.getActivatedOperators();
                        vm.startPrank(s_deactivatedOperator);
                        s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                        vm.stopPrank();
                        if (s_commitReveal2.s_isInProcess() == 3) {
                            vm.startPrank(LEADERNODE);
                            s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                            vm.stopPrank();
                        }
                    }
                    // Create a key for didntSubmitLength level with meaningful name
                    string memory didntSubmitString = Strings.toString(s_didntSubmitLength);
                    string memory didntSubmitKey = string.concat(
                        "didntSubmit_",
                        bytes(didntSubmitString).length == 1 ? string.concat("0", didntSubmitString) : didntSubmitString
                    );

                    // Use unique object name for each combination to avoid accumulation
                    string memory didntSubmitObjectName = string.concat(
                        "didntSubmitObject_",
                        Strings.toString(s_numOfOperators),
                        "_",
                        Strings.toString(s_requestedToSubmitLength)
                    );

                    finalGasOutput = vm.serializeUint(didntSubmitObjectName, didntSubmitKey, s_failToSubmitSGas[3]);
                }

                // Serialize the requested submit length level with meaningful name
                string memory requestedSubmitString = Strings.toString(s_requestedToSubmitLength);
                string memory requestedSubmitKey = string.concat(
                    "requested_",
                    bytes(requestedSubmitString).length == 1
                        ? string.concat("0", requestedSubmitString)
                        : requestedSubmitString
                );

                // Use unique object name for each operator count
                string memory requestedSubmitObjectName =
                    string.concat("requestedSubmitObject_", Strings.toString(s_numOfOperators));

                numOfrequestedGasOutput =
                    vm.serializeString(requestedSubmitObjectName, requestedSubmitKey, finalGasOutput);
            }

            // Serialize the operator level with meaningful name
            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            string memory operatorKey = string.concat(
                "operators_",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString
            );

            numOfoperatorGasOutput = vm.serializeString("operatorObject", operatorKey, numOfrequestedGasOutput);
        }

        // Create the final output structure with clear description
        string memory finalOutput = vm.serializeString("failToSubmitSGas", "scenarios", numOfoperatorGasOutput);
        finalOutput = vm.serializeUint(
            "failToSubmitSGas",
            "calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.failToSubmitS.selector).length
        );
        finalOutput = vm.serializeString(
            "failToSubmitSGas",
            "description",
            "Gas usage for failToSubmitS function by scenario: operators_XX -> requested_YY -> didntSubmit_ZZ"
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".failToSubmitSGas");
    }
}
