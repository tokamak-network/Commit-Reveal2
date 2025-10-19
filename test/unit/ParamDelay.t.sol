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

    uint256 maxGasPrice = 20 gwei;

    function setUp() public {
        s_commitReveal2 = new CommitReveal2{
            value: ACTIVATION_THRESHOLD
        }(
            ACTIVATION_THRESHOLD,
            FLAT_FEE,
            NAME,
            VERSION,
            OFFCHAIN,
            DECISION,
            ONCHAIN,
            OFFCHAIN_PER_OP,
            ONCHAIN_PER_OP,
            maxGasPrice,
            address(0) // TODO: Deploy MultisigTimelock first
        );
    }

    function testEconomicParametersGovernanceOnly() public {
        // Should revert when called by non-governance address
        uint256 newActivation = 2 ether;
        uint256 newFlatFee = 0.02 ether;

        vm.expectRevert(); // UnauthorizedGovernance error
        s_commitReveal2.setEconomicParameters(newActivation, newFlatFee);

        // Parameters should remain unchanged
        assertEq(s_commitReveal2.s_activationThreshold(), ACTIVATION_THRESHOLD, "activationThreshold should not change");
        assertEq(s_commitReveal2.s_flatFee(), FLAT_FEE, "flatFee should not change");
    }

    function testGasParametersGovernanceOnly() public {
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

        // Should revert when called by non-governance address
        vm.expectRevert(); // UnauthorizedGovernance error
        s_commitReveal2.setGasParameters(
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
            perReq,
            maxGasPrice
        );

        // Gas parameters should remain unchanged since the call should have reverted
    }
}
