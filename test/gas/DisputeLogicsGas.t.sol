// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DisputeLogicsGas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    uint256[] public s_requestToSubmitCvGas;
    uint256[] public s_submitCvGas;
    uint256[] public s_requestToSubmitCoGas;
    uint256[] public s_submitCoGas;
    uint256[] public s_requestToSubmitSGas;
    uint256[] public s_lastSubmitSGas;
    uint256[] public s_submitSGas;
    uint256[] public s_reRequestToSubmitSGas;
    uint256[] public s_generateRandomNumberWhenSomeCvsAreOnChainGas;

    uint256 public s_submitCvLength;
    uint256 public s_submitCoLength;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 4;
        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAddresses(32);
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

    // ** Path: 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 16
    // ** requestRandomNumber -> requestToSubmitCv -> submitCv -> submitMerkleRoot -> requestToSubmitCo -> submitCo -> generateRandomNumberWhenSomeCvsAreOnChain
    function test_disputeCvCoGenerateRandomNumberWhenSomeCvsAreOnChainGas() public {
        string memory submitCvGasOutput;
        string memory submitCoGasOutput;

        for (s_numOfOperators = 2; s_numOfOperators <= 7; s_numOfOperators++) {
            submitCvGasOutput = "";
            for (s_submitCvLength = 0; s_submitCvLength <= s_numOfOperators; s_submitCvLength++) {
                submitCoGasOutput = "";
                for (s_submitCoLength = 0; s_submitCoLength <= s_numOfOperators; s_submitCoLength++) {
                    _deployContracts();
                    _depositAndActivateOperators(s_operatorAddresses);

                    // Initialize gas arrays
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

                        // ** 2. requestToSubmitCv (if any)
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

                        // ** 3. submitCv (actual submissions)
                        for (uint256 j; j < s_submitCvLength; j++) {
                            vm.startPrank(s_activatedOperators[j]);
                            s_commitReveal2.submitCv(s_cvs[j]);
                            if (j == 0) s_submitCvGas[i] = vm.lastCallGas().gasTotalUsed; // Only measure first one
                            vm.stopPrank();
                        }

                        // ** 5. submitMerkleRoot
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                        vm.stopPrank();

                        // ** 8. requestToSubmitCo (if any)
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

                        // ** 9. submitCo (actual submissions)
                        for (uint256 j; j < s_submitCoLength; j++) {
                            vm.startPrank(s_activatedOperators[j]);
                            s_commitReveal2.submitCo(s_cos[j]);
                            if (j == 0) s_submitCoGas[i] = vm.lastCallGas().gasTotalUsed; // Only measure first one
                            vm.stopPrank();
                        }

                        // ** 16. generateRandomNumberWhenSomeCvsAreOnChain
                        if (s_submitCvLength > 0 || s_submitCoLength > 0) {
                            _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain();
                            s_commitReveal2.generateRandomNumberWhenSomeCvsAreOnChain(
                                s_secrets,
                                s_sigRSsForAllCvsNotOnChain,
                                s_packedVsForAllCvsNotOnChain,
                                s_packedRevealOrders
                            );
                            s_generateRandomNumberWhenSomeCvsAreOnChainGas[i] = vm.lastCallGas().gasTotalUsed;
                        } else {
                            // 11. generateRandomNumber
                            s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                        }
                    }

                    // Create scenario key: operators_XX_submitCv_YY_submitCo_ZZ
                    string memory scenarioKey = string.concat(
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

                    // Serialize gas data for this combination
                    string memory gasData = "";
                    if (s_submitCvLength > 0) {
                        gasData = vm.serializeUint(scenarioKey, "requestToSubmitCvGas", s_requestToSubmitCvGas[3]);
                        gasData = vm.serializeUint(scenarioKey, "submitCvGas", s_submitCvGas[3]);
                    }
                    if (s_submitCoLength > 0) {
                        gasData = vm.serializeUint(scenarioKey, "requestToSubmitCoGas", s_requestToSubmitCoGas[3]);
                        gasData = vm.serializeUint(scenarioKey, "submitCoGas", s_submitCoGas[3]);
                    }
                    if (s_submitCvLength > 0 || s_submitCoLength > 0) {
                        gasData = vm.serializeUint(
                            scenarioKey,
                            "generateRandomNumberWhenSomeCvsAreOnChainGas",
                            s_generateRandomNumberWhenSomeCvsAreOnChainGas[3]
                        );
                    }

                    submitCoGasOutput = vm.serializeString("scenarios", scenarioKey, gasData);
                }
            }
        }

        string memory finalOutput = vm.serializeString("disputeCvCoGas", "scenarios", submitCoGasOutput);
        finalOutput = vm.serializeString(
            "disputeCvCoGas",
            "description",
            "Path 1->2->3->5->8->9->16. Scaling: requestToSubmitCv uses packedIndices with YY indices; submitCv runs YY txs; requestToSubmitCo sets indicesLength=ZZ and passes CvAndSigRS[] only for requested indices whose Cv is not on-chain (size = notOnChainAmongZZ) with packedVs sized to that count; generateRandomNumberWhenSomeCvsAreOnChain uses allSecrets[N], SigRS[] of length (N - onChainCvCount), and packedVs sized likewise. Gas increases with N, YY, ZZ and with how many Cvs remain off-chain."
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".disputeCvCoGas");
    }

    // ** Path: 1 -> 2 -> 3 -> 5 -> 12 -> 13
    // ** requestRandomNumber -> requestToSubmitCv -> submitCv -> submitMerkleRoot -> requestToSubmitS(k sweep) -> submitS(k)
    function test_requestToSubmitSGas() public {
        string memory submitCvGasOutput;

        for (s_numOfOperators = 2; s_numOfOperators <= 7; s_numOfOperators++) {
            submitCvGasOutput = "";
            for (s_submitCvLength = 0; s_submitCvLength <= s_numOfOperators; s_submitCvLength++) {
                _deployContracts();
                _depositAndActivateOperators(s_operatorAddresses);

                uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);

                // Sweep k immediately under submitCvLength loop
                for (uint256 k; k < s_numOfOperators; k++) {
                    // Initialize gas arrays per k sweep
                    s_requestToSubmitCvGas = new uint256[](s_numOfTests);
                    s_submitCvGas = new uint256[](s_numOfTests);
                    s_requestToSubmitSGas = new uint256[](s_numOfTests);
                    s_lastSubmitSGas = new uint256[](s_numOfTests);
                    s_submitSGas = new uint256[](s_numOfTests);

                    for (uint256 i; i < s_numOfTests; i++) {
                        vm.startPrank(s_anyAddress);
                        s_consumerExample.requestRandomNumber{value: requestFee}();
                        vm.stopPrank();

                        uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                        // ** 2. requestToSubmitCv (if any)
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

                        // ** 3. submitCv (actual submissions)
                        for (uint256 j; j < s_submitCvLength; j++) {
                            vm.startPrank(s_activatedOperators[j]);
                            s_commitReveal2.submitCv(s_cvs[j]);
                            if (j == 0) s_submitCvGas[i] = vm.lastCallGas().gasTotalUsed; // Only measure first one
                            vm.stopPrank();
                        }

                        // ** 5. submitMerkleRoot
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                        vm.stopPrank();

                        // ** 12-13. requestToSubmitS(k) then submitS(k), finalize round if k != last
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

                        vm.startPrank(s_activatedOperators[revealOrders[k]]);
                        s_commitReveal2.submitS(s_secrets[revealOrders[k]]);
                        if (s_numOfOperators >= 2 && k == s_numOfOperators - 2) {
                            s_submitSGas[i] = vm.lastCallGas().gasTotalUsed;
                        }
                        if (k == s_numOfOperators - 1) {
                            s_lastSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                        }
                        vm.stopPrank();

                        if (k != s_numOfOperators - 1) {
                            _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain();
                            s_commitReveal2.generateRandomNumberWhenSomeCvsAreOnChain(
                                s_secrets,
                                s_sigRSsForAllCvsNotOnChain,
                                s_packedVsForAllCvsNotOnChain,
                                s_packedRevealOrders
                            );
                        }
                    }

                    // Create scenario key: operators_XX_submitCv_YY_k_ZZ
                    string memory scenarioKey = string.concat(
                        "operators_",
                        bytes(Strings.toString(s_numOfOperators)).length == 1
                            ? string.concat("0", Strings.toString(s_numOfOperators))
                            : Strings.toString(s_numOfOperators),
                        "_submitCv_",
                        bytes(Strings.toString(s_submitCvLength)).length == 1
                            ? string.concat("0", Strings.toString(s_submitCvLength))
                            : Strings.toString(s_submitCvLength),
                        "_k_",
                        bytes(Strings.toString(k)).length == 1
                            ? string.concat("0", Strings.toString(k))
                            : Strings.toString(k)
                    );

                    // Serialize gas data for this k combination
                    string memory gasData = "";
                    if (s_submitCvLength > 0) {
                        gasData = vm.serializeUint(scenarioKey, "requestToSubmitCvGas", s_requestToSubmitCvGas[3]);
                        gasData = vm.serializeUint(scenarioKey, "submitCvGas", s_submitCvGas[3]);
                    }
                    gasData = vm.serializeUint(scenarioKey, "requestToSubmitSGas", s_requestToSubmitSGas[3]);
                    gasData = vm.serializeUint(scenarioKey, "submitSGas", s_submitSGas[3]);
                    gasData = vm.serializeUint(scenarioKey, "lastSubmitSGas", s_lastSubmitSGas[3]);

                    submitCvGasOutput = vm.serializeString("scenarios", scenarioKey, gasData);
                }
            }
        }

        string memory finalOutput = vm.serializeString("disputeSecretsGas", "scenarios", submitCvGasOutput);
        finalOutput = vm.serializeString(
            "disputeSecretsGas",
            "description",
            "Path 1->2->3->5->12->13. Scaling by k (_k_ZZ): requestToSubmitS consumes secretsReceivedOffchainInRevealOrder of length ZZ, derived from reveal order prefix; SigRS[] and packedVs are constructed only for operators whose Cv is not on-chain, so their lengths equal (N - onChainCvCount). submitS per k touches storage for that operator and enforces reveal-order checks. Gas grows with ZZ and with how many Cvs remain off-chain."
        );
        vm.writeJson(finalOutput, s_gasReportPath, ".disputeSecretsGas");
    }

    // ** Path: 1 -> 2 -> 3 -> 5 -> (12 at k=0) -> reRequestToSubmitS(k in 1..n-1) -> submitS(k)
    function test_reRequestToSubmitSecretsGas() public {
        string memory submitCvGasOutput;

        for (s_numOfOperators = 2; s_numOfOperators <= 7; s_numOfOperators++) {
            submitCvGasOutput = "";
            for (s_submitCvLength = 0; s_submitCvLength <= s_numOfOperators; s_submitCvLength++) {
                _deployContracts();
                _depositAndActivateOperators(s_operatorAddresses);

                // Initialize gas arrays
                s_requestToSubmitCvGas = new uint256[](s_numOfTests);
                s_submitCvGas = new uint256[](s_numOfTests);
                s_requestToSubmitSGas = new uint256[](s_numOfTests);
                s_lastSubmitSGas = new uint256[](s_numOfTests);
                s_submitSGas = new uint256[](s_numOfTests);
                s_reRequestToSubmitSGas = new uint256[](s_numOfTests);

                uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);

                for (uint256 i; i < s_numOfTests; i++) {
                    vm.startPrank(s_anyAddress);
                    s_consumerExample.requestRandomNumber{value: requestFee}();
                    vm.stopPrank();

                    uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                    // ** 2. requestToSubmitCv (if any)
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

                    // ** 3. submitCv (actual submissions)
                    for (uint256 j; j < s_submitCvLength; j++) {
                        vm.startPrank(s_activatedOperators[j]);
                        s_commitReveal2.submitCv(s_cvs[j]);
                        if (j == 0) s_submitCvGas[i] = vm.lastCallGas().gasTotalUsed; // Only measure first one
                        vm.stopPrank();
                    }

                    // ** 5. submitMerkleRoot
                    vm.startPrank(LEADERNODE);
                    s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                    vm.stopPrank();

                    // ** Initial request at k=0 (not measured here)
                    _setParametersForRequestToSubmitS(0, revealOrders);
                    vm.startPrank(LEADERNODE);
                    s_commitReveal2.requestToSubmitS(
                        s_cos,
                        s_secretsReceivedOffchainInRevealOrder,
                        s_packedVsForAllCvsNotOnChain,
                        s_sigRSsForAllCvsNotOnChain,
                        s_packedRevealOrders
                    );
                    vm.stopPrank();
                    vm.startPrank(s_activatedOperators[revealOrders[0]]);
                    s_commitReveal2.submitS(s_secrets[revealOrders[0]]);
                    vm.stopPrank();

                    // ** 12-13. Sweep reRequestToSubmitS(k) for k in [1, n-1]
                    for (uint256 k = 1; k < s_numOfOperators; k++) {
                        _setParametersForReRequestToSubmitS(k, revealOrders);
                        vm.startPrank(LEADERNODE);
                        s_commitReveal2.reRequestToSubmitS(s_secretsReceivedOffchainInRevealOrder);
                        s_reRequestToSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                        vm.stopPrank();

                        vm.startPrank(s_activatedOperators[revealOrders[k]]);
                        s_commitReveal2.submitS(s_secrets[revealOrders[k]]);
                        if (s_numOfOperators >= 2 && k == s_numOfOperators - 2) {
                            s_submitSGas[i] = vm.lastCallGas().gasTotalUsed;
                        }
                        if (k == s_numOfOperators - 1) {
                            s_lastSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                        }
                        vm.stopPrank();

                        // Serialize per-k: operators_XX_submitCv_YY_k_ZZ
                        string memory scenarioKey = string.concat(
                            "operators_",
                            bytes(Strings.toString(s_numOfOperators)).length == 1
                                ? string.concat("0", Strings.toString(s_numOfOperators))
                                : Strings.toString(s_numOfOperators),
                            "_submitCv_",
                            bytes(Strings.toString(s_submitCvLength)).length == 1
                                ? string.concat("0", Strings.toString(s_submitCvLength))
                                : Strings.toString(s_submitCvLength),
                            "_k_",
                            bytes(Strings.toString(k)).length == 1
                                ? string.concat("0", Strings.toString(k))
                                : Strings.toString(k)
                        );

                        string memory gasData = "";
                        if (s_submitCvLength > 0) {
                            gasData = vm.serializeUint(scenarioKey, "requestToSubmitCvGas", s_requestToSubmitCvGas[3]);
                            gasData = vm.serializeUint(scenarioKey, "submitCvGas", s_submitCvGas[3]);
                        }
                        gasData = vm.serializeUint(scenarioKey, "reRequestToSubmitSGas", s_reRequestToSubmitSGas[3]);
                        // Only populate submitSGas/lastSubmitSGas at their specific ks
                        if (s_numOfOperators >= 2 && k == s_numOfOperators - 2) {
                            gasData = vm.serializeUint(scenarioKey, "submitSGas", s_submitSGas[3]);
                        }
                        if (k == s_numOfOperators - 1) {
                            gasData = vm.serializeUint(scenarioKey, "lastSubmitSGas", s_lastSubmitSGas[3]);
                        }

                        submitCvGasOutput = vm.serializeString("scenarios", scenarioKey, gasData);
                    }
                }
            }

            string memory finalOutput2 =
                vm.serializeString("disputeSecretsReRequestGas", "scenarios", submitCvGasOutput);
            finalOutput2 = vm.serializeString(
                "disputeSecretsReRequestGas",
                "description",
                "Path 1->2->3->5->12->13. Scaling by k (_k_ZZ): reRequestToSubmitS advances the reveal index and only passes the newly known secrets since the previous k, so secretsReceivedOffchainInRevealOrder length equals (ZZ - prevK). Storage and reveal-order checks are limited to the current k. Gas increases with ZZ and with remaining off-chain Cvs."
            );
            vm.writeJson(finalOutput2, s_gasReportPath, ".disputeSecretsReRequestGas");
        }
    }
}
