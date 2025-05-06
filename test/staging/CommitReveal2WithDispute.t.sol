// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2, Vm} from "forge-std/Test.sol";
import {Sort} from "./../shared/Sort.sol";
import {CommitReveal2Helper, CommitReveal2Storage} from "./../shared/CommitReveal2Helper.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";

contract CommitReveal2WithDispute is BaseTest, CommitReveal2Helper {
    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);

        vm.stopPrank();
        address commitReveal2Address;
        (commitReveal2Address, s_networkHelperConfig) = (new DeployCommitReveal2()).run();
        s_commitReveal2 = CommitReveal2(commitReveal2Address);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();

        s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));

        // *** Deposit And Activate
        setOperatorAdresses(10);
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

    // * 1. requestRandomNumber()
    // * 2. submitMerkleRoot()
    // * 3. requestToSubmitCv()
    // * 4. submitCv()
    // * 5. failToRequestSubmitCVAndSubmitMerkleRoot()
    // * 6. submitMerkleRoot()
    // * 7. failToSubmitCv()
    // * 8. failToSubmitMerkleRootAfterDispute()
    // * 9. requestToSubmitCo()
    // * 10. submitCo()
    // * 11. failToSubmitCo()
    // * 12. generateRandomNumber()
    // * 13. requestToSubmitS()
    // * 14. submitS()
    // * 15. failToRequestSAndGenerateRandomNumber()
    // * 16. failToSubmitAllS()

    /**
     * All Successful Paths
     * a. 1 -> 2 -> 12
     * b. 1 -> 2 -> 13 -> 14
     * c. 1 -> 2 -> 9 -> 10 -> 12
     * d. 1 -> 2 -> 9 -> 10 -> 13 -> 14
     * e. 1 -> 3 ->4 -> 6 -> 12
     * f. 1 -> 3 ->4 -> 6 -> 13 -> 14
     * g. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 12
     * h. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 13 -> 14
     *
     *  All Failure Paths
     * i. 1 -> 5
     * j. 1 -> 3 -> 4 -> 7
     * k. 1 -> 3 -> 7
     * l. 1 -> 3 -> 4-> 8
     * m. 1 -> 2 -> 9 -> 11
     * n. 1 -> 2 -> 9 -> 10 -> 11
     * o. 1 -> 3 -> 4 -> 6 -> 9 -> 11
     * p. 1 -> 3 -> 4 -> 6 -> 9 -> 10 -> 11
     * q. 1 -> 2 -> 15
     * r. 1 -> 2 -> 9 -> 10 -> 15
     * s. 1 -> 2 -> 9 -> 10 -> 13 -> 14 -> 16
     * t. 1 -> 2 -> 9 -> 10 -> 13  -> 16
     */
    function test_allPaths() public {
        // ** a,b,c,d,e,f
        // * a. 1 -> 2 -> 12
        // ** 1. Request Three Times
        mine(1);
        s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        console2.log("requestFee", s_requestFee);
        mine(1);
        vm.recordLogs();
        mine(1);
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);

        // ** Off-chain: Cvi Submission
        _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(0);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * b. 1 -> 2 -> 13 -> 14
        // ** Off-chain: Cvi Submission
        uint256[] memory revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);
        // ** 13. requestToSubmitS()
        // *** Let's assume the k of 0, 1, 2, 3 submitted their s_secrets off-chain

        // *** The signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index
        // **** In b case, no one submitted the Cvi on-chain, all the signatures are required.
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](10);
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[i];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[i];
        }
        /// *** We need to send the s_secrets of the k 0, 1, 2, 3 operators
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](4);
        for (uint256 i; i < 4; i++) {
            s_secretsReceivedOffchainInRevealOrder[i] = s_secrets[revealOrders[i]];
        }
        /// *** Finally request to submit the s_secrets
        mine(1);
        s_commitReveal2.requestToSubmitS(
            s_cos, s_secretsReceivedOffchainInRevealOrder, s_packedVs, s_sigRSsForAllCvsNotOnChain, s_packedRevealOrders
        );
        mine(1);

        // ** 14. submitS(), k 4-9 submit their s_secrets
        for (uint256 i = 4; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(1);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * c. 1 -> 2 -> 9 -> 10 -> 12, round: 2
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);
        vm.startPrank(LEADERNODE);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 2, 5, 9 to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In c case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [2, 5, 9];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](3);
        s_tempVs = new uint256[](3);
        s_indicesLength = s_tempArray.length;
        for (uint256 i; i < 3; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain = _packArrayIntoUint256(s_tempArray);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** The operators index 2, 5, 9 submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 12. generateRandomNumber()
        mine(1);
        // any operator can generate the random number
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(s_commitReveal2.s_currentRound());
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // *** d. 1 -> 2 -> 9 -> 10 -> 13 -> 14
        // ** Request Three more times
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);
        vm.startPrank(LEADERNODE);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 3, 7, 8 to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In d case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [7, 8, 3];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_tempArray.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain = _packArrayIntoUint256(s_tempArray);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** The operators index 3, 7, 8 submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }
        vm.stopPrank();

        // ** 13. requestToSubmitS()
        // *** Let's assume the k of 0, 1, 2, 3, 4, 5 submitted their s_secrets off-chain

        // *** In d case, some(3,7,8) submitted the Cvi on-chain (in submitCo() function), the signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index
        s_tempArray = [0, 1, 2, 4, 5, 6, 9];

        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        s_packedVsForAllCvsNotOnChain = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (s_tempArray[i] * 8));
        }
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](6);
        for (uint256 i; i < 6; i++) {
            s_secretsReceivedOffchainInRevealOrder[i] = s_secrets[revealOrders[i]];
        }
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 14. submitS(), k 6-9 submit their s_secrets
        for (uint256 i = 6; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(3);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** e,f,g,h

        // *  e. 1 -> 3 ->4 -> 6 -> 12
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 3. requestToSubmitCv()
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

        // ** 4. submitCv()
        // *** The operators index 2,3,5,6,7 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 5; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(4);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * f. 1 -> 3 ->4 -> 6 -> 13 -> 14, round = 5
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 3. requestToSubmitCv()
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

        // ** 4. submitCv()
        // *** The operators index 0,9 submit their cv
        vm.stopPrank();
        for (uint256 i; i < s_tempArray.length; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 13. requestToSubmitS()
        // *** Let's assume none of the operators submitted their s_secrets off-chain
        // *** index 0, 9 already submitted their cv on-chain
        s_tempArray = [1, 2, 3, 4, 5, 6, 7, 8];
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        s_packedVsForAllCvsNotOnChain = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (s_tempArray[i] * 8));
        }
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](0);
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 14. submitS(), k 0-9 submit their s_secrets
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(5);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * g. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 12, round = 6
        // ** 1. Request Three more times
        s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }

        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);
        // ** 3. requestToSubmitCv()
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

        // ** 4. submitCv()
        // *** The operators index 0,9 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 2; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request everyone to submit their Co
        // *** The indices who already submitted the Cvi on-chain should be appended at the end.
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In g case, some(0,9) submitted the Cvi on-chain (in submitCv() function), the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [1, 2, 3, 4, 5, 6, 7, 8, 0, 9];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_tempArray.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain = _packArrayIntoUint256(s_tempArray);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** Everyone submit their Co
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(6);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * h. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 13 -> 14
        // ** 3. requestToSubmitCv()
        // *** The leadernode requests everyone to submit their cv
        mine(1);
        s_tempArray = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 4. submitCv()
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // *** Everyone submit their cv
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.submitCv(s_cvs[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request everyone to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In h case, everyone submitted the Cvi on-chain (in submitCv() function), no s_cvs and signatures are required.
        s_tempArray = new uint256[](0); // cvs not on-chain
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** Everyone submit their Co
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 13. requestToSubmitS()
        // *** Let's assume none of the operators submitted their s_secrets off-chain
        // *** everyone submitted their cv on-chain
        s_tempArray = new uint256[](0); // secrets received off-chain
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        s_packedVsForAllCvsNotOnChain = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (s_tempArray[i] * 8));
        }
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](0);
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 14. submitS(), k 0-9 submit their s_secrets
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.startPrank(s_operatorAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(7);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * i. 1 -> 5, round: 8
        // ** 5.
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(8);
        // ** s_offChainSubmissionPeriod passed
        mine(s_activeNetworkConfig.offChainSubmissionPeriod);
        // ** s_requestOrSubmitOrFailDecisionPeriod passed
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);

        vm.deal(s_anyAddress, 10000 ether);
        vm.startPrank(s_anyAddress);
        s_commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot();
        mine(1);
        // *** After the protocol halts, the round can be restarted or the consumer can refund the round.

        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // *** let's refund the round 8 and start from round 9
        s_consumerExample.refund(8);
        mine(1);
        vm.stopPrank();
        console2.log("after refund");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // With currentRound=8, lastFulfilledRound=7, and requestCount=9, let's call requestRandomNumber 3 more times.

        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * j. 1 -> 3 -> 4 -> 7, round: 9
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,2,4,6,8 to submit their cv
        mine(1);
        s_tempArray = [0, 2, 4, 6, 8];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 4. submitCv()
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

        // ** 7. failToSubmitCv(), the operator index 2, 6, 8 fail to submit their cv
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCv();
        mine(1);
        vm.stopPrank();

        console2.log("After 2, 6, 8 failToSubmitCv");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * k. 1 -> 3 -> 7, round: 9
        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0 to submit their cv
        mine(1);
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

        // ** 7. failToSubmitCv(), the operator index 0 fail to submit their cv
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCv();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * l. 1 -> 3 -> 4 -> 8, round 9, operatorNum = 6
        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 1, 3, 5 to submit their cv
        mine(1);
        s_tempArray = [1, 3, 5];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 1, 3, 5 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 8. failToSubmitMerkleRootAfterDispute()
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(s_operatorAddresses[0]);
        s_commitReveal2.failToSubmitMerkleRootAfterDispute();
        mine(1);
        vm.stopPrank();

        // ** let's resume the round 9
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * m. 1 -> 2 -> 9 -> 11, round: 9, operatorNum = 6
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 2, 3 to submit their Co
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In m case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [2, 3];
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [2, 3];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 11. failToSubmitCo()
        // *** The operators index 2, 3 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();

        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * n. 1 -> 2 -> 9 -> 10 -> 11, operatorNum = 4
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request all the operators to submit their Co
        s_tempArray = [0, 1, 2, 3];
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [0, 1, 2, 3];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** index 1, 2, 3 submit their Co
        vm.stopPrank();
        for (uint256 i = 1; i < 4; i++) {
            vm.startPrank(s_activatedOperators[i]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 11. failToSubmitCo()
        // *** The operator index 0 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * o. 1 -> 3 -> 4 -> 6 -> 9 -> 11, operatorNum = 3

        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,1,2 to submit their cv
        mine(1);
        s_tempArray = [0, 1, 2];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 0, 1, 2 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request all the operators to submit their Co
        s_tempArray = [0, 1, 2];
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [0, 1, 2];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 11. failToSubmitCo()
        // *** The operator index 0, 1, 2 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();

        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * p. 1 -> 3 -> 4 -> 6 -> 9 -> 10 -> 11, operatorNum = 0
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

        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,1,2 to submit their cv
        mine(1);
        s_tempArray = [0, 1, 2];
        s_indicesLength = s_tempArray.length;
        s_packedIndices = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_packedIndices = s_packedIndices | (s_tempArray[i] << (i * 8));
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_packedIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 0,1,2 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [0,1,2, 3, 4, 5] to submit their Co
        // *** 0,1,2 submitted their cv on-chain
        s_tempArray = [3, 4, 5]; // cvs not on chain
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [3, 4, 5, 0, 1, 2];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** only index 3,4 submit their Co
        vm.stopPrank();
        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 11. failToSubmitCo()
        // *** The operator index 5 fail to submit their Co
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCo();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * q. 1 -> 2 -> 15
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 15. failToRequestSOrGenerateRandomNumber()
        mine(s_activeNetworkConfig.offChainSubmissionPeriod);
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator * s_activatedOperators.length);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToRequestSorGenerateRandomNumber();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * r. 1 -> 2 -> 9 -> 10 -> 15
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [0, 3] to submit their Co
        s_tempArray = [0, 3];
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [0, 3];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** index 0, 3 submit their Co
        vm.stopPrank();
        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 15. failToRequestSOrGenerateRandomNumber()
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator * s_activatedOperators.length);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToRequestSorGenerateRandomNumber();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // ** resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * s. 1 -> 2 -> 9 -> 10 -> 13 -> 14 -> 16
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [1, 2, 3] to submit their Co
        s_tempArray = [1, 2, 3];
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [1, 2, 3];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** index [1, 2, 3] submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 13. requestToSubmitS()
        // *** Let's assume only k 0, 1 submitted their s_secrets off-chain
        // *** [1, 2, 3] submitted their cv on-chain
        s_tempArray = [0, 4, 5]; // s_cvs not on chain
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        s_packedVsForAllCvsNotOnChain = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (s_tempArray[i] * 8));
        }
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](2);
        for (uint256 i; i < 2; i++) {
            s_secretsReceivedOffchainInRevealOrder[i] = s_secrets[revealOrders[i]];
        }
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 14. submitS(), k 2 - 3 submit their s_secrets, 4 - 5 fail to submit their s_secrets
        for (uint256 i = 2; i < 4; i++) {
            vm.startPrank(s_activatedOperators[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 16. failToSubmitS()
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitS();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * t. 1 -> 2 -> 9 -> 10 -> 13 -> 16
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [0, 1, 2, 3, 4] to submit their Co
        s_tempArray = [0, 1, 2, 3, 4];
        s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp = [0, 1, 2, 3, 4];
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo = new CommitReveal2.CvAndSigRS[](s_tempArray.length);
        s_tempVs = new uint256[](s_tempArray.length);
        s_indicesLength = s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp.length;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
        s_indicesFirstCvNotOnChainRestCvOnChain =
            _packArrayIntoUint256(s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo,
            s_packedVsForAllCvsNotOnChain,
            s_indicesLength,
            s_indicesFirstCvNotOnChainRestCvOnChain
        );
        mine(1);

        // ** 10. submitCo()
        // *** index [0, 1, 2, 3, 4] submit their Co
        vm.stopPrank();
        for (uint256 i; i < 5; i++) {
            vm.startPrank(s_activatedOperators[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 13. requestToSubmitS()
        // *** Let's assume no one submitted their s_secrets off-chain
        // *** [0, 1, 2, 3, 4] submitted their cv on-chain
        s_tempArray = new uint256[](0);
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        s_packedVsForAllCvsNotOnChain = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (s_tempArray[i] * 8));
        }
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](0);
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_secretsReceivedOffchainInRevealOrder,
            s_packedVsForAllCvsNotOnChain,
            s_sigRSsForAllCvsNotOnChain,
            s_packedRevealOrders
        );
        mine(1);

        // ** 16. failToSubmitS()
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitS();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );

        // * a. 1 -> 2 -> 12
        // ** Off-chain: Cvi Submission
        revealOrders = _setSCoCvRevealOrders(s_privateKeys);

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(0);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_operatorAddresses, LEADERNODE, s_anyAddress
        );
    }
}
