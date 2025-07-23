// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2} from "forge-std/Test.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";

contract CallBackGas is BaseTest {
    address public s_anyAddress;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);

        s_anyAddress = makeAddr("any");
        vm.deal(s_anyAddress, 10000 ether);
        setOperatorAdresses(32);
    }

    function test_callbackGas() public {
        address callee = address(new Callee());
        Callee(callee).rawFulfillRandomNumber(type(uint256).max, type(uint256).max);
        Callee(callee).rawFulfillRandomNumber(type(uint256).max, type(uint256).max);
        uint256 directCallGasUsed = vm.lastCallGas().gasTotalUsed;
        console2.log("direct call gasUsed:", directCallGasUsed);

        address caller = address(new Caller(callee, directCallGasUsed - 21970));
        Caller(caller).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        Caller(caller).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        console2.log("callback call gasUsed:", vm.lastCallGas().gasTotalUsed);

        console2.log(address(s_anyAddress).code.length);
        caller = address(new Caller(s_anyAddress, directCallGasUsed - 21970));
        Caller(caller).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        Caller(caller).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        console2.log("without callback call gasUsed:", vm.lastCallGas().gasTotalUsed);

        address callerWithoutCallback = address(new CallerWithoutCallback(callee, directCallGasUsed - 21000));
        CallerWithoutCallback(callerWithoutCallback).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        CallerWithoutCallback(callerWithoutCallback).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        console2.log("without callback call gasUsed:", vm.lastCallGas().gasTotalUsed);

        address consoleGasUsedOfCallback = address(new ConsoleGasUsedOfCallback(callee, directCallGasUsed - 21000));
        ConsoleGasUsedOfCallback(consoleGasUsedOfCallback).fulFillRandomNumber(type(uint256).max, type(uint256).max);
        ConsoleGasUsedOfCallback(consoleGasUsedOfCallback).fulFillRandomNumber(type(uint256).max, type(uint256).max);
    }
}

contract Callee {
    uint256 public s_round;
    uint256 public s_randomNumber;

    function rawFulfillRandomNumber(uint256 round, uint256 randomNumber) external {
        s_round = round;
        s_randomNumber = randomNumber;
    }
}

contract Caller {
    address public s_callee;
    uint256 public s_callbackGasLimit;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    constructor(address callee, uint256 callbackGasLimit) {
        s_callee = callee;
        s_callbackGasLimit = callbackGasLimit;
    }

    function fulFillRandomNumber(uint256 round, uint256 randomNumber) external {
        assembly ("memory-safe") {
            mstore(0x00, 0x00fc98b8) // rawFulfillRandomNumber(uint256,uint256) selector
            mstore(0x20, round)
            mstore(0x40, randomNumber)
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) { revert(0, 0) }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            let callbackGasLimit := sload(s_callbackGasLimit.slot)
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            let consumer := sload(s_callee.slot)
            if gt(extcodesize(consumer), 0) {
                // call and return whether we succeeded. ignore return data
                // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
                if iszero(call(callbackGasLimit, consumer, 0, 0x1c, 0x44, 0, 0)) { revert(0, 0) }
            }
        }
    }
}

contract ConsoleGasUsedOfCallback {
    address public s_callee;
    uint256 public s_callbackGasLimit;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    constructor(address callee, uint256 callbackGasLimit) {
        s_callee = callee;
        s_callbackGasLimit = callbackGasLimit;
    }

    function fulFillRandomNumber(uint256 round, uint256 randomNumber) external {
        assembly ("memory-safe") {
            mstore(0x00, 0x00fc98b8) // rawFulfillRandomNumber(uint256,uint256) selector
            mstore(0x20, round)
            mstore(0x40, randomNumber)
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) { revert(0, 0) }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            let callbackGasLimit := sload(s_callbackGasLimit.slot)
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            let consumer := sload(s_callee.slot)
            if gt(extcodesize(consumer), 0) {
                // call and return whether we succeeded. ignore return data
                // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
                let gasStart := gas()
                pop(call(callbackGasLimit, consumer, 0, 0x1c, 0x44, 0, 0))
                mstore(0x00, sub(gasStart, gas()))
                log0(0x00, 0x20)
            }
        }
    }
}

contract CallerWithoutCallback {
    address public s_callee;
    uint256 public s_callbackGasLimit;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    constructor(address callee, uint256 callbackGasLimit) {
        s_callee = callee;
        s_callbackGasLimit = callbackGasLimit;
    }

    function fulFillRandomNumber(uint256 round, uint256 randomNumber) external {
        assembly ("memory-safe") {
            mstore(0x00, 0x00fc98b8) // rawFulfillRandomNumber(uint256,uint256) selector
            mstore(0x20, round)
            mstore(0x40, randomNumber)
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) { revert(0, 0) }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            let callbackGasLimit := sload(s_callbackGasLimit.slot)
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            let consumer := sload(s_callee.slot)
            if gt(extcodesize(consumer), 0) {
                // call and return whether we succeeded. ignore return data
                // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
                if iszero(true) { revert(0, 0) }
            }
        }
    }
}
