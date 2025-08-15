// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// This test scans parameter combinations to empirically find the scenario that maximizes
// the sum of request-phase gas costs per path while keeping runtime practical.
// - Cv/Co path scans operators in [2..7], submitCv in [0..operators], submitCo in [0..operators]
// - Secrets path scans operators in [2..13], submitCv in [0..operators]
// For each combo, it performs 4 iterations and uses only the last sample (index 3) like existing tests.
// Results are written to output/maxRequestPhaseGas.json.
contract MaxDisputeLogics is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    uint256[] public s_requestToSubmitCvGas;
    uint256[] public s_submitCvGas;
    uint256[] public s_requestToSubmitCoGas;
    uint256[] public s_submitCoGas;
    uint256[] public s_requestToSubmitSGas;
    uint256[] public s_lastSubmitSGas;
    uint256[] public s_submitSGas;
    uint256[] public s_generateRandomNumberWhenSomeCvsAreOnChainGas;

    uint256 public s_submitCvLength;
    uint256 public s_submitCoLength;

    string internal constant OUTPUT_PATH = "output/maxDisputeGas.json";

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 4;
        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAddresses(32);
    }

    function _deployContracts() internal {
        address commitRevealAddress;
        (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).runForGasTest();
        s_commitReveal2 = CommitReveal2(commitRevealAddress);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
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

    // Heuristic scan (from gasreport): request sum tends to peak when submitCo is max,
    // and submitCv is minimal or very small. We therefore scan only a few candidates.
    function test_findMaxCvCoRequestSumGas() public {
        uint256 maxSum = 0;
        string memory maxScenarioKey = "";
        uint256 maxReqCv = 0;
        uint256 maxReqCo = 0;
        uint256 maxSubmitCvGas = 0;
        uint256 maxSubmitCoGas = 0;
        uint256 maxGenWhenSomeGas = 0;

        s_numOfOperators = 32;
        uint256[] memory submitCvCandidates = new uint256[](4);
        submitCvCandidates[0] = 0;
        submitCvCandidates[1] = 1;
        submitCvCandidates[2] = 2;
        submitCvCandidates[3] = 32;
        uint256[] memory submitCoCandidates = new uint256[](1);
        submitCoCandidates[0] = 32;

        for (uint256 a; a < submitCvCandidates.length; a++) {
            s_submitCvLength = submitCvCandidates[a];
            for (uint256 b; b < submitCoCandidates.length; b++) {
                s_submitCoLength = submitCoCandidates[b];
                _deployContracts();
                _depositAndActivateOperators(s_operatorAddresses);

                s_requestToSubmitCvGas = new uint256[](s_numOfTests);
                s_submitCvGas = new uint256[](s_numOfTests);
                s_requestToSubmitCoGas = new uint256[](s_numOfTests);
                s_submitCoGas = new uint256[](s_numOfTests);
                s_generateRandomNumberWhenSomeCvsAreOnChainGas = new uint256[](s_numOfTests);

                uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);

                for (uint256 i; i < s_numOfTests; i++) {
                    vm.startPrank(s_anyAddress);
                    s_commitReveal2.requestRandomNumber{value: requestFee}(90000);
                    vm.stopPrank();

                    _setSCoCvRevealOrders(s_privateKeys);

                    if (s_submitCvLength > 0) {
                        s_packedIndices = 0;
                        for (uint256 j; j < s_submitCvLength; j++) {
                            s_packedIndices = s_packedIndices | (j << (j * 8));
                        }
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.requestToSubmitCv(s_packedIndices);
                        s_requestToSubmitCvGas[i] = vm.lastCallGas().gasTotalUsed;
                        vm.stopPrank();
                    }

                    for (uint256 j; j < s_submitCvLength; j++) {
                        vm.startPrank(s_activatedOperators[j]);
                        s_commitReveal2.submitCv(s_cvs[j]);
                        if (j == 0) s_submitCvGas[i] = vm.lastCallGas().gasTotalUsed;
                        vm.stopPrank();
                    }

                    vm.startPrank(LEADERNODE);
                    s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                    vm.stopPrank();

                    if (s_submitCoLength > 0) {
                        s_tempArray = new uint256[](s_submitCoLength);
                        for (uint256 j; j < s_submitCoLength; j++) {
                            s_tempArray[j] = j;
                        }
                        _setParametersForRequestToSubmitCo(s_tempArray);
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.requestToSubmitCo(
                            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
                            s_packedVsForAllCvsNotOnChain,
                            s_indicesLength,
                            s_indicesFirstCvNotOnChainRestCvOnChain
                        );
                        s_requestToSubmitCoGas[i] = vm.lastCallGas().gasTotalUsed;
                        vm.stopPrank();
                    }

                    for (uint256 j; j < s_submitCoLength; j++) {
                        vm.startPrank(s_activatedOperators[j]);
                        s_commitReveal2.submitCo(s_cos[j]);
                        if (j == 0) s_submitCoGas[i] = vm.lastCallGas().gasTotalUsed;
                        vm.stopPrank();
                    }

                    if (s_submitCvLength > 0 || s_submitCoLength > 0) {
                        _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain();
                        s_commitReveal2.generateRandomNumberWhenSomeCvsAreOnChain(
                            s_secrets, s_sigRSsForAllCvsNotOnChain, s_packedVsForAllCvsNotOnChain, s_packedRevealOrders
                        );
                        s_generateRandomNumberWhenSomeCvsAreOnChainGas[i] = vm.lastCallGas().gasTotalUsed;
                    } else {
                        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                    }
                }

                uint256 reqCv = s_submitCvLength > 0 ? s_requestToSubmitCvGas[3] : 0;
                uint256 reqCo = s_submitCoLength > 0 ? s_requestToSubmitCoGas[3] : 0;
                uint256 sumReq = reqCv + reqCo;

                if (sumReq > maxSum) {
                    maxSum = sumReq;
                    maxReqCv = reqCv;
                    maxReqCo = reqCo;
                    maxSubmitCvGas = s_submitCvGas[3];
                    maxSubmitCoGas = s_submitCoGas[3];
                    maxGenWhenSomeGas = s_generateRandomNumberWhenSomeCvsAreOnChainGas[3];
                    maxScenarioKey = string.concat(
                        "operators_",
                        bytes(Strings.toString(s_numOfOperators)).length == 1
                            ? string.concat("0", Strings.toString(s_numOfOperators))
                            : Strings.toString(s_numOfOperators),
                        "_submitCv_",
                        bytes(Strings.toString(s_submitCvLength)).length == 1
                            ? string.concat("0", Strings.toString(s_submitCvLength))
                            : Strings.toString(s_submitCvLength),
                        "_submitCo_",
                        bytes(Strings.toString(s_submitCoLength)).length == 1
                            ? string.concat("0", Strings.toString(s_submitCoLength))
                            : Strings.toString(s_submitCoLength)
                    );
                }
            }
        }

        string memory gasData = "";
        gasData = vm.serializeUint("max", "requestToSubmitCvGas", maxReqCv);
        gasData = vm.serializeUint("max", "submitCvGas", maxSubmitCvGas);
        gasData = vm.serializeUint("max", "requestToSubmitCoGas", maxReqCo);
        gasData = vm.serializeUint("max", "submitCoGas", maxSubmitCoGas);
        gasData = vm.serializeUint("max", "generateRandomNumberWhenSomeCvsAreOnChainGas", maxGenWhenSomeGas);
        gasData = vm.serializeUint("max", "sumRequestGas", maxSum);

        string memory payload = vm.serializeString("disputeCvCoGas", "scenarioKey", maxScenarioKey);
        payload = vm.serializeString("disputeCvCoGas", "metrics", gasData);
        vm.writeJson(payload, OUTPUT_PATH, ".disputeCvCoGas");
    }

    // Heuristic scan (from gasreport): requestToSubmitS tends to be larger when fewer CVs are on-chain.
    // We therefore scan only submitCv in {0,1,2,32} with 32 operators.
    function test_findMaxSecretsRequestSumGas() public {
        uint256 maxSum = 0;
        string memory maxScenarioKey = "";
        uint256 maxReqCv = 0;
        uint256 maxReqS = 0;
        uint256 maxSubmitCvGas = 0;
        uint256 maxSubmitSGas = 0;
        uint256 maxLastSubmitSGas = 0;

        s_numOfOperators = 32;
        uint256[] memory submitCvCandidates = new uint256[](4);
        submitCvCandidates[0] = 0;
        submitCvCandidates[1] = 1;
        submitCvCandidates[2] = 2;
        submitCvCandidates[3] = 32;
        for (uint256 a; a < submitCvCandidates.length; a++) {
            s_submitCvLength = submitCvCandidates[a];
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);

            s_requestToSubmitCvGas = new uint256[](s_numOfTests);
            s_submitCvGas = new uint256[](s_numOfTests);
            s_requestToSubmitSGas = new uint256[](s_numOfTests);
            s_lastSubmitSGas = new uint256[](s_numOfTests);
            s_submitSGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);

            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_consumerExample.requestRandomNumber{value: requestFee}();
                vm.stopPrank();

                uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                if (s_submitCvLength > 0) {
                    s_packedIndices = 0;
                    for (uint256 j; j < s_submitCvLength; j++) {
                        s_packedIndices = s_packedIndices | (j << (j * 8));
                    }
                    vm.startPrank(LEADERNODE);
                    s_commitReveal2.requestToSubmitCv(s_packedIndices);
                    s_requestToSubmitCvGas[i] = vm.lastCallGas().gasTotalUsed;
                    vm.stopPrank();
                }

                for (uint256 j; j < s_submitCvLength; j++) {
                    vm.startPrank(s_activatedOperators[j]);
                    s_commitReveal2.submitCv(s_cvs[j]);
                    if (j == 0) s_submitCvGas[i] = vm.lastCallGas().gasTotalUsed;
                    vm.stopPrank();
                }

                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                vm.stopPrank();

                uint256 k = 0;
                _setParametersForRequestToSubmitS(k, revealOrders);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.requestToSubmitS(
                    s_cos,
                    s_secretsReceivedOffchainInRevealOrder,
                    s_packedVsForAllCvsNotOnChain,
                    s_sigRSsForAllCvsNotOnChain,
                    s_packedRevealOrders
                );
                s_requestToSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                vm.stopPrank();

                for (uint256 j = k; j < s_numOfOperators; j++) {
                    vm.startPrank(s_activatedOperators[revealOrders[j]]);
                    s_commitReveal2.submitS(s_secrets[revealOrders[j]]);
                    if (s_numOfOperators >= 2 && j == s_numOfOperators - 2) {
                        s_submitSGas[i] = vm.lastCallGas().gasTotalUsed;
                    }
                    if (j == s_numOfOperators - 1) s_lastSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                    vm.stopPrank();
                }
            }

            uint256 reqCv = s_submitCvLength > 0 ? s_requestToSubmitCvGas[3] : 0;
            uint256 reqS = s_requestToSubmitSGas[3];
            uint256 sumReq = reqCv + reqS;

            if (sumReq > maxSum) {
                maxSum = sumReq;
                maxReqCv = reqCv;
                maxReqS = reqS;
                maxSubmitCvGas = s_submitCvGas[3];
                maxSubmitSGas = s_submitSGas[3];
                maxLastSubmitSGas = s_lastSubmitSGas[3];
                maxScenarioKey = string.concat(
                    "operators_",
                    bytes(Strings.toString(s_numOfOperators)).length == 1
                        ? string.concat("0", Strings.toString(s_numOfOperators))
                        : Strings.toString(s_numOfOperators),
                    "_submitCv_",
                    bytes(Strings.toString(s_submitCvLength)).length == 1
                        ? string.concat("0", Strings.toString(s_submitCvLength))
                        : Strings.toString(s_submitCvLength)
                );
            }
        }

        string memory gasData = "";
        gasData = vm.serializeUint("max", "requestToSubmitCvGas", maxReqCv);
        gasData = vm.serializeUint("max", "submitCvGas", maxSubmitCvGas);
        gasData = vm.serializeUint("max", "requestToSubmitSGas", maxReqS);
        gasData = vm.serializeUint("max", "submitSGas", maxSubmitSGas);
        gasData = vm.serializeUint("max", "lastSubmitSGas", maxLastSubmitSGas);
        gasData = vm.serializeUint("max", "sumRequestGas", maxSum);

        string memory payload = vm.serializeString("disputeSecretsGas", "scenarioKey", maxScenarioKey);
        payload = vm.serializeString("disputeSecretsGas", "metrics", gasData);
        vm.writeJson(payload, OUTPUT_PATH, ".disputeSecretsGas");
    }
}
