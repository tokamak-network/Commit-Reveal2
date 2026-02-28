// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {CommitReveal2BLS} from "./../../src/CommitReveal2BLS.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BLS} from "./../../src/libraries/BLS.sol";
import {NetworkHelperConfig} from "./../../script/NetworkHelperConfig.s.sol";

contract BaselineGas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    // *** Gas variables
    uint256[] public s_submitMerkleRootGas;
    uint256[] public s_generateRandomNumberGas;

    CommitReveal2BLS public commitReveal2Bls;
    NetworkHelperConfig networkHelperConfig;
    NetworkHelperConfig.NetworkConfig activeNetworkConfig;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_numOfTests = 10;
        s_callbackGas = 90000;

        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAddresses(32);
    }

    function _deployContracts() internal {
        // ** Deploy CommitReveal2
        address commitRevealAddress;
        (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).runForTest();
        s_commitReveal2 = CommitReveal2(commitRevealAddress);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
    }

    function _deployBLSContracts() internal {
        // ** Deploy CommitReveal2BLS

        networkHelperConfig = new NetworkHelperConfig();
        activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();

        vm.startBroadcast(activeNetworkConfig.deployer);
        commitReveal2Bls = new CommitReveal2BLS{
            value: activeNetworkConfig.activationThreshold
        }(
            activeNetworkConfig.activationThreshold,
            activeNetworkConfig.flatFee,
            activeNetworkConfig.name,
            activeNetworkConfig.version,
            activeNetworkConfig.offChainSubmissionPeriod,
            activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
            activeNetworkConfig.onChainSubmissionPeriod,
            activeNetworkConfig.offChainSubmissionPeriodPerOperator,
            activeNetworkConfig.onChainSubmissionPeriodPerOperator,
            activeNetworkConfig.maxGasPrice,
            address(0)
        );
        vm.stopBroadcast();
    }

    function test_commitReveal2Gas() public {
        string memory gasOutput;
        string memory gasOutputMax;
        string memory gasOutput2;
        string memory calldataSizeOutput;
        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployContracts();
            _depositAndActivateOperators(s_operatorAddresses);
            s_submitMerkleRootGas = new uint256[](s_numOfTests);
            s_generateRandomNumberGas = new uint256[](s_numOfTests);

            uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                s_commitReveal2.requestRandomNumber{value: requestFee * 11 / 10}(90000);
                vm.stopPrank();
            }
            for (uint256 i; i < s_numOfTests; i++) {
                _setSCoCvRevealOrders(s_privateKeys);
                vm.startPrank(LEADERNODE);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;

                s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                s_generateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
                vm.stopPrank();
            }

            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            // For generateRandomNumber - use average except index 0
            gasOutput = vm.serializeUint(
                "gasObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getAverageExceptIndex0(s_generateRandomNumberGas)
            );

            // For generateRandomNumber - use max except index 0
            gasOutputMax = vm.serializeUint(
                "gasObjectMax",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getMaxExceptIndex0(s_generateRandomNumberGas)
            );

            // For submitMerkleRoot - use any value except index 0 (since it's constant)
            gasOutput2 = vm.serializeUint(
                "gasObject2",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                s_submitMerkleRootGas[1] // Just use index 1 since it's constant
            );

            // For generateRandomNumber calldata size - measure for each numOfOperators
            calldataSizeOutput = vm.serializeUint(
                "calldataSizeObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                abi.encodeWithSelector(
                    s_commitReveal2.generateRandomNumber.selector, s_secretSigRSs, s_packedVs, s_packedRevealOrders
                ).length
            );
        }

        // Create final JSON output
        string memory finalOutput =
            vm.serializeString("commitReveal2Gas", "generateRandomNumber_numOfOperators_gasUsed_average", gasOutput);
        finalOutput =
            vm.serializeString("commitReveal2Gas", "generateRandomNumber_numOfOperators_gasUsed_max", gasOutputMax);
        finalOutput = vm.serializeString("commitReveal2Gas", "submitMerkleRoot_numOfOperators_gasUsed", gasOutput2);
        finalOutput = vm.serializeString(
            "commitReveal2Gas", "generateRandomNumber_numOfOperators_calldataSizeInBytes", calldataSizeOutput
        );

        // Add submitMerkleRoot calldata size (constant)
        finalOutput = vm.serializeUint(
            "commitReveal2Gas",
            "submitMerkleRoot_calldataSizeInBytes",
            abi.encodeWithSelector(s_commitReveal2.submitMerkleRoot.selector, type(uint256).max).length
        );

        vm.writeJson(finalOutput, s_gasReportPath, ".commitReveal2Gas");
    }

    function test_commitReveal2BLSGas() public {
        string memory gasOutput;
        string memory gasOutputMax;
        string memory gasOutput2;
        string memory calldataSizeOutput;
        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            _deployBLSContracts();
            for (uint256 i; i < s_numOfOperators; i++) {
                vm.startPrank(s_operatorAddresses[i]);
                BLS.G1Point memory pubKey = _blsg1mul(G1_GENERATOR(), bytes32(s_operatorPrivateKeys[i]));
                BLS.G2Point memory popMessage = BLS.hashToG2(abi.encodePacked(s_operatorAddresses[i]));
                BLS.G2Point memory pop = _blsg2mul(popMessage, bytes32(s_operatorPrivateKeys[i]));
                commitReveal2Bls.depositAndActivate{
                    value: activeNetworkConfig.activationThreshold
                }(pubKey, pop);
                vm.stopPrank();
            }
            s_submitMerkleRootGas = new uint256[](s_numOfTests);
            s_generateRandomNumberGas = new uint256[](s_numOfTests);

            uint256 requestFee = commitReveal2Bls.estimateRequestPrice(s_callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(s_anyAddress);
                commitReveal2Bls.requestRandomNumber{value: requestFee * 11 / 10}(90000);
                vm.stopPrank();
            }
            bytes32[] memory ss;
            BLS.G2Point memory sig0;
            for (uint256 i; i < s_numOfTests; i++) {
                _setSCoCvRevealOrdersBLS(s_privateKeys, commitReveal2Bls);
                bytes32 merkleRoot = _createMerkleRoot(s_cvs);
                BLS.G2Point memory messagePoint = BLS.toG2(BLS.Fp2(0, 0, 0, merkleRoot));
                ss = new bytes32[](s_numOfOperators);
                ss[0] = s_secrets[0];
                sig0 = _blsg2mul(messagePoint, bytes32(s_privateKeys[s_activatedOperators[0]]));
                for (uint256 j = 1; j < s_numOfOperators; j++) {
                    ss[j] = s_secrets[j];
                    BLS.G2Point memory sig = _blsg2mul(messagePoint, bytes32(s_privateKeys[s_activatedOperators[j]]));
                    sig0 = BLS.add(sig0, sig);
                }
                vm.startPrank(LEADERNODE);
                commitReveal2Bls.submitMerkleRoot(merkleRoot, sig0);
                s_submitMerkleRootGas[i] = vm.lastCallGas().gasTotalUsed;

                commitReveal2Bls.generateRandomNumber(ss, s_packedRevealOrders);
                s_generateRandomNumberGas[i] = vm.lastCallGas().gasTotalUsed;
                vm.stopPrank();
            }

            string memory numOfOperatorsString = Strings.toString(s_numOfOperators);
            // For generateRandomNumber - use average except index 0
            gasOutput = vm.serializeUint(
                "gasObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getAverageExceptIndex0(s_generateRandomNumberGas)
            );

            // For generateRandomNumber - use max except index 0
            gasOutputMax = vm.serializeUint(
                "gasObjectMax",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                _getMaxExceptIndex0(s_generateRandomNumberGas)
            );

            // For submitMerkleRoot - use any value except index 0 (since it's constant)
            gasOutput2 = vm.serializeUint(
                "gasObject2",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                s_submitMerkleRootGas[1] // Just use index 1 since it's constant
            );

            // For generateRandomNumber calldata size - measure for each numOfOperators
            calldataSizeOutput = vm.serializeUint(
                "calldataSizeObject",
                bytes(numOfOperatorsString).length == 1
                    ? string.concat("0", numOfOperatorsString)
                    : numOfOperatorsString,
                abi.encodeWithSelector(
                    commitReveal2Bls.generateRandomNumber.selector, ss, s_packedRevealOrders
                ).length
            );
        }

        // Create final JSON output
        string memory finalOutput = vm.serializeString(
            "commitReveal2BLSGas", "generateRandomNumber_numOfOperators_gasUsed_average", gasOutput
        );
        finalOutput = vm.serializeString(
            "commitReveal2BLSGas", "generateRandomNumber_numOfOperators_gasUsed_max", gasOutputMax
        );
        finalOutput =
            vm.serializeString("commitReveal2BLSGas", "submitMerkleRoot_numOfOperators_gasUsed", gasOutput2);
        finalOutput = vm.serializeString(
            "commitReveal2BLSGas",
            "generateRandomNumber_numOfOperators_calldataSizeInBytes",
            calldataSizeOutput
        );

        // Add submitMerkleRoot calldata size (constant)
        BLS.G2Point memory emptySig;
        finalOutput = vm.serializeUint(
            "commitReveal2BLSGas",
            "submitMerkleRoot_calldataSizeInBytes",
            abi.encodeWithSelector(commitReveal2Bls.submitMerkleRoot.selector, type(uint256).max, emptySig)
            .length
        );

        vm.writeJson(finalOutput, s_gasReportPath, ".commitReveal2BLSGas");
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

    function _u(uint256 x) internal pure returns (bytes32) {
        return bytes32(x);
    }
}
