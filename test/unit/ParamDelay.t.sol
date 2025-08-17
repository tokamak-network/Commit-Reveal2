// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CommitReveal2} from "src/CommitReveal2.sol";

contract ParamDelayTest is Test {
    CommitReveal2 private s_commitReveal2;

    // Common constructor params
    uint256 private constant ACTIVATION_THRESHOLD = 1 ether;
    uint256 private constant FLAT_FEE = 0.01 ether;
    string private constant NAME = "CR2";
    string private constant VERSION = "1";
    uint256 private constant OFFCHAIN = 10;
    uint256 private constant DECISION = 5;
    uint256 private constant ONCHAIN = 20;
    uint256 private constant OFFCHAIN_PER_OP = 1;
    uint256 private constant ONCHAIN_PER_OP = 1;

    // Custom error selectors
    bytes4 private constant TOO_EARLY = 0x085de625;

    function setUp() public {
        s_commitReveal2 = new CommitReveal2{value: ACTIVATION_THRESHOLD}(
            ACTIVATION_THRESHOLD, FLAT_FEE, NAME, VERSION, OFFCHAIN, DECISION, ONCHAIN, OFFCHAIN_PER_OP, ONCHAIN_PER_OP
        );
    }

    function testEconomicParametersDelayAndExecute() public {
        // Propose new economic parameters
        uint256 newActivation = 2 ether;
        uint256 newFlatFee = 0.02 ether;
        s_commitReveal2.proposeEconomicParameters(newActivation, newFlatFee);

        // Should revert if executed before delay
        vm.expectRevert(TOO_EARLY);
        s_commitReveal2.executeSetEconomicParameters();

        // Move time forward just before the delay; still too early
        vm.warp(block.timestamp + s_commitReveal2.SET_DELAY_TIME() - 1);
        vm.expectRevert(TOO_EARLY);
        s_commitReveal2.executeSetEconomicParameters();

        // Move past the delay and execute
        vm.warp(block.timestamp + 2);
        s_commitReveal2.executeSetEconomicParameters();

        // Verify parameters updated
        assertEq(s_commitReveal2.s_activationThreshold(), newActivation, "activationThreshold not updated");
        assertEq(s_commitReveal2.s_flatFee(), newFlatFee, "flatFee not updated");
        assertEq(s_commitReveal2.s_economicParamsEffectiveTimestamp(), 0, "economic effective ts not cleared");
    }

    function testGasParametersDelayAndExecute() public {
        // Prepare gas parameters
        uint128 a = 12345;
        uint128 b = 67890;
        uint256 maxCb = 2_500_000;
        uint48 l1Upper = 21833;
        uint48 failCvOrRoot = 85386;
        uint48 failRootAfter = 82746;
        uint48 failReqSOrGen = 86242;
        uint48 failS = 122282;
        uint32 failCoBaseA = 95000;
        uint32 failCvBaseA = 95500;
        uint32 failBaseB = 110000;
        uint32 perOpA = 500;
        uint32 perOpB = 200;
        uint32 perDidntA = 15000;
        uint32 perDidntB = 24000;
        uint32 perReq = 500;

        // Propose
        s_commitReveal2.proposeGasParameters(
            a,
            b,
            maxCb,
            l1Upper,
            failCvOrRoot,
            failRootAfter,
            failReqSOrGen,
            failS,
            failCoBaseA,
            failCvBaseA,
            failBaseB,
            perOpA,
            perOpB,
            perDidntA,
            perDidntB,
            perReq
        );

        // Execute too early should revert
        vm.expectRevert(TOO_EARLY);
        s_commitReveal2.executeSetGasParameters();

        // Warp past delay and execute
        vm.warp(block.timestamp + s_commitReveal2.SET_DELAY_TIME() + 1);
        s_commitReveal2.executeSetGasParameters();

        (
            uint128 ra,
            uint128 rb,
            uint256 rMaxCb,
            uint48 rL1Upper,
            uint48 rFailCvOrRoot,
            uint48 rFailRootAfter,
            uint48 rFailReqSOrGen,
            uint48 rFailS,
            uint32 rFailCoBaseA,
            uint32 rFailCvBaseA,
            uint32 rFailBaseB,
            uint32 rPerOpA,
            uint32 rPerOpB,
            uint32 rPerDidntA,
            uint32 rPerDidntB,
            uint32 rPerReq
        ) = s_commitReveal2.getGasParameters();

        // Verify gas parameters updated
        assertEq(ra, a, "gas A mismatch");
        assertEq(rb, b, "gas B mismatch");
        assertEq(rMaxCb, maxCb, "maxCallbackGasLimit mismatch");
        assertEq(rL1Upper, l1Upper, "l1Upper mismatch");
        assertEq(rFailCvOrRoot, failCvOrRoot, "failCvOrRoot mismatch");
        assertEq(rFailRootAfter, failRootAfter, "failRootAfter mismatch");
        assertEq(rFailReqSOrGen, failReqSOrGen, "failReqSOrGen mismatch");
        assertEq(rFailS, failS, "failS mismatch");
        assertEq(rFailCoBaseA, failCoBaseA, "failCoBaseA mismatch");
        assertEq(rFailCvBaseA, failCvBaseA, "failCvBaseA mismatch");
        assertEq(rFailBaseB, failBaseB, "failBaseB mismatch");
        assertEq(rPerOpA, perOpA, "perOpA mismatch");
        assertEq(rPerOpB, perOpB, "perOpB mismatch");
        assertEq(rPerDidntA, perDidntA, "perDidntA mismatch");
        assertEq(rPerDidntB, perDidntB, "perDidntB mismatch");
        assertEq(rPerReq, perReq, "perReq mismatch");
        assertEq(s_commitReveal2.s_gasParamsEffectiveTimestamp(), 0, "gas effective ts not cleared");
    }
}
