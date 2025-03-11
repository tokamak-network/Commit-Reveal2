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

    // ** constants

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);

        DeployCommitReveal2 deployCommitReveal2 = new DeployCommitReveal2();
        NetworkHelperConfig s_networkHelperConfig;
        vm.stopPrank();
        (s_commitReveal2Address, s_networkHelperConfig) = deployCommitReveal2
            .run();
        s_commitReveal2 = CommitReveal2L1(s_commitReveal2Address);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
        s_nameHash = keccak256(bytes(s_activeNetworkConfig.name));
        s_versionHash = keccak256(bytes(s_activeNetworkConfig.version));

        DeployConsumerExample deployConsumerExample = new DeployConsumerExample();
        s_consumerExample = deployConsumerExample
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

    function test_abcdPaths() public {
        // ** a,b,c,d

        // * a. 1 -> 2 -> 12
        // ** 1. Request Three Times
        mine(1);
        uint256 requestFee = s_commitReveal2.estimateRequestPrice(
            s_consumerExample.CALLBACK_GAS_LIMIT(),
            tx.gasprice
        );
        mine(1);
        vm.recordLogs();
        mine(1);
        s_consumerExample.requestRandomNumber{value: requestFee}();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        mine(1);
        (, uint256 startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );

        // ** Off-chain: Cvi Submission
        bytes32[] memory secrets = new bytes32[](10);
        bytes32[] memory cos = new bytes32[](10);
        bytes32[] memory cvs = new bytes32[](10);
        uint8[] memory vs = new uint8[](10);
        bytes32[] memory rs = new bytes32[](10);
        bytes32[] memory ss = new bytes32[](10);
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
            (vs[i], rs[i], ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(startTimestamp, cvs[i])
            );
        }

        // ** 2. submitMerkleRoot()
        vm.startPrank(LEADERNODE);
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(cvs));
        mine(1);
        // ** 12. generateRandomNumber()
        mine(1);
        s_commitReveal2.generateRandomNumber(secrets, vs, rs, ss);
        mine(1);
        (bool fulfilled, uint256 randomNumber) = s_consumerExample.s_requests(
            0
        );
        console2.log(fulfilled, randomNumber);

        // * b. 1 -> 2 -> 13 -> 14
        (, startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
            (vs[i], rs[i], ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(startTimestamp, cvs[i])
            );
        }

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(cvs));
        mine(1);
        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        uint256[] memory diffs = new uint256[](s_anvilDefaultAddresses.length);
        uint256[] memory revealOrders = new uint256[](
            s_anvilDefaultAddresses.length
        );
        uint256 rv = uint256(keccak256(abi.encodePacked(cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(rv, uint256(cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume the k of 0, 1, 2, 3 submitted their secrets off-chain

        // *** The signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index descending(for gas optimization and to avoid stack too deep error).
        // **** In b case, no one submitted the Cvi on-chain, all the signatures are required.
        CommitReveal2L1.Signature[]
            memory sigsDidntSubmitCv = new CommitReveal2L1.Signature[](10);
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            sigsDidntSubmitCv[i].v = vs[s_anvilDefaultAddresses.length - i - 1];
            sigsDidntSubmitCv[i].r = rs[s_anvilDefaultAddresses.length - i - 1];
            sigsDidntSubmitCv[i].s = ss[s_anvilDefaultAddresses.length - i - 1];
        }
        /// *** We need to send the secrets of the k 0, 1, 2, 3 operators
        bytes32[] memory alreadySubmittedSecretsOffChain = new bytes32[](4);
        for (uint256 i; i < 4; i++) {
            alreadySubmittedSecretsOffChain[i] = secrets[revealOrders[i]];
        }
        /// *** Finally request to submit the secrets
        mine(1);
        s_commitReveal2.requestToSubmitS(
            cos,
            alreadySubmittedSecretsOffChain,
            sigsDidntSubmitCv
        );
        mine(1);

        // ** 14. submitS(), k 4-9 submit their secrets
        for (uint256 i = 4; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (fulfilled, randomNumber) = s_consumerExample.s_requests(1);
        console2.log(fulfilled, randomNumber);

        // * c. 1 -> 2 -> 9 -> 10 -> 12, round: 2
        // ** Off-chain: Cvi Submission
        (, startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        // ** Off-chain: Cvi Submission
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
            (vs[i], rs[i], ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(startTimestamp, cvs[i])
            );
        }
        vm.startPrank(LEADERNODE);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 2, 5, 9 to submit their Co
        uint256[] memory requestedToSubmitCoIndices = new uint256[](3);
        requestedToSubmitCoIndices[0] = 2;
        requestedToSubmitCoIndices[1] = 5;
        requestedToSubmitCoIndices[2] = 9;
        // *** The cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In c case, no one submitted the Cvi on-chain, all the cvs and signatures of the operators who are requested to submit their Co are required.
        bytes32[] memory cvsToSubmit = new bytes32[](3);
        cvsToSubmit[0] = cvs[2];
        cvsToSubmit[1] = cvs[5];
        cvsToSubmit[2] = cvs[9];
        uint8[] memory vsToSubmit = new uint8[](3);
        bytes32[] memory rsToSubmit = new bytes32[](3);
        bytes32[] memory ssToSubmit = new bytes32[](3);
        vsToSubmit[0] = vs[2];
        vsToSubmit[1] = vs[5];
        vsToSubmit[2] = vs[9];
        rsToSubmit[0] = rs[2];
        rsToSubmit[1] = rs[5];
        rsToSubmit[2] = rs[9];
        ssToSubmit[0] = ss[2];
        ssToSubmit[1] = ss[5];
        ssToSubmit[2] = ss[9];
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            requestedToSubmitCoIndices,
            cvsToSubmit,
            vsToSubmit,
            rsToSubmit,
            ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** The operators index 2, 5, 9 submit their Co
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[2]);
        mine(1);
        s_commitReveal2.submitCo(cos[2]);
        mine(1);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[5]);
        mine(1);
        s_commitReveal2.submitCo(cos[5]);
        mine(1);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[9]);
        mine(1);
        s_commitReveal2.submitCo(cos[9]);
        mine(1);
        vm.stopPrank();

        // ** 12. generateRandomNumber()
        mine(1);
        // any operator can generate the random number
        s_commitReveal2.generateRandomNumber(secrets, vs, rs, ss);
        mine(1);
        (fulfilled, randomNumber) = s_consumerExample.s_requests(
            s_commitReveal2.s_currentRound()
        );
        console2.log(fulfilled, randomNumber);

        // *** d. 1 -> 2 -> 9 -> 10 -> 13 -> 14
        // ** Request Three more times
        s_consumerExample.requestRandomNumber{value: requestFee}();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        // ** Off-chain: Cvi Submission
        (, startTimestamp, , ) = s_commitReveal2.s_requestInfo(
            s_commitReveal2.s_currentRound()
        );
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
            (vs[i], rs[i], ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(startTimestamp, cvs[i])
            );
        }
        vm.startPrank(LEADERNODE);

        // ** 2. submitMerkleRoot()
        mine(1);
        s_commitReveal2.submitMerkleRoot(_createMerkleRoot(cvs));
        mine(1);

        // ** 9. requestToSubmitCo()
        // *** Let's request operator index 3, 7, 8 to submit their Co
        requestedToSubmitCoIndices[0] = 3;
        requestedToSubmitCoIndices[1] = 7;
        requestedToSubmitCoIndices[2] = 8;
        // *** The cvs and signatures of the operators who are requested to submit their Co are required except the operator who submitted the Cvi on-chain.
        // *** In d case, no one submitted the Cvi on-chain, all the cvs and signatures of the operators who are requested to submit their Co are required.
        cvsToSubmit[0] = cvs[3];
        cvsToSubmit[1] = cvs[7];
        cvsToSubmit[2] = cvs[8];
        vsToSubmit[0] = vs[3];
        vsToSubmit[1] = vs[7];
        vsToSubmit[2] = vs[8];
        rsToSubmit[0] = rs[3];
        rsToSubmit[1] = rs[7];
        rsToSubmit[2] = rs[8];
        ssToSubmit[0] = ss[3];
        ssToSubmit[1] = ss[7];
        ssToSubmit[2] = ss[8];
        mine(1);
        s_commitReveal2.requestToSubmitCo(
            requestedToSubmitCoIndices,
            cvsToSubmit,
            vsToSubmit,
            rsToSubmit,
            ssToSubmit
        );
        mine(1);

        // ** 10. submitCo()
        // *** The operators index 3, 7, 8 submit their Co
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[3]);
        mine(1);
        s_commitReveal2.submitCo(cos[3]);
        mine(1);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[7]);
        mine(1);
        s_commitReveal2.submitCo(cos[7]);
        mine(1);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[8]);
        mine(1);
        s_commitReveal2.submitCo(cos[8]);
        mine(1);
        vm.stopPrank();

        // ** 13. requestToSubmitS()
        // *** - calculate reveal order
        rv = uint256(keccak256(abi.encodePacked(cos)));
        for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
            diffs[i] = _diff(rv, uint256(cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        // *** Let's assume the k of 0, 1, 2, 3, 4, 5 submitted their secrets off-chain

        // *** In d case, some(3,7,8) submitted the Cvi on-chain (in submitCo() function), the signatures are required except the operator who submitted the Cvi on-chain.
        // *** The signatures should be organized in the order of activatedOperator Index descending(for gas optimization and to avoid stack too deep error).
        sigsDidntSubmitCv = new CommitReveal2L1.Signature[](10 - 3);
        sigsDidntSubmitCv[0].v = vs[9];
        sigsDidntSubmitCv[0].r = rs[9];
        sigsDidntSubmitCv[0].s = ss[9];
        sigsDidntSubmitCv[1].v = vs[6];
        sigsDidntSubmitCv[1].r = rs[6];
        sigsDidntSubmitCv[1].s = ss[6];
        sigsDidntSubmitCv[2].v = vs[5];
        sigsDidntSubmitCv[2].r = rs[5];
        sigsDidntSubmitCv[2].s = ss[5];
        sigsDidntSubmitCv[3].v = vs[4];
        sigsDidntSubmitCv[3].r = rs[4];
        sigsDidntSubmitCv[3].s = ss[4];
        sigsDidntSubmitCv[4].v = vs[2];
        sigsDidntSubmitCv[4].r = rs[2];
        sigsDidntSubmitCv[4].s = ss[2];
        sigsDidntSubmitCv[5].v = vs[1];
        sigsDidntSubmitCv[5].r = rs[1];
        sigsDidntSubmitCv[5].s = ss[1];
        sigsDidntSubmitCv[6].v = vs[0];
        sigsDidntSubmitCv[6].r = rs[0];
        sigsDidntSubmitCv[6].s = ss[0];
        alreadySubmittedSecretsOffChain = new bytes32[](6);
        for (uint256 i; i < 6; i++) {
            alreadySubmittedSecretsOffChain[i] = secrets[revealOrders[i]];
        }
        mine(1);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitS(
            cos,
            alreadySubmittedSecretsOffChain,
            sigsDidntSubmitCv
        );
        mine(1);

        // ** 14. submitS(), k 6-9 submit their secrets
        for (uint256 i = 6; i < s_anvilDefaultAddresses.length; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            mine(1);
            s_commitReveal2.submitS(secrets[revealOrders[i]]);
            mine(1);
            vm.stopPrank();
        }
        (fulfilled, randomNumber) = s_consumerExample.s_requests(3);
        console2.log(fulfilled, randomNumber);
    }

    //     function test_includingWholeDispute() public {
    //         console2.log("test_includingWholeDispute");

    //         // *** 10 operators deposit and activate
    //         // *************************************
    // for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
    //     vm.startPrank(s_anvilDefaultAddresses[i]);
    //     s_commitReveal2.deposit{
    //         value: s_activeNetworkConfig.activationThreshold
    //     }();
    //     s_commitReveal2.activate();
    //     vm.stopPrank();
    //     assertEq(
    //         s_commitReveal2.s_depositAmount(s_anvilDefaultAddresses[i]),
    //         s_activeNetworkConfig.activationThreshold
    //     );
    //     assertEq(
    //         s_commitReveal2.s_activatedOperatorIndex1Based(
    //             s_anvilDefaultAddresses[i]
    //         ),
    //         i + 1
    //     );
    // }
    // vm.startPrank(LEADERNODE);

    //         // *** Request Random Number 2 times
    //         // *************************************
    //         uint256 requestFee = s_commitReveal2.estimateRequestPrice(
    //             s_consumerExample.CALLBACK_GAS_LIMIT(),
    //             tx.gasprice
    //         );
    //         vm.recordLogs();
    //         s_consumerExample.requestRandomNumber{value: requestFee}();
    //         s_consumerExample.requestRandomNumber{value: requestFee}();
    //         uint256 round = 0;
    //         (, uint256 startTimestamp, , ) = s_commitReveal2.s_requestInfo(round);

    //         // *** Phase0: Off-chain: Commit Submission
    //         // *************************************
    //         bytes32[] memory secrets = new bytes32[](10);
    //         bytes32[] memory cos = new bytes32[](10);
    //         bytes32[] memory cvs = new bytes32[](10);
    //         uint8[] memory vs = new uint8[](10);
    //         bytes32[] memory rs = new bytes32[](10);
    //         bytes32[] memory ss = new bytes32[](10);
    //         for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
    //             (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
    //             (vs[i], rs[i], ss[i]) = vm.sign(
    //                 s_anvilDefaultPrivateKeys[i],
    //                 _getTypedDataHash(startTimestamp, cvs[i])
    //             );
    //         }
    //         mine(s_activeNetworkConfig.phaseDuration[0]);

    //         // *** Phase1: On-chain: Commit Submission Request
    //         // *** The leadernode requests the operators index 1,3 to submit their cv
    //         // *************************************
    //         uint256[] memory requestedToSubmitCVIndices = new uint256[](2);
    //         requestedToSubmitCVIndices[0] = 1;
    //         requestedToSubmitCVIndices[1] = 3;
    //         s_commitReveal2.requestToSubmitCV(requestedToSubmitCVIndices);
    //         mine(s_activeNetworkConfig.phaseDuration[1]);

    //         // *** Phase2: On-chain: Commit Submission
    //         // *** The operators index 1,3 submit their cv
    //         // *************************************
    //         vm.stopPrank();
    //         for (uint256 i; i < requestedToSubmitCVIndices.length; i++) {
    //             vm.startPrank(
    //                 s_anvilDefaultAddresses[requestedToSubmitCVIndices[i]]
    //             );
    //             s_commitReveal2.submitCV(cvs[requestedToSubmitCVIndices[i]]);
    //             vm.stopPrank();
    //         }
    //         mine(s_activeNetworkConfig.phaseDuration[2]);

    //         // *** Phase3: On-chain:Merkle Root Submission
    //         // *************************************
    //         vm.startPrank(LEADERNODE);
    //         s_commitReveal2.submitMerkleRoot(_createMerkleRoot(cvs));
    //         mine(s_activeNetworkConfig.phaseDuration[3]);

    //         // ***Phase4: Off-chain: Reveal-1 Submission
    //         // *************************************
    //         mine(s_activeNetworkConfig.phaseDuration[4]);
    //         // done

    //         // ***Phase5: On-chain: Reveal-1 Submission Request
    //         // *** The leadernode requests the operators index 5, 8, 3 to submit their co
    //         // *************************************
    //         uint256[] memory requestedToSubmitCOIndices = new uint256[](3);
    //         requestedToSubmitCOIndices[0] = 5;
    //         requestedToSubmitCOIndices[1] = 8;
    //         requestedToSubmitCOIndices[2] = 3;
    //         bytes32[] memory phase5Cvs = new bytes32[](2); // index 3 already submitted cv in phase2
    //         phase5Cvs[0] = cvs[5];
    //         phase5Cvs[1] = cvs[8];
    //         uint8[] memory phase5Vs = new uint8[](2);
    //         bytes32[] memory phase5Rs = new bytes32[](2);
    //         bytes32[] memory phase5Ss = new bytes32[](2);
    //         phase5Vs[0] = vs[5];
    //         phase5Vs[1] = vs[8];
    //         phase5Rs[0] = rs[5];
    //         phase5Rs[1] = rs[8];
    //         phase5Ss[0] = ss[5];
    //         phase5Ss[1] = ss[8];
    //         s_commitReveal2.requestToSubmitCO(
    //             requestedToSubmitCOIndices,
    //             phase5Cvs,
    //             phase5Vs,
    //             phase5Rs,
    //             phase5Ss
    //         );
    //         mine(s_activeNetworkConfig.phaseDuration[5]);

    //         // ***Phase6: On-chain: Reveal-1 Submission
    //         // *** The operators index 5, 8, 3 submit their co
    //         // *************************************
    //         vm.stopPrank();
    //         vm.startPrank(s_anvilDefaultAddresses[5]);
    //         s_commitReveal2.submitCO(cos[5]);
    //         vm.stopPrank();
    //         vm.startPrank(s_anvilDefaultAddresses[8]);
    //         s_commitReveal2.submitCO(cos[8]);
    //         vm.stopPrank();
    //         vm.startPrank(s_anvilDefaultAddresses[3]);
    //         s_commitReveal2.submitCO(cos[3]);
    //         vm.stopPrank();
    //         mine(s_activeNetworkConfig.phaseDuration[6]);

    //         // ***Phase7: Off-chain: Reveal-2 Submission
    //         // *** Calculate the reveal order
    //         // *************************************
    //         uint256[] memory diffs = new uint256[](s_anvilDefaultAddresses.length);
    //         uint256[] memory revealOrders = new uint256[](
    //             s_anvilDefaultAddresses.length
    //         );
    //         uint256 rv = uint256(keccak256(abi.encodePacked(cos)));
    //         for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
    //             diffs[i] = _diff(rv, uint256(cvs[i]));
    //             revealOrders[i] = i;
    //         }
    //         Sort.sort(diffs, revealOrders);
    //         mine(s_activeNetworkConfig.phaseDuration[7]);

    //         // ***Phase8: On-chain: Reveal-2 Submission Request
    //         // *** The leadernode requests the operators from order index k 3 to submit their s
    //         // *** The operators who have already submitted cvs in phase2 and phase5: 1, 3, 5, 8
    //         // *************************************
    //         // in descending order
    //         CommitReveal2L1.Signature[]
    //             memory signatures = new CommitReveal2L1.Signature[](10 - 4);
    //         signatures[0].v = vs[9];
    //         signatures[0].r = rs[9];
    //         signatures[0].s = ss[9];
    //         signatures[1].v = vs[7];
    //         signatures[1].r = rs[7];
    //         signatures[1].s = ss[7];
    //         signatures[2].v = vs[6];
    //         signatures[2].r = rs[6];
    //         signatures[2].s = ss[6];
    //         signatures[3].v = vs[4];
    //         signatures[3].r = rs[4];
    //         signatures[3].s = ss[4];
    //         signatures[4].v = vs[2];
    //         signatures[4].r = rs[2];
    //         signatures[4].s = ss[2];
    //         signatures[5].v = vs[0];
    //         signatures[5].r = rs[0];
    //         signatures[5].s = ss[0];

    //         bytes32[] memory phase8Secrets = new bytes32[](3); // 0, 1, 2
    //         phase8Secrets[0] = secrets[revealOrders[0]];
    //         phase8Secrets[1] = secrets[revealOrders[1]];
    //         phase8Secrets[2] = secrets[revealOrders[2]];

    //         vm.startPrank(LEADERNODE);
    //         s_commitReveal2.requestToSubmitSFromIndex(
    //             cos,
    //             phase8Secrets,
    //             signatures
    //         );
    //         mine(s_activeNetworkConfig.phaseDuration[8]);

    //         // ***Phase9: On-chain: Reveal-2 Submission
    //         // *** The operators from order index k 3 submit their s
    //         // *************************************
    //         vm.stopPrank();
    //         for (uint256 i = 3; i < s_anvilDefaultAddresses.length; i++) {
    //             vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
    //             s_commitReveal2.submitS(secrets[revealOrders[i]]);
    //             vm.stopPrank();
    //         }

    //         // *** let's fail on phase2 on this new round
    //         ++round;
    //         (, startTimestamp, , ) = s_commitReveal2.s_requestInfo(round);
    //         // ***Phase0: Off-chain: Commit Submission
    //         // *************************************
    //         for (uint256 i; i < 10; i++) {
    //             (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
    //             (vs[i], rs[i], ss[i]) = vm.sign(
    //                 s_anvilDefaultPrivateKeys[i],
    //                 _getTypedDataHash(startTimestamp, cvs[i])
    //             );
    //         }
    //         mine(s_activeNetworkConfig.phaseDuration[0]);

    //         // ***Phase1: On-chain: Commit Submission Request
    //         // *** The leadernode requests the operators index 1,3 to submit their cv
    //         // *************************************
    //         requestedToSubmitCVIndices[0] = 1;
    //         requestedToSubmitCVIndices[1] = 3;
    //         vm.startPrank(LEADERNODE);
    //         s_commitReveal2.requestToSubmitCV(requestedToSubmitCVIndices);
    //         vm.stopPrank();
    //         mine(s_activeNetworkConfig.phaseDuration[1]);

    //         // ***Phase2: On-chain: Commit Submission
    //         // *** The operators index 1,3 doesn't submit their cv
    //         // *************************************
    //         mine(s_activeNetworkConfig.phaseDuration[2]);

    //         // ***Phase3: The index 1,3 get slashed and the round starts from Phase0
    //         // *************************************
    //         vm.startPrank(LEADERNODE);
    //         s_commitReveal2.phase2FailedAndRestart();
    //         assertEq(s_commitReveal2.getActivatedOperatorsLength(), 10 - 2);
    //         assertEq(s_commitReveal2.s_currentRound(), round);

    //         // *** Request Random Number 4 more times
    //         // *************************************
    //         requestFee = s_commitReveal2.estimateRequestPrice(
    //             s_consumerExample.CALLBACK_GAS_LIMIT(),
    //             tx.gasprice
    //         );
    //         s_consumerExample.requestRandomNumber{value: requestFee}();
    //         s_consumerExample.requestRandomNumber{value: requestFee}();
    //         s_consumerExample.requestRandomNumber{value: requestFee}();
    //         s_consumerExample.requestRandomNumber{value: requestFee}();
    //         assertEq(s_commitReveal2.s_requestCount(), 6);
    //         assertEq(s_commitReveal2.s_lastfulfilledRound(), round - 1);
    //         assertEq(s_commitReveal2.s_currentRound(), round);

    //         // *** Lets Fail on Phase2 and deactivates 7 operators, Consumer refunds some rounds

    //         // ***Phase0: Off-chain: Commit Submission
    //         // *************************************
    //         // to avoid stack too deep error
    //         // for (uint256 i; i < 10; i++) {
    //         //     (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
    //         //     (vs[i], rs[i], ss[i]) = vm.sign(
    //         //         s_anvilDefaultPrivateKeys[i],
    //         //         _getTypedDataHash(startTimestamp, cvs[i])
    //         //     );
    //         // }
    //         mine(s_activeNetworkConfig.phaseDuration[0]);

    //         // ***Phase1: On-chain: Commit Submission Request
    //         // *** The leadernode requests the operators to submit their cv
    //         // *************************************
    //         requestedToSubmitCVIndices = new uint256[](7);
    //         requestedToSubmitCVIndices[0] = 0;
    //         requestedToSubmitCVIndices[1] = 1;
    //         requestedToSubmitCVIndices[2] = 2;
    //         requestedToSubmitCVIndices[3] = 3;
    //         requestedToSubmitCVIndices[4] = 5;
    //         requestedToSubmitCVIndices[5] = 6;
    //         requestedToSubmitCVIndices[6] = 7;
    //         s_commitReveal2.requestToSubmitCV(requestedToSubmitCVIndices);
    //         mine(s_activeNetworkConfig.phaseDuration[1]);

    //         // ***Phase2: On-chain: Commit Submission
    //         // *** The operators do not submit their cv
    //         // *************************************
    //         mine(s_activeNetworkConfig.phaseDuration[2]);

    //         // ***Phase3: The operators get slashed and the process halts
    //         // *************************************
    //         vm.startPrank(LEADERNODE);
    //         s_commitReveal2.phase2FailedAndRestart();
    //         assertEq(s_commitReveal2.getActivatedOperatorsLength(), 1);
    //         assertEq(s_commitReveal2.s_currentRound(), round);
    //         assertEq(s_commitReveal2.s_isInProcess(), 1);

    //         // *** The consumer refunds the rounds 1,2,3,4
    //         // *************************************
    //         s_consumerExample.refund(3);
    //         s_consumerExample.refund(4);
    //         s_consumerExample.refund(2);
    //         s_consumerExample.refund(1);

    //         // *** The process starts again
    //         // *************************************
    //         // everybody activates again
    //         for (uint256 i; i < s_anvilDefaultAddresses.length; i++) {
    //             if (i == 4) {
    //                 continue;
    //             }
    //             vm.startPrank(s_anvilDefaultAddresses[i]);
    //             s_commitReveal2.depositAndActivate{
    //                 value: s_activeNetworkConfig.activationThreshold
    //             }();
    //             vm.stopPrank();
    //         }
    //         vm.startPrank(LEADERNODE);
    //         s_commitReveal2.restartOrUpdateCurrentRound();

    //         // *** round 5 started
    //         round = 5;
    //     }
}
