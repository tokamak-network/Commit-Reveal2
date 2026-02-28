// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./../shared/BaseTest.t.sol";
import {BLS} from "./../../src/libraries/BLS.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract BLSPairingPrecompileGas is BaseTest {
    uint256 public s_numOfTests;
    uint256[] public s_pairingGas;
    BLSPairingPrecompileHarness private s_harness;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 10;
        setOperatorAddresses(32);
        s_harness = new BLSPairingPrecompileHarness();
    }

    function test_blsPairingPrecompileGas() public {
        string memory gasOutput;
        string memory calldataSizeOutput;
        bytes32 messageHash = keccak256("pairing precompile gas");
        BLS.G2Point memory messagePoint = BLS.toG2(BLS.Fp2(0, 0, 0, messageHash));

        for (uint256 numOperators = 2; numOperators <= 32; numOperators++) {
            BLS.G1Point[] memory g1Points = new BLS.G1Point[](numOperators + 1);
            BLS.G2Point[] memory g2Points = new BLS.G2Point[](numOperators + 1);
            g1Points[0] = NEGATED_G1_GENERATOR();

            BLS.G2Point memory sig = _blsg2mul(messagePoint, bytes32(s_operatorPrivateKeys[0]));
            for (uint256 i = 1; i < numOperators; i++) {
                BLS.G2Point memory sigPart = _blsg2mul(messagePoint, bytes32(s_operatorPrivateKeys[i]));
                sig = BLS.add(sig, sigPart);
            }
            g2Points[0] = sig;

            for (uint256 i = 1; i <= numOperators; i++) {
                bytes32 sk = bytes32(s_operatorPrivateKeys[i - 1]);
                g1Points[i] = _blsg1mul(G1_GENERATOR(), sk);
                g2Points[i] = messagePoint;
            }

            bytes memory input = _packPairingInput(g1Points, g2Points);
            s_pairingGas = new uint256[](s_numOfTests);
            for (uint256 i; i < s_numOfTests; i++) {
                (bool ok, uint256 gasUsed) = s_harness.pairingRaw(input);
                s_pairingGas[i] = gasUsed;
                assertTrue(ok);
            }

            string memory numOfOperatorsString = Strings.toString(numOperators);
            string memory paddedKey = bytes(numOfOperatorsString).length == 1
                ? string.concat("0", numOfOperatorsString)
                : numOfOperatorsString;

            gasOutput = vm.serializeUint("gasObject", paddedKey, _getAverageExceptIndex0(s_pairingGas));
            calldataSizeOutput = vm.serializeUint(
                "calldataSizeObject", paddedKey, abi.encodeWithSelector(s_harness.pairingRaw.selector, input).length
            );
        }

        string memory finalOutput = vm.serializeString(
            "blsPairingPrecompileGas", "pairing_precompile_numOfOperators_gasUsed_average", gasOutput
        );
        finalOutput = vm.serializeString(
            "blsPairingPrecompileGas", "pairing_precompile_numOfOperators_calldataSizeInBytes", calldataSizeOutput
        );

        vm.writeJson(finalOutput, s_gasReportPath, ".blsPairingPrecompileGas");
    }

    function _packPairingInput(BLS.G1Point[] memory g1Points, BLS.G2Point[] memory g2Points)
        private
        pure
        returns (bytes memory input)
    {
        uint256 k = g1Points.length;
        require(k == g2Points.length);
        input = new bytes(0x180 * k);
        assembly ("memory-safe") {
            let data := add(input, 0x20)
            let g1 := g1Points
            let g2 := g2Points
            for { let i := 0 } lt(i, k) { i := add(i, 1) } {
                g1 := add(g1, 0x20)
                g2 := add(g2, 0x20)
                let dst := add(data, mul(0x180, i))
                mcopy(dst, mload(g1), 0x80)
                mcopy(add(dst, 0x80), mload(g2), 0x100)
            }
        }
    }

    function _blsg1mul(BLS.G1Point memory g1, bytes32 scalar) private view returns (BLS.G1Point memory) {
        BLS.G1Point[] memory points = new BLS.G1Point[](1);
        bytes32[] memory scalars = new bytes32[](1);

        points[0] = g1;
        scalars[0] = scalar;

        return BLS.msm(points, scalars);
    }

    function _blsg2mul(BLS.G2Point memory g2, bytes32 scalar) private view returns (BLS.G2Point memory) {
        BLS.G2Point[] memory points = new BLS.G2Point[](1);
        bytes32[] memory scalars = new bytes32[](1);

        points[0] = g2;
        scalars[0] = scalar;

        return BLS.msm(points, scalars);
    }

    function G1_GENERATOR() internal pure returns (BLS.G1Point memory) {
        return BLS.G1Point(
            _u(31827880280837800241567138048534752271),
            _u(88385725958748408079899006800036250932223001591707578097800747617502997169851),
            _u(11568204302792691131076548377920244452),
            _u(114417265404584670498511149331300188430316142484413708742216858159411894806497)
        );
    }

    function NEGATED_G1_GENERATOR() internal pure returns (BLS.G1Point memory) {
        return BLS.G1Point(
            _u(31827880280837800241567138048534752271),
            _u(88385725958748408079899006800036250932223001591707578097800747617502997169851),
            _u(22997279242622214937712647648895181298),
            _u(46816884707101390882112958134453447585552332943769894357249934112654335001290)
        );
    }

    function _u(uint256 x) internal pure returns (bytes32) {
        return bytes32(x);
    }
}

contract BLSPairingPrecompileHarness {
    function pairingRaw(bytes calldata input) external view returns (bool ok, uint256 gasUsed) {
        assembly ("memory-safe") {
            let len := input.length
            if iszero(eq(len, mul(0x180, div(len, 0x180)))) { revert(0, 0) }
            let m := mload(0x40)
            calldatacopy(m, input.offset, len)
            let g := gas()
            ok := staticcall(gas(), 0x0f, m, len, 0x00, 0x20)
            gasUsed := sub(g, gas())
            ok := and(ok, and(eq(returndatasize(), 0x20), mload(0x00)))
        }
    }
}
