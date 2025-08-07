// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest, console2} from "./../shared/BaseTest.t.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * Three paths
 * 1 -> 5 -> 11 for baseline
 * 1 -> 5 -> 12 -> 13 for participant withholding - 1
 * 1 -> 5 -> 12 -> 15 -> 5 -> 11 for participant withholding - 2
 * 1 -> 5 -> 12 -> 15 -> depositAndActivate() -> resume() -> 5 -> 11 for participant withholding - 3 (when only two operators are active)
 * 1 -> 5 -> 14 -> resume{value: activationThreshold}() -> 5 -> 11 for leader withholding
 */
contract ForManuscriptGas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    uint256[] public s_baselineGas;
    uint256[] public s_participantWithholding1Gas;
    uint256[] public s_participantWithholding2Gas;
    uint256[] public s_participantWithholding3Gas;
    uint256[] public s_leaderWithholdingGas;

    uint256[] public s_submitMerkleRootGas;
    uint256[] public s_requestToSubmitSGas;
    uint256[] public s_submitSGas;
    uint256[] public s_depositAndActivateGas;
    uint256[] public s_resumeGas;
    uint256[] public s_failToSubmitSGas;
    uint256[] public s_submitMerkleRoot2Gas;
    uint256[] public s_generateRandomNumberGas;
    uint256[] public s_failToRequestSorGenerateRandomNumberGas;

    string public s_gasReportPathForManuscript;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 5;

        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAddresses(32);

        string memory root = vm.projectRoot();
        s_gasReportPathForManuscript = string.concat(root, "/output/gasreportForManuscript.json");
        if (!vm.exists(s_gasReportPathForManuscript)) {
            vm.writeFile(s_gasReportPathForManuscript, "{}");
        }
    }

    function _deployContracts() internal {
        // ** Deploy CommitReveal2
        address commitRevealAddress;
        (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).runForTest();
        s_commitReveal2 = CommitReveal2(commitRevealAddress);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();

        s_callbackGas = 90000;
        (
            s_offChainSubmissionPeriod,
            s_requestOrSubmitOrFailDecisionPeriod,
            s_onChainSubmissionPeriod,
            s_offChainSubmissionPeriodPerOperator,
            s_onChainSubmissionPeriodPerOperator
        ) = s_commitReveal2.getPeriods();
    }

    // 1 -> 5 -> 12 -> 13 for participant withholding - 1
    function test_ParticipantWithholding1Gas() public {
        string memory gasOutput;
        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_participantWithholding1Gas = new uint256[](s_numOfTests);
            s_submitMerkleRootGas = new uint256[](s_numOfTests);
            s_requestToSubmitSGas = new uint256[](s_numOfTests);
            s_submitSGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_commitReveal2.requestRandomNumber{value: requestFee}(s_callbackGas);
                vm.stopPrank();
            }

            for (uint256 i; i < s_numOfTests; i++) {
                uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);
                vm.startPrank(LEADERNODE);
                // ** 5. submitMerkleRoot
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;
                s_participantWithholding1Gas[i] = s_submitMerkleRootGas[i];
                vm.stopPrank();

                // ** 12. requestToSubmitS
                uint256 k = s_numOfOperators - 1; // last operator
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
                s_participantWithholding1Gas[i] += s_requestToSubmitSGas[i];
                vm.stopPrank();

                // ** 13. submitS (remaining operators)
                vm.startPrank(s_activatedOperators[revealOrders[k]]);
                s_commitReveal2.submitS(s_secrets[revealOrders[k]]);
                s_submitSGas[i] = vm.lastCallGas().gasTotalUsed;
                s_participantWithholding1Gas[i] += s_submitSGas[i];
                vm.stopPrank();
            }

            // Create scenario key: operators_XX
            string memory scenarioKey = string.concat(
                "operators_",
                bytes(Strings.toString(s_numOfOperators)).length == 1
                    ? string.concat("0", Strings.toString(s_numOfOperators))
                    : Strings.toString(s_numOfOperators)
            );

            // Serialize gas data for this operator count (using index 3 for consistency)
            string memory gasData = "";
            gasData = vm.serializeUint(scenarioKey, "totalGas", _getAverageExceptIndex0(s_participantWithholding1Gas));
            gasData =
                vm.serializeUint(scenarioKey, "submitMerkleRootGas", _getAverageExceptIndex0(s_submitMerkleRootGas));
            gasData =
                vm.serializeUint(scenarioKey, "requestToSubmitSGas", _getAverageExceptIndex0(s_requestToSubmitSGas));
            gasData = vm.serializeUint(scenarioKey, "submitSGas", _getAverageExceptIndex0(s_submitSGas));

            gasOutput = vm.serializeString("scenarios", scenarioKey, gasData);
        }

        string memory finalOutput = vm.serializeString("participantWithholding1Gas", "scenarios", gasOutput);
        finalOutput = vm.serializeString(
            "participantWithholding1Gas",
            "description",
            "Gas usage for participant withholding path 1: 1->5->12->13 by scenario: operators_XX"
        );
        vm.writeJson(finalOutput, s_gasReportPathForManuscript, ".participantWithholding1Gas");
    }

    // 1 -> 5 -> 12 -> 15 -> 5 -> 11 for participant withholding - 2
    function test_ParticipantWithholding2Gas() public {
        string memory gasOutput;

        // ** Test
        for (s_numOfOperators = 3; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_participantWithholding2Gas = new uint256[](s_numOfTests);
            s_submitMerkleRootGas = new uint256[](s_numOfTests);
            s_requestToSubmitSGas = new uint256[](s_numOfTests);
            s_failToSubmitSGas = new uint256[](s_numOfTests);
            s_submitMerkleRoot2Gas = new uint256[](s_numOfTests);
            s_generateRandomNumberGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_commitReveal2.requestRandomNumber{value: requestFee}(s_callbackGas);
                vm.stopPrank();
                uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                // ** 5. submitMerkleRoot (first time)
                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;
                s_participantWithholding2Gas[i] = s_submitMerkleRootGas[i];
                vm.stopPrank();

                // ** 12. requestToSubmitS
                uint256 k = s_numOfOperators - 1; // last operator will not submit
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
                s_participantWithholding2Gas[i] += s_requestToSubmitSGas[i];
                vm.stopPrank();

                address lastOperator = s_activatedOperators[revealOrders[k]];

                // ** 15. failToSubmitS (timeout - participant withholding)
                mine(s_onChainSubmissionPeriodPerOperator);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.failToSubmitS();
                s_failToSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
                s_participantWithholding2Gas[i] += s_failToSubmitSGas[i];
                vm.stopPrank();

                // ** 5. submitMerkleRoot (second time - new round)
                _setSCoCvRevealOrders(s_privateKeys);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRoot2Gas[i] = vm.lastCallGas().gasTotalUsed;
                s_participantWithholding2Gas[i] += s_submitMerkleRoot2Gas[i];
                vm.stopPrank();

                // ** 11. generateRandomNumber (final completion)
                vm.startPrank(LEADERNODE);
                s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                s_generateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
                s_participantWithholding2Gas[i] += s_generateRandomNumberGas[i];
                vm.stopPrank();

                vm.startPrank(lastOperator);
                s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
            }

            // Create scenario key: operators_XX
            string memory scenarioKey = string.concat(
                "operators_",
                bytes(Strings.toString(s_numOfOperators)).length == 1
                    ? string.concat("0", Strings.toString(s_numOfOperators))
                    : Strings.toString(s_numOfOperators)
            );

            // Serialize gas data for this operator count
            string memory gasData = "";
            gasData = vm.serializeUint(scenarioKey, "totalGas", _getAverageExceptIndex0(s_participantWithholding2Gas));
            gasData =
                vm.serializeUint(scenarioKey, "submitMerkleRootGas", _getAverageExceptIndex0(s_submitMerkleRootGas));
            gasData =
                vm.serializeUint(scenarioKey, "requestToSubmitSGas", _getAverageExceptIndex0(s_requestToSubmitSGas));
            gasData = vm.serializeUint(scenarioKey, "failToSubmitSGas", _getAverageExceptIndex0(s_failToSubmitSGas));
            gasData =
                vm.serializeUint(scenarioKey, "submitMerkleRoot2Gas", _getAverageExceptIndex0(s_submitMerkleRoot2Gas));
            gasData = vm.serializeUint(
                scenarioKey, "generateRandomNumberGas", _getAverageExceptIndex0(s_generateRandomNumberGas)
            );

            gasOutput = vm.serializeString("scenarios", scenarioKey, gasData);
        }

        string memory finalOutput = vm.serializeString("participantWithholding2Gas", "scenarios", gasOutput);
        finalOutput = vm.serializeString(
            "participantWithholding2Gas",
            "description",
            "Gas usage for participant withholding path 2: 1->5->12->15->5->11 by scenario: operators_XX"
        );
        vm.writeJson(finalOutput, s_gasReportPathForManuscript, ".participantWithholding2Gas");
    }

    // 1 -> 5 -> 12 -> 15 -> depositAndActivate() -> resume() -> 5 -> 11 for participant withholding - 3 (when only two operators are active)
    function test_ParticipantWithholding3Gas() public {
        string memory gasOutput;

        s_participantWithholding3Gas = new uint256[](s_numOfTests);
        s_submitMerkleRootGas = new uint256[](s_numOfTests);
        s_requestToSubmitSGas = new uint256[](s_numOfTests);
        s_failToSubmitSGas = new uint256[](s_numOfTests);
        s_submitMerkleRoot2Gas = new uint256[](s_numOfTests);
        s_generateRandomNumberGas = new uint256[](s_numOfTests);
        s_depositAndActivateGas = new uint256[](s_numOfTests);
        s_resumeGas = new uint256[](s_numOfTests);

        // ** Test with only 2 operators
        s_numOfOperators = 2;
        _deployContracts();
        _depositAndActivateOperators(s_operatorAddresses);

        uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
        for (uint256 i; i < s_numOfTests; i++) {
            vm.startPrank(s_anyAddress);
            s_commitReveal2.requestRandomNumber{value: requestFee}(s_callbackGas);
            vm.stopPrank();

            uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

            // ** 5. submitMerkleRoot (first time)
            vm.startPrank(LEADERNODE);
            s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
            s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;
            s_participantWithholding3Gas[i] = s_submitMerkleRootGas[i];
            vm.stopPrank();

            // ** 12. requestToSubmitS
            uint256 k = s_numOfOperators - 1; // last operator will not submit
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
            s_participantWithholding3Gas[i] += s_requestToSubmitSGas[i];
            vm.stopPrank();

            address lastOperator = s_activatedOperators[revealOrders[k]];

            // ** 15. failToSubmitS (timeout - participant withholding)
            mine(s_onChainSubmissionPeriodPerOperator);
            vm.startPrank(LEADERNODE);
            s_commitReveal2.failToSubmitS();
            s_failToSubmitSGas[i] = vm.lastCallGas().gasTotalUsed;
            s_participantWithholding3Gas[i] += s_failToSubmitSGas[i];
            vm.stopPrank();

            // ** depositAndActivate() - failed operator re-deposits and activates
            vm.startPrank(lastOperator);
            s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
            s_depositAndActivateGas[i] = vm.lastCallGas().gasTotalUsed;
            s_participantWithholding3Gas[i] += s_depositAndActivateGas[i];
            vm.stopPrank();

            // ** resume() - leader resumes the protocol
            vm.startPrank(LEADERNODE);
            s_commitReveal2.resume();
            s_resumeGas[i] = vm.lastCallGas().gasTotalUsed;
            s_participantWithholding3Gas[i] += s_resumeGas[i];
            vm.stopPrank();

            // ** 5. submitMerkleRoot (second time - new round)
            _setSCoCvRevealOrders(s_privateKeys);
            vm.startPrank(LEADERNODE);
            s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
            s_submitMerkleRoot2Gas[i] = vm.lastCallGas().gasTotalUsed;
            s_participantWithholding3Gas[i] += s_submitMerkleRoot2Gas[i];
            vm.stopPrank();

            // ** 11. generateRandomNumber (final completion)
            vm.startPrank(LEADERNODE);
            s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
            s_generateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
            s_participantWithholding3Gas[i] += s_generateRandomNumberGas[i];
            vm.stopPrank();
        }

        // Create scenario key: operators_02 (fixed to 2 operators)
        string memory scenarioKey = "operators_02";

        // Serialize gas data
        string memory gasData = "";
        gasData = vm.serializeUint(scenarioKey, "totalGas", _getAverageExceptIndex0(s_participantWithholding3Gas));
        gasData = vm.serializeUint(scenarioKey, "submitMerkleRootGas", _getAverageExceptIndex0(s_submitMerkleRootGas));
        gasData = vm.serializeUint(scenarioKey, "requestToSubmitSGas", _getAverageExceptIndex0(s_requestToSubmitSGas));
        gasData = vm.serializeUint(scenarioKey, "failToSubmitSGas", _getAverageExceptIndex0(s_failToSubmitSGas));
        gasData =
            vm.serializeUint(scenarioKey, "depositAndActivateGas", _getAverageExceptIndex0(s_depositAndActivateGas));
        gasData = vm.serializeUint(scenarioKey, "resumeGas", _getAverageExceptIndex0(s_resumeGas));
        gasData = vm.serializeUint(scenarioKey, "submitMerkleRoot2Gas", _getAverageExceptIndex0(s_submitMerkleRoot2Gas));
        gasData =
            vm.serializeUint(scenarioKey, "generateRandomNumberGas", _getAverageExceptIndex0(s_generateRandomNumberGas));

        gasOutput = vm.serializeString("scenarios", scenarioKey, gasData);

        string memory finalOutput = vm.serializeString("participantWithholding3Gas", "scenarios", gasOutput);
        finalOutput = vm.serializeString(
            "participantWithholding3Gas",
            "description",
            "Gas usage for participant withholding path 3: 1->5->12->15->depositAndActivate->resume->5->11 (2 operators only)"
        );
        vm.writeJson(finalOutput, s_gasReportPathForManuscript, ".participantWithholding3Gas");
    }

    // 1 -> 5 -> 14 -> resume{value: activationThreshold}() -> 5 -> 11 for leader withholding
    function test_LeaderWithholdingGas() public {
        string memory gasOutput;

        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);

            // Initialize arrays for this scenario
            s_leaderWithholdingGas = new uint256[](s_numOfTests);
            s_submitMerkleRootGas = new uint256[](s_numOfTests);
            s_failToRequestSorGenerateRandomNumberGas = new uint256[](s_numOfTests);
            s_resumeGas = new uint256[](s_numOfTests);
            s_submitMerkleRoot2Gas = new uint256[](s_numOfTests);
            s_generateRandomNumberGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_commitReveal2.requestRandomNumber{value: requestFee}(s_callbackGas);
                vm.stopPrank();

                _setSCoCvRevealOrders(s_privateKeys);

                // ** 5. submitMerkleRoot
                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;
                s_leaderWithholdingGas[i] = s_submitMerkleRootGas[i];

                // ** 14. failToRequestSorGenerateRandomNumber (leader withholding)
                mine(s_offChainSubmissionPeriod);
                mine(s_offChainSubmissionPeriodPerOperator * s_activatedOperators.length);
                mine(s_requestOrSubmitOrFailDecisionPeriod);
                s_commitReveal2.failToRequestSorGenerateRandomNumber();
                s_failToRequestSorGenerateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
                s_leaderWithholdingGas[i] += s_failToRequestSorGenerateRandomNumberGas[i];

                // ** resume{value: activationThreshold}() - leader resumes with deposit
                s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
                s_resumeGas[i] = vm.lastCallGas().gasTotalUsed;
                s_leaderWithholdingGas[i] += s_resumeGas[i];

                // ** 5. submitMerkleRoot (second time - new round)
                _setSCoCvRevealOrders(s_privateKeys);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRoot2Gas[i] = vm.lastCallGas().gasTotalUsed;
                s_leaderWithholdingGas[i] += s_submitMerkleRoot2Gas[i];

                // ** 11. generateRandomNumber (final completion)
                s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                s_generateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
                s_leaderWithholdingGas[i] += s_generateRandomNumberGas[i];
                vm.stopPrank();
            }

            string memory scenarioKey =
                string.concat("operators_", s_numOfOperators < 10 ? "0" : "", Strings.toString(s_numOfOperators));

            string memory gasData = "";
            gasData = vm.serializeUint(scenarioKey, "totalGas", _getAverageExceptIndex0(s_leaderWithholdingGas));
            gasData =
                vm.serializeUint(scenarioKey, "submitMerkleRootGas", _getAverageExceptIndex0(s_submitMerkleRootGas));
            gasData = vm.serializeUint(
                scenarioKey,
                "failToRequestSorGenerateRandomNumberGas",
                _getAverageExceptIndex0(s_failToRequestSorGenerateRandomNumberGas)
            );
            gasData = vm.serializeUint(scenarioKey, "resumeGas", _getAverageExceptIndex0(s_resumeGas));
            gasData =
                vm.serializeUint(scenarioKey, "submitMerkleRoot2Gas", _getAverageExceptIndex0(s_submitMerkleRoot2Gas));
            gasData = vm.serializeUint(
                scenarioKey, "generateRandomNumberGas", _getAverageExceptIndex0(s_generateRandomNumberGas)
            );

            gasOutput = vm.serializeString("scenarios", scenarioKey, gasData);
        }

        string memory finalOutput = vm.serializeString("leaderWithholdingGas", "scenarios", gasOutput);
        finalOutput = vm.serializeString(
            "leaderWithholdingGas",
            "description",
            "Gas usage for leader withholding path: 1->5->14->resume{value: activationThreshold}->5->11 by scenario: operators_XX"
        );
        vm.writeJson(finalOutput, s_gasReportPathForManuscript, ".leaderWithholdingGas");
    }
}
