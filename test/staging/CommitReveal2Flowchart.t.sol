// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";

// https://excalidraw.com/#json=cx0cU1CsPe7yD29U_Bfq7,BnMMBTvI3eXxp50_ENxAtA
// * 1. requestRandomNumber()
// * 2. requestToSubmitCv()
// * 3. submitCv()
// * 4. failToRequestSubmitCVAndSubmitMerkleRoot()
// * 5. submitMerkleRoot()
// * 6. failToSubmitCv()
// * 7. failToSubmitMerkleRootAfterDispute()
// * 8. requestToSubmitCo()
// * 9. submitCo()
// * 10. failToSubmitCo()
// * 11. generateRandomNumber()
// * 12. requestToSubmitS()
// * 13. submitS()
// * 14. failToRequestSAndGenerateRandomNumber()
// * 15. failToSubmitAllS()
// * 16. generateRandomNumberWhenSomeCvsAreOnChain()
/**
 * All Successful Paths
 * a. 1 -> 5 -> 11
 * b. 1 -> 5 -> 12 -> 13
 * c. 1 -> 5 -> 8 -> 9 -> 16
 * d. 1 -> 5 -> 8 -> 9 -> 12 -> 13
 * e. 1 -> 2 -> 3 -> 5 -> 16
 * f. 1 -> 2 -> 3 -> 5 -> 12 -> 13
 * g. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 16
 * h. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 12 -> 13
 *
 *  All Failure Paths
 * i. 1 -> 4
 * j. 1 -> 2 -> 3 -> 6
 * k. 1 -> 2 -> 6
 * l. 1 -> 2 -> 3 -> 7
 * m. 1 -> 5 -> 8 -> 10
 * n. 1 -> 5 -> 8 -> 9 -> 10
 * o. 1 -> 2 -> 3 -> 5 -> 8 -> 10
 * p. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 10
 * q. 1 -> 5 -> 14
 * r. 1 -> 5 -> 8 -> 9 -> 14
 * s. 1 -> 5 -> 8 -> 9 -> 12 -> 13 -> 15
 * t. 1 -> 5 -> 8 -> 9 -> 12 -> 15
 * u. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 12 -> 15
 * v. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 12 -> 13 -> 15
 * w. 1 -> 5 -> 12 -> 13 -> 15
 */
contract CommitReveal2WithDispute is BaseTest, CommitReveal2Helper {
    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);

        address commitReveal2Address;
        (commitReveal2Address, s_networkHelperConfig) = (new DeployCommitReveal2()).runForTest();
        s_commitReveal2 = CommitReveal2(commitReveal2Address);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
        s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));

        // *** Deposit And Activate
        setOperatorAddresses(10);
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
            vm.stopPrank();
            assertEq(s_commitReveal2.s_depositAmount(s_operatorAddresses[i]), s_activeNetworkConfig.activationThreshold);
            assertEq(s_commitReveal2.s_activatedOperatorIndex1Based(s_operatorAddresses[i]), i + 1);
        }
        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
    }

    function test_allPaths() public {
        // * path a. 1 -> 5 -> 11
        // ** 1. Request Three Times
        s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        console2.log("requestFee", s_requestFee);
        console2.log("activationThreshold", s_activeNetworkConfig.activationThreshold);
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);

        // ** Off-chain: Cvi Submission
        _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 11. generateRandomNumber()
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * b. 1 -> 5 -> 12 -> 13
        // ** Off-chain: Cvi Submission
        uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);
        // ** 12. requestToSubmitS()
        // *** Let's assume the k of 0, 1, 2, 3 submitted their s_secrets off-chain
        // *** The signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index
        // **** In b case, no one submitted the Cvi on-chain, all the signatures are required.
        /// *** We need to send the s_secrets of the k 0, 1, 2, 3 operators
        _setParametersForRequestToSubmitS(4, revealOrders);
        /// *** Finally request to submit the s_secrets
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 13. submitS(), k 4-9 submit their s_secrets
        for (uint256 i = 4; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * c. 1 -> 5 -> 8 -> 9 -> 16
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);
        vm.startPrank(LEADERNODE);

        // ** 5. submitMerkleRoot()
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request operator index 2, 5, 9 to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In c case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [2, 5, 9];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** The operators index 2, 5, 9 submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 11. generateRandomNumber()
        // any operator can generate the random number
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // *** d. 1 -> 5 -> 8 -> 9 -> 16 -> 17
        // ** Request Three more times
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);
        vm.startPrank(LEADERNODE);

        // ** 5. submitMerkleRoot()
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request operator index 3, 7, 8 to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In d case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [7, 8, 3];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** The operators index 3, 7, 8 submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }
        vm.stopPrank();

        // ** 12. requestToSubmitS()
        // *** Let's assume the k of 0, 1, 2, 3, 4, 5 submitted their s_secrets off-chain
        // *** In d case, some(3,7,8) submitted the Cvi on-chain (in submitCo() function), the signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index
        _setParametersForRequestToSubmitS(6, revealOrders);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 13. submitS(), k 6-9 submit their s_secrets
        for (uint256 i = 6; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }

        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** e,f,g,h

        // *  e. 1 -> 2 -> 3 -> 5 -> 16
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 2,3,5,6,7 to submit their cv
        mine(1);
        s_tempArray = [2, 3, 5, 6, 7];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** The operators index 2,3,5,6,7 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 5; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }
        console2.log("wow");

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 16. generateRandomNumberWhenSomeCvsAreOnChain()
        _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain();
        vm.startPrank(LEADERNODE);
        s_commitReveal2.generateRandomNumberWhenSomeCvsAreOnChain(
            s_secrets, s_sigRSsForAllCvsNotOnChain, s_packedVsForAllCvsNotOnChain, s_packedRevealOrders
        );
        mine(1);

        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * f. 1 -> 2 -> 3 -> 5 -> 12 -> 13, round = 5
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,9 to submit their cv
        s_tempArray = [0, 9];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** The operators index 0,9 submit their cv
        vm.stopPrank();
        for (uint256 i; i < s_tempArray.length; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 12. requestToSubmitS()
        // *** Let's assume none of the operators submitted their s_secrets off-chain
        // *** index 0, 9 already submitted their cv on-chain
        _setParametersForRequestToSubmitS(0, revealOrders);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 13. submitS(), k 0-9 submit their s_secrets
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }

        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * g. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 16, round = 6
        // ** 1. Request Three more times
        s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }

        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);
        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,9 to submit their cv
        mine(1);
        s_tempArray = [0, 9];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** The operators index 0,9 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 2; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request everyone to submit their Co
        // *** The indices who already submitted the Cvi on-chain should be appended at the end.
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In g case, some(0,9) submitted the Cvi on-chain (in submitCv() function), the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_activatedOperatorsLength = s_commitReveal2.getActivatedOperators().length;
        s_tempArray = new uint256[](s_activatedOperatorsLength);
        for (uint256 i; i < s_activatedOperatorsLength; i++) {
            s_tempArray[i] = i;
        }
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** Everyone submit their Co
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 16. generateRandomNumberWhenSomeCvsAreOnChain()
        _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain();
        s_commitReveal2.generateRandomNumberWhenSomeCvsAreOnChain(
            s_secrets, s_sigRSsForAllCvsNotOnChain, s_packedVsForAllCvsNotOnChain, s_packedRevealOrders
        );
        mine(1);

        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * h. 1 -> 2 -> 3 -> 5 -> 8 -> 9 -> 12 -> 13
        // ** 2. requestToSubmitCv()
        // *** The leadernode requests everyone to submit their cv
        s_tempArray = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // *** Everyone submit their cv
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.submitCv(s_cvs[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request everyone to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In h case, everyone submitted the Cvi on-chain (in submitCv() function), no s_cvs and signatures are required.
        s_activatedOperatorsLength = s_commitReveal2.getActivatedOperators().length;
        s_tempArray = new uint256[](s_activatedOperatorsLength);
        for (uint256 i; i < s_activatedOperatorsLength; i++) {
            s_tempArray[i] = i;
        }
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** Everyone submit their Co
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 12. requestToSubmitS()
        // *** Let's assume none of the operators submitted their s_secrets off-chain
        // *** everyone submitted their cv on-chain
        _setParametersForRequestToSubmitS(0, revealOrders);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 13. submitS(), k 0-9 submit their s_secrets
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }

        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("s_lastRequestId", s_lastRequestId);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * i. 1 -> 4, round: 8
        // ** 4.
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_currentRound);
        mine(s_activeNetworkConfig.offChainSubmissionPeriod);
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator * s_activatedOperators.length);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);

        vm.deal(s_anyAddress, 10000 ether);
        vm.startPrank(s_anyAddress);
        s_commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot();
        mine(1);
        // *** After the protocol halts, the round can be restarted or the consumer can refund the round.
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("Failed");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // *** let's refund the round 8 and start from round 9
        s_consumerExample.refund(8);
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("Refunded");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("Resumed");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // With currentRound=8, lastFulfilledRound=7, and requestCount=9, let's call requestRandomNumber 3 more times.
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);

        // * j. 1 -> 2 -> 3 -> 6, round: 9
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,2,4,6,8 to submit their cv
        s_tempArray = [0, 2, 4, 6, 8];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** Only the operators index 0, 4 submit their cv
        vm.stopPrank();
        vm.startPrank(s_operatorAddresses[0]);
        s_commitReveal2.submitCv(s_cvs[0]);
        mine(1);
        vm.stopPrank();
        vm.startPrank(s_operatorAddresses[4]);
        s_commitReveal2.submitCv(s_cvs[4]);
        mine(1);
        vm.stopPrank();

        // ** 6. failToSubmitCv(), the operator index 2, 6, 8 fail to submit their cv
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCv();
        mine(1);
        vm.stopPrank();

        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After 2, 6, 8 failToSubmitCv");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * k. 1 -> 2 -> 6, round: 9
        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 0 to submit their cv
        s_tempArray = [0];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** No one submits their cv
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);

        // ** 6. failToSubmitCv(), the operator index 0 fail to submit their cv
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCv();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After 0 failToSubmitCv");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * l. 1 -> 2 -> 3 -> 7, round 9, operatorNum = 6
        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 1, 3, 5 to submit their cv
        s_tempArray = [1, 3, 5];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** The operators index 1, 3, 5 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 7. failToSubmitMerkleRootAfterDispute()
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(s_operatorAddresses[0]);
        s_commitReveal2.failToSubmitMerkleRootAfterDispute();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitMerkleRootAfterDispute");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** let's resume the round 9
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * m. 1 -> 5 -> 8 -> 10, round: 9, operatorNum = 6
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request operator index 2, 3 to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In m case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [2, 3];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. failToSubmitCo()
        // *** The operators index 2, 3 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();

        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitCo");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * n. 1 -> 5 -> 8 -> 9 -> 10, operatorNum = 4
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request all the operators to submit their Co
        s_activatedOperatorsLength = s_commitReveal2.getActivatedOperators().length;
        s_tempArray = new uint256[](s_activatedOperatorsLength);
        for (uint256 i; i < s_activatedOperatorsLength; i++) {
            s_tempArray[i] = i;
        }
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** index 1, 2, 3 submit their Co
        vm.stopPrank();
        for (uint256 i = 1; i < 4; i++) {
            vm.startPrank(s_activatedOperators[i]);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 10. failToSubmitCo()
        // *** The operator index 0 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitCo");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * o. 1 -> 2 -> 3 -> 5 -> 8 -> 10, operatorNum = 3

        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,1,2 to submit their cv
        s_tempArray = [0, 1, 2];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** The operators index 0, 1, 2 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request all the operators to submit their Co
        s_activatedOperatorsLength = s_commitReveal2.getActivatedOperators().length;
        s_tempArray = new uint256[](s_activatedOperatorsLength);
        for (uint256 i; i < s_activatedOperatorsLength; i++) {
            s_tempArray[i] = i;
        }
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. failToSubmitCo()
        // *** The operator index 0, 1, 2 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();

        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitCo");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * p. 1 -> 5 -> 3 -> 5 -> 8 -> 9 -> 10, operatorNum = 0
        // ** Let's withdraw all
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.withdraw();
            mine(1);
            vm.stopPrank();
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.withdraw();
        mine(1);
        vm.stopPrank();

        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After Some Withdraw");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );
        // ** 10 operators deposit and activate
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            if (s_commitReveal2.s_depositAmount(s_operatorAddresses[i]) < s_activeNetworkConfig.activationThreshold) {
                s_commitReveal2.deposit{
                    value: s_activeNetworkConfig.activationThreshold
                        - s_commitReveal2.s_depositAmount(s_operatorAddresses[i])
                }();
            }
            s_commitReveal2.activate();
            mine(1);
            vm.stopPrank();
        }

        // ** operator resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,1,2 to submit their cv
        s_tempArray = [0, 1, 2];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 3. submitCv()
        // *** The operators index 0,1,2 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request [0,1,2, 3, 4, 5] to submit their Co
        // *** 0,1,2 submitted their cv on-chain
        s_tempArray = [0, 1, 2, 3, 4, 5];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** only index 3,4 submit their Co
        vm.stopPrank();
        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 10. failToSubmitCo()
        // *** The operator index 5 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitCo");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * q. 1 -> 5 -> 14
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 14. failToRequestSOrGenerateRandomNumber()
        mine(s_activeNetworkConfig.offChainSubmissionPeriod);
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator * s_activatedOperators.length);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToRequestSorGenerateRandomNumber();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToRequestSOrGenerateRandomNumber");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * r. 1 -> 5 -> 8 -> 9 -> 14
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request [0, 3] to submit their Co
        s_tempArray = [0, 3];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** index 0, 3 submit their Co
        vm.stopPrank();
        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 14. failToRequestSOrGenerateRandomNumber()
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator * s_activatedOperators.length);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToRequestSorGenerateRandomNumber();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToRequestSOrGenerateRandomNumber");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * s. 1 -> 5 -> 8 -> 9 -> 12 -> 13 -> 15
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request [1, 2, 3] to submit their Co
        s_tempArray = [1, 2, 3];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** index [1, 2, 3] submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 12. requestToSubmitS()
        // *** Let's assume only k 0, 1 submitted their s_secrets off-chain
        // *** [1, 2, 3] submitted their cv on-chain
        _setParametersForRequestToSubmitS(2, revealOrders);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 13. submitS(), k 2 - 3 submit their s_secrets, 4 - 5 fail to submit their s_secrets
        for (uint256 i = 2; i < 4; i++) {
            vm.startPrank(s_activatedOperators[revealOrders[i]]);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 15. failToSubmitS()
        mine(s_activeNetworkConfig.onChainSubmissionPeriodPerOperator);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitS();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitS");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * t. 1 -> 5 -> 8 -> 9 -> 12 -> 15
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 8. requestToSubmitCo()
        // *** Let's request [0, 1, 2, 3, 4] to submit their Co
        s_tempArray = [0, 1, 2, 3, 4];
        _setParametersForRequestToSubmitCo(s_tempArray);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 9. submitCo()
        // *** index [0, 1, 2, 3, 4] submit their Co
        vm.stopPrank();
        for (uint256 i; i < 5; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 12. requestToSubmitS()
        // *** Let's assume no one submitted their s_secrets off-chain
        // *** [0, 1, 2, 3, 4] submitted their cv on-chain
        _setParametersForRequestToSubmitS(0, revealOrders);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 15. failToSubmitS()
        mine(s_activeNetworkConfig.onChainSubmissionPeriodPerOperator);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitS();
        mine(1);
        vm.stopPrank();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After failToSubmitS");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * 1 -> 5 -> 11
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 5. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 11. generateRandomNumber()
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        s_lastRequestId = s_consumerExample.lastRequestId();
        (s_fulfilled,) = s_consumerExample.s_requests(s_lastRequestId);
        assertEq(s_fulfilled, true);
        console2.log("\nRound", s_currentRound, "trialNum", s_currentTrialNum);
        console2.log("After generateRandomNumber");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );
    }
}
