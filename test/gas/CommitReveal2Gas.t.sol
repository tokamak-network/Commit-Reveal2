// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2, Vm} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./../../script/NetworkHelperConfig.s.sol";
import {Sort} from "./../shared/Sort.sol";
import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";

contract CommitReveal2Gas is BaseTest, CommitReveal2Helper {
    uint256 public s_numOfTests;

    // *** Gas variables
    uint256[] public s_depositGas;
    uint256[] public s_activateGas;
    uint256[] public s_deactivateGas;
    uint256[] public s_depositAndActivateGas;
    uint256[] public s_requestRandomNumberGas;
    uint256[] public s_submitMerkleRootGas;
    uint256[] public s_generateRandomNumberGas;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        vm.stopPrank();
        s_numOfTests = 10;

        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
    }

    function _getAverageExceptIndex0(uint256[] memory arr) internal pure returns (uint256) {
        uint256 sum;
        uint256 len = arr.length;
        for (uint256 i = 1; i < len; i++) {
            sum += arr[i];
        }
        return sum / (len - 1);
    }

    function _consoleAverageExceptIndex0(uint256[] memory arr, string memory msg1) internal pure {
        console2.log(msg1, _getAverageExceptIndex0(arr));
    }

    function _deployContracts() internal {
        // ** Deploy CommitReveal2
        address commitRevealAddress;
        (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).run();
        s_commitReveal2 = CommitReveal2(commitRevealAddress);
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
        // ** Deploy ConsumerExample
        s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));
    }

    function test_activateDeactivate() public {
        setOperatorAdresses(32);
        s_networkHelperConfig = new NetworkHelperConfig();
        s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();

        _deployContracts();

        // *** Deposit And Activate Operators
        s_numOfOperators = 32;
        for (uint256 i; i < s_numOfOperators; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.deposit{value: s_activeNetworkConfig.activationThreshold}();
            vm.stopPrank();
        }
        for (uint256 i; i < s_numOfOperators; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.activate();
            vm.stopPrank();
            s_activateGas.push(vm.lastCallGas().gasTotalUsed);
        }
        assertEq(s_commitReveal2.getActivatedOperatorsLength(), s_numOfOperators);
        for (uint256 i; i < s_numOfOperators; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            s_commitReveal2.deactivate();
            vm.stopPrank();
            s_deactivateGas.push(vm.lastCallGas().gasTotalUsed);
        }
        assertEq(s_commitReveal2.getActivatedOperatorsLength(), 0);
        console2.log("activateGas, deactivateGas");
        console2.log(_getAverageExceptIndex0(s_activateGas), _getAverageExceptIndex0(s_deactivateGas));
        for (uint256 i; i < s_numOfOperators; i++) {
            console2.log(s_activateGas[i], s_deactivateGas[i]);
        }
    }

    error OnlyCoordinatorCanFulfill(address caller, address coordinator);

    function rawFulfillRandomNumber(uint256 round, uint256 randomNumber) external {
        require(msg.sender == address(s_commitReveal2), OnlyCoordinatorCanFulfill(msg.sender, address(s_commitReveal2)));
        fulfillRandomRandomNumber(round, randomNumber);
    }

    function fulfillRandomRandomNumber(uint256 requestId, uint256 randomNumber) internal {}

    function test_forCalculateRequestFeeWithoutCallback() public {
        console2.log("Without Callback Gas-----------------------");
        setOperatorAdresses(32);

        vm.startPrank(address(s_commitReveal2));
        ConsumerExample(payable(address(this))).rawFulfillRandomNumber(type(uint256).max, type(uint256).max);
        vm.stopPrank();
        uint256 callbackGas = vm.lastCallGas().gasTotalUsed;
        console2.log("callbackGas", callbackGas);
        callbackGas -= 21000; // base fee
        console2.log("Setting callbackGasLimit to", callbackGas);
        console2.log("--------------------");

        // ** Test
        for (s_numOfOperators = 2; s_numOfOperators <= 32; s_numOfOperators++) {
            // ** Deploy CommitReveal2 and ConsumerExample
            _deployContracts();

            // *** Deposit And Activate Operators
            for (uint256 i; i < s_numOfOperators; i++) {
                vm.startPrank(s_operatorAddresses[i]);
                s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
                s_depositAndActivateGas.push(vm.lastCallGas().gasTotalUsed);
            }
            // ** 1 -> 2 -> 12
            uint256[] memory revealOrders;
            uint256 requestFee = s_commitReveal2.estimateRequestPrice(callbackGas, tx.gasprice);
            for (uint256 i; i < s_numOfTests; i++) {
                vm.startPrank(address(this));
                s_commitReveal2.requestRandomNumber{value: requestFee}(uint32(callbackGas));
                vm.stopPrank();
                s_requestRandomNumberGas.push(vm.lastCallGas().gasTotalUsed);

                // ** Off-chain: Cv submission
                revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                // ** 2. submitMerkleRoot()
                vm.startPrank(LEADERNODE);
                mine(1);
                bytes32 merkleRoot = _createMerkleRoot(s_cvs);
                s_commitReveal2.submitMerkleRoot(merkleRoot);
                s_submitMerkleRootGas.push(vm.lastCallGas().gasTotalUsed);
                mine(1);

                // ** 12. generateRandomNumber()
                mine(1);
                s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                s_generateRandomNumberGas.push(vm.lastCallGas().gasTotalUsed);
                mine(1);
                vm.stopPrank();
            }

            console2.log("numOfOperators, requestRandomNumberGas, submitMerkleRootGas, generateRandomNumberGas");
            uint256 submitRootAverage = _getAverageExceptIndex0(s_submitMerkleRootGas);
            uint256 generateRandomNumberAverage = _getAverageExceptIndex0(s_generateRandomNumberGas);
            console2.log(
                s_numOfOperators,
                _getAverageExceptIndex0(s_requestRandomNumberGas),
                submitRootAverage,
                generateRandomNumberAverage
            );
            console2.log("total (submitRoot+generateRandomNumber):", submitRootAverage + generateRandomNumberAverage);
            console2.log(
                "generateRandomNumber Calldata Size:",
                abi.encodeWithSelector(
                    s_commitReveal2.generateRandomNumber.selector, s_secretSigRSs, s_packedVs, s_packedRevealOrders
                ).length
            );
            console2.log("--------------------");
        }
        console2.log(
            "submitMerkleRoot Calldata Size:",
            abi.encodeWithSelector(s_commitReveal2.submitMerkleRoot.selector, bytes32(type(uint256).max)).length
        );
        console2.log("=======================");
    }

    function test_optimisticCaseGasChart() public {
        setOperatorAdresses(10);
        for (s_numOfOperators = 2; s_numOfOperators < 10; s_numOfOperators++) {
            // ** Deploy CommitReveal2
            address commitRevealAddress;
            (commitRevealAddress, s_networkHelperConfig) = (new DeployCommitReveal2()).run();
            s_commitReveal2 = CommitReveal2(commitRevealAddress);
            s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
            // ** Deploy ConsumerExample
            s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));

            // *** Deposit And Activate Operators
            for (uint256 i; i < s_numOfOperators; i++) {
                vm.startPrank(s_operatorAddresses[i]);
                s_commitReveal2.depositAndActivate{value: s_activeNetworkConfig.activationThreshold}();
                vm.stopPrank();
                s_depositAndActivateGas.push(vm.lastCallGas().gasTotalUsed);
            }

            // ** 1 -> 2 -> 12
            s_requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);

            vm.startPrank(s_anyAddress);
            uint256[] memory revealOrders;
            for (uint256 i; i < s_numOfTests; i++) {
                s_consumerExample.requestRandomNumber{value: s_requestFee}();
                s_requestRandomNumberGas.push(vm.lastCallGas().gasTotalUsed);

                // ** Off-chain: Cv submission
                revealOrders = _setSCoCvRevealOrders(s_privateKeys);

                // ** 2. submitMerkleRoot()
                vm.startPrank(LEADERNODE);
                mine(1);
                s_commitReveal2.submitMerkleRoot(_createMerkleRoot(s_cvs));
                s_submitMerkleRootGas.push(vm.lastCallGas().gasTotalUsed);
                mine(1);

                // ** 12. generateRandomNumber()
                mine(1);
                s_commitReveal2.generateRandomNumber(s_secretSigRSs, s_packedVs, s_packedRevealOrders);
                s_generateRandomNumberGas.push(vm.lastCallGas().gasTotalUsed);
                mine(1);
            }
            console2.log("s_numOfOperators:", s_numOfOperators);
            _consoleAverageExceptIndex0(s_depositAndActivateGas, "depositAndActivateGas:");
            _consoleAverageExceptIndex0(s_requestRandomNumberGas, "requestRandomNumberGas:");
            _consoleAverageExceptIndex0(s_submitMerkleRootGas, "submitMerkleRootGas:");
            _consoleAverageExceptIndex0(s_generateRandomNumberGas, "generateRandomNumberGas:");
            console2.log("--------------------");
            vm.stopPrank();
        }
    }
}
