// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2L1} from "./../src/CommitReveal2L1.sol";
import {BaseTest} from "./shared/BaseTest.t.sol";
import {console2, Vm} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./../script/NetworkHelperConfig.s.sol";
import {Sort} from "./../src/Sort.sol";
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
        (s_commitReveal2Address, s_networkHelperConfig) = (
            new DeployCommitReveal2()
        ).run();
        s_commitReveal2 = CommitReveal2L1(s_commitReveal2Address);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
        s_nameHash = keccak256(bytes(s_activeNetworkConfig.name));
        s_versionHash = keccak256(bytes(s_activeNetworkConfig.version));

        s_consumerExample = (new DeployConsumerExample())
            .deployConsumerExampleUsingConfig(address(s_commitReveal2));

        // *** Deposit And Activate
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2.depositAndActivate{
                value: s_activeNetworkConfig.activationThreshold
            }();
            vm.stopPrank();
            assertEq(
                s_commitReveal2.s_depositAmount(s_anvilDefaultAddresses[i]),
                s_activeNetworkConfig.activationThreshold
            );
            assertEq(
                s_commitReveal2.s_activatedOperatorIndex1Based(
                    s_anvilDefaultAddresses[i]
                ),
                i + 1
            );
        }

        // *** Allocate storage arrays
        s_secrets = new bytes32[](s_anvilDefaultAddresses.length);
        s_cos = new bytes32[](s_anvilDefaultAddresses.length);
        s_cvs = new bytes32[](s_anvilDefaultAddresses.length);
        s_vs = new uint8[](s_anvilDefaultAddresses.length);
        s_rs = new bytes32[](s_anvilDefaultAddresses.length);
        s_ss = new bytes32[](s_anvilDefaultAddresses.length);
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
     All Successful Paths
    a. 1 -> 2 -> 12
    b. 1 -> 2 -> 13 -> 14
    c. 1 -> 2 -> 9 -> 10 -> 12
    d. 1 -> 2 -> 9 -> 10 -> 13 -> 14
    e. 1 -> 3 ->4 -> 6 -> 12
    f. 1 -> 3 ->4 -> 6 -> 13 -> 14
    g. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 12
    h. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 13 -> 14

     All Failure Paths
    i. 1 -> 5
    j. 1 -> 3 -> 4 -> 7
    k. 1 -> 3 -> 7
    l. 1 -> 3 -> 4-> 8
    m. 1 -> 2 -> 9 -> 11
    n. 1 -> 2 -> 9 -> 10 -> 11
    o. 1 -> 3 -> 4 -> 6 -> 9 -> 11
    p. 1 -> 3 -> 4 -> 6 -> 9 -> 10 -> 11
    q. 1 -> 2 -> 15
    r. 1 -> 2 -> 9 -> 10 -> 15
    s. 1 -> 2 -> 9 -> 10 -> 13 -> 14 -> 16
    t. 1 -> 2 -> 9 -> 10 -> 13  -> 16
     */

    function test_allPaths() public {
        // ** a,b,c,d,e,f

        // * a. 1 -> 2 -> 12
        // ** 1. Request Three Times
        mine(1);
        s_requestFee = s_commitReveal2.estimateRequestPrice(
            s_consumerExample.CALLBACK_GAS_LIMIT(),
            tx.gasprice
        );
        mine(1);
        vm.recordLogs();
        mine(1);
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        mine(1);
        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );

        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
        }

        // ** 2. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);
        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(0);
        console2.log(s_fulfilled, s_randomNumber);

        // * b. 1 -> 2 -> 13 -> 14
        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
        mine(1);
        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        uint256[] memory diffs = new uint256[](s_anvilDefaultAddresses.length);
        uint256[] memory revealOrders = new uint256[](
            s_anvilDefaultAddresses.length
        );
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
            s_sigsDidntSubmitCv[i].v = s_vs[
                s_anvilDefaultAddresses.length - i - 1
            ];
            s_sigsDidntSubmitCv[i].r = s_rs[
                s_anvilDefaultAddresses.length - i - 1
            ];
            s_sigsDidntSubmitCv[i].s = s_ss[
                s_anvilDefaultAddresses.length - i - 1
            ];
        }
        /// *** We need to send the s_secrets of the k 0, 1, 2, 3 operators
        s_alreadySubmittedSecretsOffChain = new bytes32[](4);
        for (uint256 i; i < 4; i++) {
            s_alreadySubmittedSecretsOffChain[i] = s_secrets[revealOrders[i]];
        }
        /// *** Finally request to submit the s_secrets
        mine(1);
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_alreadySubmittedSecretsOffChain,
            s_sigsDidntSubmitCv
        );
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

        // * c. 1 -> 2 -> 9 -> 10 -> 12, round: 2
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
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
            s_requestedToSubmitCoIndices,
            s_cvsToSubmit,
            s_vsToSubmit,
            s_rsToSubmit,
            s_ssToSubmit
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

        // ** 12. generateRandomNumber()
        mine(1);
        // any operator can generate the random number
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(
            s_commitReveal2.s_currentRound()
        );
        console2.log(s_fulfilled, s_randomNumber);

        // *** d. 1 -> 2 -> 9 -> 10 -> 13 -> 14
        // ** Request Three more times
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
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
            s_requestedToSubmitCoIndices,
            s_cvsToSubmit,
            s_vsToSubmit,
            s_rsToSubmit,
            s_ssToSubmit
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
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_alreadySubmittedSecretsOffChain,
            s_sigsDidntSubmitCv
        );
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

        // ** e,f,g,h

        // *  e. 1 -> 3 ->4 -> 6 -> 12
        // ** Off-chain: Cvi Submission
        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
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

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(4);
        console2.log(s_fulfilled, s_randomNumber);

        // * f. 1 -> 3 ->4 -> 6 -> 13 -> 14, round = 5
        // ** Off-chain: Cvi Submission

        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
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
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_alreadySubmittedSecretsOffChain,
            s_sigsDidntSubmitCv
        );

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

        // * g. 1 -> 3 ->4 -> 6 -> 9 -> 10 -> 12, round = 6
        // ** 1. Request Three more times
        s_requestFee = s_commitReveal2.estimateRequestPrice(
            s_consumerExample.CALLBACK_GAS_LIMIT(),
            tx.gasprice
        );
        for (uint256 i; i < 3; i++) {
            s_consumerExample.requestRandomNumber{value: s_requestFee}();
        }

        // ** Off-chain: Cvi Submission
        (, s_startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(s_startTimestamp, s_cvs[i])
            );
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
            s_requestedToSubmitCoIndices,
            s_cvsToSubmit,
            s_vsToSubmit,
            s_rsToSubmit,
            s_ssToSubmit
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

        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(s_secrets, s_vs, s_rs, s_ss);
        mine(1);
        (s_fulfilled, s_randomNumber) = s_consumerExample.s_requests(6);
        console2.log(s_fulfilled, s_randomNumber);

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
            s_requestedToSubmitCoIndices,
            s_cvsToSubmit,
            s_vsToSubmit,
            s_rsToSubmit,
            s_ssToSubmit
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
        s_commitReveal2.requestToSubmitS(
            s_cos,
            s_alreadySubmittedSecretsOffChain,
            s_sigsDidntSubmitCv
        );

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
    }
}
