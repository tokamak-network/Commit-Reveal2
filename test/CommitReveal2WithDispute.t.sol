// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2L1} from "./../src/test/CommitReveal2L1.sol";
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

        assertEq(
            s_commitReveal2.s_activationThreshold(),
            s_activeNetworkConfig.activationThreshold
        );
        assertEq(s_commitReveal2.s_flatFee(), s_activeNetworkConfig.flatFee);
        assertEq(
            s_commitReveal2.s_maxActivatedOperators(),
            s_activeNetworkConfig.maxActivatedOperators
        );
        assertEq(s_commitReveal2.owner(), LEADERNODE);

        DeployConsumerExample deployConsumerExample = new DeployConsumerExample();
        s_consumerExample = deployConsumerExample
            .deployConsumerExampleUsingConfig(address(s_commitReveal2));
    }

    function test_includingWholeDispute() public {
        console2.log("test_includingWholeDispute");

        // *** 10 operators deposit and activate
        // *************************************
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_commitReveal2.deposit{
                value: s_activeNetworkConfig.activationThreshold
            }();
            s_commitReveal2.activate();
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
        vm.startPrank(LEADERNODE);
        address[] memory activatedOperators = s_commitReveal2
            .getActivatedOperators();
        for (uint256 i; i < 10; i++) {
            assertEq(activatedOperators[i], s_anvilDefaultAddresses[i]);
        }

        // *** Request Random Number
        // *************************************
        uint256 requestFee = s_commitReveal2.estimateRequestPrice(
            s_consumerExample.CALLBACK_GAS_LIMIT(),
            tx.gasprice
        );
        vm.recordLogs();
        s_consumerExample.requestRandomNumber{value: requestFee}();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(
            entries[0].topics[0],
            keccak256("RandomNumberRequested(uint256,uint256,address[])")
        );
        (
            uint256 round,
            uint256 startTime,
            address[] memory activatedOperatorsAtThisRound
        ) = abi.decode(entries[0].data, (uint256, uint256, address[]));
        (, uint256 startTimestamp, , ) = s_commitReveal2.s_requestInfo(round);

        // *** Phase0: Off-chain: Commit Submission
        // *************************************
        bytes32[] memory secrets = new bytes32[](10);
        bytes32[] memory cos = new bytes32[](10);
        bytes32[] memory cvs = new bytes32[](10);
        uint8[] memory vs = new uint8[](10);
        bytes32[] memory rs = new bytes32[](10);
        bytes32[] memory ss = new bytes32[](10);
        for (uint256 i; i < 10; i++) {
            (secrets[i], cos[i], cvs[i]) = _generateSCoCv();
            (vs[i], rs[i], ss[i]) = vm.sign(
                s_anvilDefaultPrivateKeys[i],
                _getTypedDataHash(startTimestamp, cvs[i])
            );
        }
        mine(s_activeNetworkConfig.phaseDuration[0]);

        // *** Phase1: On-chain: Commit Submission Request
        // *** The leadernode requests the operators index 1,3 to submit their cv
        // *************************************
        uint256[] memory requestedToSubmitCVIndices = new uint256[](2);
        requestedToSubmitCVIndices[0] = 1;
        requestedToSubmitCVIndices[1] = 3;
        s_commitReveal2.requestToSubmitCV(requestedToSubmitCVIndices);
        mine(s_activeNetworkConfig.phaseDuration[1]);

        // *** Phase2: On-chain: Commit Submission
        // *** The operators index 1,3 submit their cv
        // *************************************
        vm.stopPrank();
        for (uint256 i; i < requestedToSubmitCVIndices.length; i++) {
            vm.startPrank(
                s_anvilDefaultAddresses[requestedToSubmitCVIndices[i]]
            );
            s_commitReveal2.submitCV(cvs[requestedToSubmitCVIndices[i]]);
            vm.stopPrank();
        }
        mine(s_activeNetworkConfig.phaseDuration[2]);

        // *** Phase3: On-chain:Merkle Root Submission
        // *************************************
        bytes32 merkleRoot = _createMerkleRoot(cvs);
        vm.startPrank(LEADERNODE);
        s_commitReveal2.submitMerkleRoot(merkleRoot);
        mine(s_activeNetworkConfig.phaseDuration[3]);

        // ***Phase4: Off-chain: Reveal-1 Submission
        // *************************************
        mine(s_activeNetworkConfig.phaseDuration[4]);
        // done

        // ***Phase5: On-chain: Reveal-1 Submission Request
        // *** The leadernode requests the operators index 5, 8, 3 to submit their co
        // *************************************
        uint256[] memory requestedToSubmitCOIndices = new uint256[](3);
        requestedToSubmitCOIndices[0] = 5;
        requestedToSubmitCOIndices[1] = 8;
        requestedToSubmitCOIndices[2] = 3;
        bytes32[] memory phase5Cvs = new bytes32[](2); // index 3 already submitted cv in phase2
        phase5Cvs[0] = cvs[5];
        phase5Cvs[1] = cvs[8];
        uint8[] memory phase5Vs = new uint8[](2);
        bytes32[] memory phase5Rs = new bytes32[](2);
        bytes32[] memory phase5Ss = new bytes32[](2);
        phase5Vs[0] = vs[5];
        phase5Vs[1] = vs[8];
        phase5Rs[0] = rs[5];
        phase5Rs[1] = rs[8];
        phase5Ss[0] = ss[5];
        phase5Ss[1] = ss[8];
        s_commitReveal2.requestToSubmitCO(
            requestedToSubmitCOIndices,
            phase5Cvs,
            phase5Vs,
            phase5Rs,
            phase5Ss
        );
        mine(s_activeNetworkConfig.phaseDuration[5]);

        // ***Phase6: On-chain: Reveal-1 Submission
        // *** The operators index 5, 8, 3 submit their co
        // *************************************
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[5]);
        s_commitReveal2.submitCO(cos[5]);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[8]);
        s_commitReveal2.submitCO(cos[8]);
        vm.stopPrank();
        vm.startPrank(s_anvilDefaultAddresses[3]);
        s_commitReveal2.submitCO(cos[3]);
        vm.stopPrank();
        mine(s_activeNetworkConfig.phaseDuration[6]);

        // ***Phase7: Off-chain: Reveal-2 Submission
        // *** Calculate the reveal order
        // *************************************
        uint256 operatorsLength = activatedOperators.length;
        uint256[] memory diffs = new uint256[](operatorsLength);
        uint256[] memory revealOrders = new uint256[](operatorsLength);
        uint256 rv = uint256(keccak256(abi.encodePacked(cos)));
        for (uint256 i; i < operatorsLength; i++) {
            diffs[i] = _diff(rv, uint256(cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);
        mine(s_activeNetworkConfig.phaseDuration[7]);

        // ***Phase8: On-chain: Reveal-2 Submission Request
        // *** The leadernode requests the operators from order index k 3 to submit their s
        // *** The operators who have already submitted cvs in phase2 and phase5: 1, 3, 5, 8
        // *************************************
        // in descending order
        CommitReveal2L1.Signature[]
            memory signatures = new CommitReveal2L1.Signature[](10 - 4);
        signatures[0].v = vs[9];
        signatures[0].r = rs[9];
        signatures[0].s = ss[9];
        signatures[1].v = vs[7];
        signatures[1].r = rs[7];
        signatures[1].s = ss[7];
        signatures[2].v = vs[6];
        signatures[2].r = rs[6];
        signatures[2].s = ss[6];
        signatures[3].v = vs[4];
        signatures[3].r = rs[4];
        signatures[3].s = ss[4];
        signatures[4].v = vs[2];
        signatures[4].r = rs[2];
        signatures[4].s = ss[2];
        signatures[5].v = vs[0];
        signatures[5].r = rs[0];
        signatures[5].s = ss[0];
        vm.startPrank(LEADERNODE);
        s_commitReveal2.requestToSubmitSFromIndex(3, cos, signatures);
        mine(s_activeNetworkConfig.phaseDuration[8]);

        // ***Phase9: On-chain: Reveal-2 Submission
        // *** The operators from order index k 3 submit their s
        // *************************************
        vm.stopPrank();
        for (uint256 i = 3; i < operatorsLength; i++) {
            vm.startPrank(s_anvilDefaultAddresses[revealOrders[i]]);
            s_commitReveal2.submitS(secrets[revealOrders[i]]);
            vm.stopPrank();
        }
    }
}
