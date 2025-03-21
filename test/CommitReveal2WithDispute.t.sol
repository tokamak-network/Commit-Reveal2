// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2L1} from "./../src/CommitReveal2L1.sol";
import {BaseTest} from "./shared/BaseTest.t.sol";
import {console2, Vm} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./../script/NetworkHelperConfig.s.sol";
import {Sort} from "./shared/Sort.sol";
import {CommitReveal2Helper} from "./shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../script/DeployConsumerExample.s.sol";

contract CommitReveal2WithDispute is BaseTest, CommitReveal2Helper {
    // ** Contracts
    CommitReveal2L1 public s_commitReveal2;
    ConsumerExample public s_consumerExample;
    NetworkHelperConfig.NetworkConfig public s_activeNetworkConfig;
    NetworkHelperConfig s_networkHelperConfig;

    // ** Variables for Testing
    uint256 public s_requestFee;
    uint256 public s_startTimestamp;

    bytes32[] public s_secrets;
    bytes32[] public s_cos;
    bytes32[] public s_cvs;
    uint8[] public s_vs;
    bytes32[] public s_rs;
    bytes32[] public s_ss;
    uint256 public s_rv;
    bool public s_fulfilled;
    uint256 public s_randomNumber;
    address[] public s_activatedOperators;
    uint256[] public s_depositAmounts;
    address public s_anyAddress;

    // ** Variables for Dispute
    CommitReveal2L1.Signature[] public s_sigsDidntSubmitCv;
    bytes32[] public s_alreadySubmittedSecretsOffChain;
    uint256[] public s_requestedToSubmitCoIndices;
    uint256[] public s_requestedToSubmitCvIndices;
    bytes32[] public s_cvsToSubmit;
    uint8[] public s_vsToSubmit;
    bytes32[] public s_rsToSubmit;
    bytes32[] public s_ssToSubmit;
    uint256[] public s_tempArray;

    // ** constants

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);

        vm.stopPrank();
        (s_commitReveal2Address, s_networkHelperConfig) = (new DeployCommitReveal2()).run();
        s_commitReveal2 = CommitReveal2L1(s_commitReveal2Address);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
        s_nameHash = keccak256(bytes(s_activeNetworkConfig.name));
        s_versionHash = keccak256(bytes(s_activeNetworkConfig.version));

        s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));

        // *** Deposit And Activate
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
            vm.stopPrank();
            assertEq(
                s_commitReveal2.s_depositAmount(s_anvilDefaultAddresses[i]), s_activeNetworkConfig.activationThreshold
            );
            assertEq(s_commitReveal2.s_activatedOperatorIndex1Based(s_anvilDefaultAddresses[i]), i + 1);
        }

        // *** Allocate storage arrays
        s_secrets = new bytes32[](s_anvilDefaultAddresses.length);
        s_cos = new bytes32[](s_anvilDefaultAddresses.length);
        s_cvs = new bytes32[](s_anvilDefaultAddresses.length);
        s_vs = new uint8[](s_anvilDefaultAddresses.length);
        s_rs = new bytes32[](s_anvilDefaultAddresses.length);
        s_ss = new bytes32[](s_anvilDefaultAddresses.length);

        s_anyAddress = makeAddr("any");
    }

    // * 1. requestRandomNumber()
    // * 2. submitMerkleRoot()
    // * 3. requestToSubmitCv()
    // * 4. submitCv()
    // * 5. failToRequestSubmitCVAndSubmitMerkleRoot()
    // * 6. submitMerkleRootAfterDispute()
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
        console2.log(address(s_commitReveal2).balance);

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
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());

        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // *** calculate reveal order
        uint256[] memory diffs = new uint256[](s_anvilDefaultAddresses.length);
        uint256[] memory revealOrders = new uint256[](s_anvilDefaultAddresses.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss, revealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(0);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * b. 1 -> 2 -> 13 -> 14
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);
        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        diffs = new uint256[](s_anvilDefaultAddresses.length);
        revealOrders = new uint256[](s_anvilDefaultAddresses.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume the k of 0, 1, 2, 3 submitted their s_secrets off-chain

        // *** The signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index descending(for gas optimization and to avoid stack too deep error).
        // **** In b case, no one submitted the Cvi on-chain, all the signatures are required.
        s_sigsDidntSubmitCv = new CommitReveal2L1.Signature[](10);
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            s_sigsDidntSubmitCv[i].v = s_vs[s_anvilDefaultAddresses.length - i - 1];
            s_sigsDidntSubmitCv[i].r = s_rs[s_anvilDefaultAddresses.length - i - 1];
            s_sigsDidntSubmitCv[i].s = s_ss[s_anvilDefaultAddresses.length - i - 1];
        }
        /// *** We need to send the s_secrets of the k 0, 1, 2, 3 operators
        s_alreadySubmittedSecretsOffChain = new bytes32[](4);
        for (uint256 i; i < 4; i++) {
            s_alreadySubmittedSecretsOffChain[i] = s_secrets[revealOrders[i]];
        }
        /// *** Finally request to submit the s_secrets
        mine(1);
        s_commitReveal2.requestToSubmitS(s_cos, s_alreadySubmittedSecretsOffChain, s_sigsDidntSubmitCv, revealOrders);
        mine(1);

        // ** 14. submitS(), k 4-9 submit their s_secrets
        for (uint256 i = 4; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(1);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * c. 1 -> 2 -> 9 -> 10 -> 12, round: 2
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }
        vm.startPrank(LEADERNODE);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 2, 5, 9 to submit their Co
        s_tempArray = [2, 5, 9];
        s_requestedToSubmitCoIndices = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In c case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_cvsToSubmit = new bytes32[](3);
        s_vsToSubmit = new uint8[](3);
        s_rsToSubmit = new bytes32[](3);
        s_ssToSubmit = new bytes32[](3);
        for (uint256 i; i < 3; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** The operators index 2, 5, 9 submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_anvilDefaultAddresses[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // *** caculate reveal order
        diffs = new uint256[](s_anvilDefaultAddresses.length);
        revealOrders = new uint256[](s_anvilDefaultAddresses.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // ** 12. generateRandomNumber()
        mine(1);
        // any operator can generate the random number
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss, revealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(s_commitReveal2.s_currentRound());
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // *** d. 1 -> 2 -> 9 -> 10 -> 13 -> 14
        // ** Request Three more times
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }
        vm.startPrank(LEADERNODE);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 3, 7, 8 to submit their Co
        s_tempArray = [3, 7, 8];

        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In d case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** The operators index 3, 7, 8 submit their Co
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_anvilDefaultAddresses[s_tempArray[i]]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }
        vm.stopPrank();

        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume the k of 0, 1, 2, 3, 4, 5 submitted their s_secrets off-chain

        // *** In d case, some(3,7,8) submitted the Cvi on-chain (in submitCo() function), the signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index descending(for gas optimization and to avoid stack too deep error).
        s_tempArray = [9, 6, 5, 4, 2, 1, 0];
        s_sigsDidntSubmitCv = new CommitReveal2L1.Signature[](10 - 3);
        for (uint256 i; i < 10 - 3; i++) {
            s_sigsDidntSubmitCv[i].v = s_vs[s_tempArray[i]];
            s_sigsDidntSubmitCv[i].r = s_rs[s_tempArray[i]];
            s_sigsDidntSubmitCv[i].s = s_ss[s_tempArray[i]];
        }
        s_alreadySubmittedSecretsOffChain = new bytes32[](6);
        for (uint256 i; i < 6; i++) {
            s_alreadySubmittedSecretsOffChain[i] = s_secrets[revealOrders[i]];
        }
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(s_cos, s_alreadySubmittedSecretsOffChain, s_sigsDidntSubmitCv, revealOrders);
        mine(1);

        // ** 14. submitS(), k 6-9 submit their s_secrets
        for (uint256 i = 6; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(3);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // ** e,f,g,h

        // *  e. 1 -> 3 ->4 -> 6 -> 12
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 2,3,5,6,7 to submit their cv
        mine(1);
        s_tempArray = [2, 3, 5, 6, 7];
        s_requestedToSubmitCvIndices = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 2,3,5,6,7 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 5; i++) {
            vm.startPrank(s_anvilDefaultAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRootAfterDispute(_createMerkleRoot(s_cvs));
        mine(1);

        // *** caculate reveal order
        diffs = new uint256[](s_anvilDefaultAddresses.length);
        revealOrders = new uint256[](s_anvilDefaultAddresses.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss, revealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(4);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * f. 1 -> 3 ->4 -> 6 -> 13 -> 14, round = 5
        // ** Off-chain: Cvi Submission

        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_secrets = new bytes32[](s_anvilDefaultAddresses.length);
        s_cos = new bytes32[](s_anvilDefaultAddresses.length);
        s_cvs = new bytes32[](s_anvilDefaultAddresses.length);
        s_vs = new uint8[](s_anvilDefaultAddresses.length);
        s_rs = new bytes32[](s_anvilDefaultAddresses.length);
        s_ss = new bytes32[](s_anvilDefaultAddresses.length);
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,9 to submit their cv
        mine(1);
        s_tempArray = [0, 9];
        s_requestedToSubmitCvIndices = new uint256[](2);
        for (uint256 i; i < 2; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 0,9 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 2; i++) {
            vm.startPrank(s_anvilDefaultAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume none of the operators submitted their s_secrets off-chain
        // *** index 0, 9 already submitted their cv on-chain
        s_tempArray = [8, 7, 6, 5, 4, 3, 2, 1];
        s_sigsDidntSubmitCv = new CommitReveal2L1.Signature[](10 - 2);
        for (uint256 i; i < 10 - 2; i++) {
            s_sigsDidntSubmitCv[i].v = s_vs[s_tempArray[i]];
            s_sigsDidntSubmitCv[i].r = s_rs[s_tempArray[i]];
            s_sigsDidntSubmitCv[i].s = s_ss[s_tempArray[i]];
        }
        s_alreadySubmittedSecretsOffChain = new bytes32[](0);
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(s_cos, s_alreadySubmittedSecretsOffChain, s_sigsDidntSubmitCv, revealOrders);

        // ** 14. submitS(), k 0-9 submit their s_secrets
        for (uint256 i = 0; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(5);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * g. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 12, round = 6
        // ** 1. Request Three more times
        s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }

        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_secrets = new bytes32[](s_anvilDefaultAddresses.length);
        s_cos = new bytes32[](s_anvilDefaultAddresses.length);
        s_cvs = new bytes32[](s_anvilDefaultAddresses.length);
        s_vs = new uint8[](s_anvilDefaultAddresses.length);
        s_rs = new bytes32[](s_anvilDefaultAddresses.length);
        s_ss = new bytes32[](s_anvilDefaultAddresses.length);
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,9 to submit their cv
        mine(1);
        s_tempArray = [0, 9];
        s_requestedToSubmitCvIndices = new uint256[](2);
        for (uint256 i; i < 2; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 0,9 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 2; i++) {
            vm.startPrank(s_anvilDefaultAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRootAfterDispute(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request everyone to submit their Co

        // *** The indices who already submitted the Cvi on-chain should be appended at the end.
        s_tempArray = [1, 2, 3, 4, 5, 6, 7, 8, 0, 9];
        s_requestedToSubmitCoIndices = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In g case, some(0,9) submitted the Cvi on-chain (in submitCv() function), the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_tempArray = [1, 2, 3, 4, 5, 6, 7, 8];
        s_cvsToSubmit = new bytes32[](10 - 2);
        s_vsToSubmit = new uint8[](10 - 2);
        s_rsToSubmit = new bytes32[](10 - 2);
        s_ssToSubmit = new bytes32[](10 - 2);
        for (uint256 i; i < 10 - 2; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** Everyone submit their Co
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // *** caculate reveal order
        diffs = new uint256[](s_anvilDefaultAddresses.length);
        revealOrders = new uint256[](s_anvilDefaultAddresses.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss, revealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(6);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * h. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 13 -> 14
        // ** 3. requestToSubmitCv()
        // *** The leadernode requests everyone to submit their cv
        mine(1);
        s_requestedToSubmitCvIndices = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            s_requestedToSubmitCvIndices[i] = i;
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** 4. submitCv()
        // *** Everyone submit their cv
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2.submitCv(s_cvs[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 6. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRootAfterDispute(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request everyone to submit their Co
        mine(1);
        s_requestedToSubmitCoIndices = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            s_requestedToSubmitCoIndices[i] = i;
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In h case, everyone submitted the Cvi on-chain (in submitCv() function), no s_cvs and signatures are required.
        s_cvsToSubmit = new bytes32[](0);
        s_vsToSubmit = new uint8[](0);
        s_rsToSubmit = new bytes32[](0);
        s_ssToSubmit = new bytes32[](0);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** Everyone submit their Co
        vm.stopPrank();
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            mine(1);
            s_commitReveal2.submitCo(s_cos[i]);
            mine(1);
            vm.stopPrank();
        }

        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume none of the operators submitted their s_secrets off-chain
        // *** everyone submitted their cv on-chain
        s_sigsDidntSubmitCv = new CommitReveal2L1.Signature[](0);
        s_alreadySubmittedSecretsOffChain = new bytes32[](0);
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(s_cos, s_alreadySubmittedSecretsOffChain, s_sigsDidntSubmitCv, revealOrders);

        // ** 14. submitS(), k 0-9 submit their s_secrets
        for (uint256 i = 0; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(s_secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(7);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // *** let's refund the round 8 and start from round 9
        s_consumerExample.refund(8);
        mine(1);
        vm.stopPrank();
        console2.log("after refund");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // With currentRound=8, lastFulfilledRound=7, and requestCount=9, let's call requestRandomNumber 3 more times.

        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * j. 1 -> 3 -> 4 -> 7, round: 9
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        // ** Off-chain: Cvi Submission
        s_secrets = new bytes32[](s_anvilDefaultAddresses.length);
        s_cos = new bytes32[](s_anvilDefaultAddresses.length);
        s_cvs = new bytes32[](s_anvilDefaultAddresses.length);
        s_vs = new uint8[](s_anvilDefaultAddresses.length);
        s_rs = new bytes32[](s_anvilDefaultAddresses.length);
        s_ss = new bytes32[](s_anvilDefaultAddresses.length);
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_anvilDefaultPrivateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,2,4,6,8 to submit their cv
        mine(1);
        s_tempArray = [0, 2, 4, 6, 8];
        s_requestedToSubmitCvIndices = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** 4. submitCv()
        // *** Only the operators index 0, 4 submit their cv
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[0]);
        s_commitReveal2.submitCv(s_cvs[0]);
        mine(1);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[4]);
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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * k. 1 -> 3 -> 7, round: 9
        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0 to submit their cv
        mine(1);
        s_requestedToSubmitCvIndices = new uint256[](1);
        s_requestedToSubmitCvIndices[0] = 0;
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** No one submits their cv
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);

        // ** 7. failToSubmitCv(), the operator index 0 fail to submit their cv
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitCv();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * l. 1 -> 3 -> 4 -> 8, round 9, operatorNum = 6
        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 1, 3, 5 to submit their cv
        mine(1);
        s_tempArray = [1, 3, 5];
        s_requestedToSubmitCvIndices = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
        mine(1);

        // ** 4. submitCv()
        // *** The operators index 1, 3, 5 submit their cv
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.startPrank(s_anvilDefaultAddresses[s_tempArray[i]]);
            s_commitReveal2.submitCv(s_cvs[s_tempArray[i]]);
            mine(1);
            vm.stopPrank();
        }

        // ** 8. failToSubmitMerkleRootAfterDispute()
        mine(s_activeNetworkConfig.onChainSubmissionPeriod);
        mine(s_activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod);
        vm.startPrank(s_anvilDefaultAddresses[0]);
        s_commitReveal2.failToSubmitMerkleRootAfterDispute();
        mine(1);
        vm.stopPrank();

        // ** let's resume the round 9
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * m. 1 -> 2 -> 9 -> 11, round: 9, operatorNum = 6
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 2, 3 to submit their Co
        s_tempArray = [2, 3];
        s_requestedToSubmitCoIndices = new uint256[](2);
        for (uint256 i; i < 2; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In m case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_cvsToSubmit = new bytes32[](2);
        s_vsToSubmit = new uint8[](2);
        s_rsToSubmit = new bytes32[](2);
        s_ssToSubmit = new bytes32[](2);
        for (uint256 i; i < 2; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * n. 1 -> 2 -> 9 -> 10 -> 11, operatorNum = 4
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request all the operators to submit their Co
        s_tempArray = [0, 1, 2, 3];
        s_requestedToSubmitCoIndices = new uint256[](4);
        for (uint256 i; i < 4; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In n case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_cvsToSubmit = new bytes32[](4);
        s_vsToSubmit = new uint8[](4);
        s_rsToSubmit = new bytes32[](4);
        s_ssToSubmit = new bytes32[](4);
        for (uint256 i; i < 4; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * o. 1 -> 3 -> 4 -> 6 -> 9 -> 11, operatorNum = 3

        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,1,2 to submit their cv
        mine(1);
        s_tempArray = [0, 1, 2];
        s_requestedToSubmitCvIndices = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
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
        s_commitReveal2.submitMerkleRootAfterDispute(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request all the operators to submit their Co
        s_tempArray = [0, 1, 2];
        s_requestedToSubmitCoIndices = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In this case, everyone submitted the Cvi on-chain (in submitCv() function), no s_cvs and signatures are required.
        s_cvsToSubmit = new bytes32[](0);
        s_vsToSubmit = new uint8[](0);
        s_rsToSubmit = new bytes32[](0);
        s_ssToSubmit = new bytes32[](0);
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * p. 1 -> 3 -> 4 -> 6 -> 9 -> 10 -> 11, operatorNum = 0
        // ** Let's withdraw all
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2.withdraw();
            mine(1);
            vm.stopPrank();
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.withdraw();
        mine(1);
        vm.stopPrank();

        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // ** 10 operators deposit and activate
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            if (s_commitReveal2.s_depositAmount(s_anvilDefaultAddresses[i]) < s_activeNetworkConfig.activationThreshold)
            {
                s_commitReveal2.deposit{
                    value: s_activeNetworkConfig.activationThreshold
                        - s_commitReveal2.s_depositAmount(s_anvilDefaultAddresses[i])
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
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 3. requestToSubmitCv()
        // *** The leadernode requests the operators index 0,1,2 to submit their cv
        mine(1);
        s_tempArray = [0, 1, 2];
        s_requestedToSubmitCvIndices = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCvIndices[i] = s_tempArray[i];
        }
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitCv(s_requestedToSubmitCvIndices);
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
        s_commitReveal2.submitMerkleRootAfterDispute(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [0,1,2, 3, 4, 5] to submit their Co
        s_tempArray = [0, 1, 2, 3, 4, 5];
        s_requestedToSubmitCoIndices = new uint256[](6);
        // *** The indices who already submitted the Cvi on-chain should be appended at the end.
        for (uint256 i = 3; i < 6; i++) {
            s_requestedToSubmitCoIndices[i - 3] = s_tempArray[i];
        }
        for (uint256 i = 0; i < 3; i++) {
            s_requestedToSubmitCoIndices[i + 3] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In this case, 0, 1, 2 submitted the Cvi on-chain (in submitCv() function)
        s_cvsToSubmit = new bytes32[](6 - 3);
        s_vsToSubmit = new uint8[](6 - 3);
        s_rsToSubmit = new bytes32[](6 - 3);
        s_ssToSubmit = new bytes32[](6 - 3);
        for (uint256 i = 3; i < 6; i++) {
            s_cvsToSubmit[i - 3] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i - 3] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i - 3] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i - 3] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** only index 3,4 submit their Co
        vm.stopPrank();
        for (uint256 i = 3; i < 5; i++) {
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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * q. 1 -> 2 -> 15
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

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
        s_commitReveal2.failToRequestSOrGenerateRandomNumber();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // ** resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * r. 1 -> 2 -> 9 -> 10 -> 15
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [0, 3] to submit their Co
        s_tempArray = [0, 3];
        s_requestedToSubmitCoIndices = new uint256[](2);
        for (uint256 i; i < 2; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In this case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_cvsToSubmit = new bytes32[](2);
        s_vsToSubmit = new uint8[](2);
        s_rsToSubmit = new bytes32[](2);
        s_ssToSubmit = new bytes32[](2);
        for (uint256 i; i < 2; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
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
        s_commitReveal2.failToRequestSOrGenerateRandomNumber();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // ** resume
        vm.startPrank(LEADERNODE);
        s_commitReveal2.resume{value: s_activeNetworkConfig.activationThreshold}();
        mine(1);
        vm.stopPrank();
        console2.log("After resume");
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * s. 1 -> 2 -> 9 -> 10 -> 13 -> 14 -> 16
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [1, 2, 3] to submit their Co
        s_tempArray = [1, 2, 3];
        s_requestedToSubmitCoIndices = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In this case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_cvsToSubmit = new bytes32[](3);
        s_vsToSubmit = new uint8[](3);
        s_rsToSubmit = new bytes32[](3);
        s_ssToSubmit = new bytes32[](3);
        for (uint256 i; i < 3; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
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
        // *** - calculate reveal order
        revealOrders = new uint256[](s_activatedOperators.length);
        diffs = new uint256[](s_activatedOperators.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_activatedOperators.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume only k 0, 1 submitted their s_secrets off-chain
        // *** [1, 2, 3] submitted their cv on-chain
        s_alreadySubmittedSecretsOffChain = new bytes32[](2);
        for (uint256 i = 0; i < 2; i++) {
            s_alreadySubmittedSecretsOffChain[i] = s_secrets[revealOrders[i]];
        }
        // *** [0, 5] didn't submit their cv onchain
        s_tempArray = [5, 4, 0]; // in descending order
        s_sigsDidntSubmitCv = new CommitReveal2L1.Signature[](3);
        for (uint256 i = 0; i < 3; i++) {
            s_sigsDidntSubmitCv[i].v = s_vs[s_tempArray[i]];
            s_sigsDidntSubmitCv[i].r = s_rs[s_tempArray[i]];
            s_sigsDidntSubmitCv[i].s = s_ss[s_tempArray[i]];
        }
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(s_cos, s_alreadySubmittedSecretsOffChain, s_sigsDidntSubmitCv, revealOrders);

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
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * t. 1 -> 2 -> 9 -> 10 -> 13 -> 16
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request [0, 1, 2, 3, 4] to submit their Co
        s_tempArray = [0, 1, 2, 3, 4];
        s_requestedToSubmitCoIndices = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            s_requestedToSubmitCoIndices[i] = s_tempArray[i];
        }
        // *** The s_cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In this case, no one submitted the Cvi on-chain, all the s_cvs and signatures of the operators who are requested to submit their Co are required.
        s_cvsToSubmit = new bytes32[](5);
        s_vsToSubmit = new uint8[](5);
        s_rsToSubmit = new bytes32[](5);
        s_ssToSubmit = new bytes32[](5);
        for (uint256 i; i < 5; i++) {
            s_cvsToSubmit[i] = s_cvs[s_tempArray[i]];
            s_vsToSubmit[i] = s_vs[s_tempArray[i]];
            s_rsToSubmit[i] = s_rs[s_tempArray[i]];
            s_ssToSubmit[i] = s_ss[s_tempArray[i]];
        }
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            s_requestedToSubmitCoIndices, s_cvsToSubmit, s_vsToSubmit, s_rsToSubmit, s_ssToSubmit
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
        // *** - calculate reveal order
        revealOrders = new uint256[](s_activatedOperators.length);
        diffs = new uint256[](s_activatedOperators.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_activatedOperators.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume no one submitted their s_secrets off-chain
        // *** [0, 1, 2, 3, 4] submitted their cv on-chain
        s_alreadySubmittedSecretsOffChain = new bytes32[](0);
        // *** everyone submitted their cv onchain
        s_sigsDidntSubmitCv = new CommitReveal2L1.Signature[](0);
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(s_cos, s_alreadySubmittedSecretsOffChain, s_sigsDidntSubmitCv, revealOrders);

        // ** 16. failToSubmitS()
        mine(s_activeNetworkConfig.offChainSubmissionPeriodPerOperator);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.failToSubmitS();
        mine(1);
        vm.stopPrank();
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );

        // * a. 1 -> 2 -> 12
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        s_secrets = new bytes32[](s_activatedOperators.length);
        s_cos = new bytes32[](s_activatedOperators.length);
        s_cvs = new bytes32[](s_activatedOperators.length);
        s_vs = new uint8[](s_activatedOperators.length);
        s_rs = new bytes32[](s_activatedOperators.length);
        s_ss = new bytes32[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(s_privateKeys[s_activatedOperators[i]], _getTypedDataHash(s_startTimestamp, s_cvs[i]));
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);

        // *** calculate reveal order
        revealOrders = new uint256[](s_activatedOperators.length);
        diffs = new uint256[](s_activatedOperators.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_activatedOperators.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss, revealOrders);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(0);
        console2.log(s_fulfilled, s_randomNumber);
        consoleDepositsAndSlashRewardAccumulated(
            s_commitReveal2, s_consumerExample, s_anvilDefaultAddresses, LEADERNODE, s_anyAddress
        );
    }
}
