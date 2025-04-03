// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2L1} from "./../../src/CommitReveal2L1.sol";

import {Test, console2} from "forge-std/Test.sol";

contract CommitReveal2CallbackTest is CommitReveal2L1 {
    constructor(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 maxActivatedOperators,
        string memory name,
        string memory version,
        uint256 offChainSubmissionPeriod,
        uint256 requestOrSubmitOrFailDecisionPeriod,
        uint256 onChainSubmissionPeriod,
        uint256 offChainSubmissionPeriodPerOperator,
        uint256 onChainSubmissionPeriodPerOperator
    )
        payable
        CommitReveal2L1(
            activationThreshold,
            flatFee,
            maxActivatedOperators,
            name,
            version,
            offChainSubmissionPeriod,
            requestOrSubmitOrFailDecisionPeriod,
            onChainSubmissionPeriod,
            offChainSubmissionPeriodPerOperator,
            onChainSubmissionPeriodPerOperator
        )
    {}

    function generateRandomNumber(
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint256[] calldata revealOrders
    ) external override {
        bytes32 domainSeparator = _domainSeparatorV4();
        assembly ("memory-safe") {
            let activatedOperatorsLength := sload(s_activatedOperators.slot)
            // ** check if all secrets are submitted
            if gt(activatedOperatorsLength, secrets.length) {
                mstore(0, 0xe0767fa4) // selector for InvalidSecretLength()
                revert(0x1c, 0x04)
            }

            // ** initialize cos and cvs arrays memory
            let cos := mload(0x40)
            mstore(cos, activatedOperatorsLength)
            let activatedOperatorsLengthInBytes := shl(5, activatedOperatorsLength)
            let cosDataPtr := add(cos, 0x20)
            let cvs := add(cosDataPtr, activatedOperatorsLengthInBytes)
            mstore(cvs, activatedOperatorsLength)
            mstore(0x40, add(cvs, add(0x20, activatedOperatorsLengthInBytes))) // update the free memory pointer

            let cvsDataPtr := add(cvs, 0x20)
            // ** get cos and cvs
            for { let i } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                mstore(0x00, calldataload(add(secrets.offset, shl(5, i))))
                let cosMemP := add(cosDataPtr, shl(5, i))
                mstore(cosMemP, keccak256(0x00, 0x20))
                mstore(add(cvsDataPtr, shl(5, i)), keccak256(cosMemP, 0x20))
            }

            // ** verify reveal order
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let rv := keccak256(cosDataPtr, activatedOperatorsLengthInBytes)
            let index := calldataload(revealOrders.offset)
            let revealBitmap := shl(index, 1)
            let before := _diff(rv, mload(add(cvsDataPtr, shl(5, index))))
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                index := calldataload(add(revealOrders.offset, shl(5, i)))
                revealBitmap := or(revealBitmap, shl(index, 1))
                let after := _diff(rv, mload(add(cvsDataPtr, shl(5, index))))
                if lt(before, after) {
                    mstore(0, 0x24f1948e) // selector for RevealNotInDescendingOrder()
                    revert(0x1c, 0x04)
                }
                before := after
            }
            if iszero(eq(revealBitmap, sub(shl(activatedOperatorsLength, 1), 1))) {
                mstore(0, 0xe3ae7cc0) // selector for WrongRevealOrder()
                revert(0x1c, 0x04)
            }

            // ** Create Merkle Root and verify it
            let hashCount := sub(activatedOperatorsLength, 1)
            let fmp := mload(0x40)
            mstore(fmp, hashCount)
            let hashesDataPtr := add(fmp, 0x20)
            let cvsPosInBytes
            let hashPosInBytes
            for { let i } lt(i, hashCount) { i := add(i, 1) } {
                switch lt(cvsPosInBytes, activatedOperatorsLengthInBytes)
                case 1 {
                    mstore(0x00, mload(add(cvsDataPtr, cvsPosInBytes)))
                    cvsPosInBytes := add(cvsPosInBytes, 0x20)
                }
                default {
                    mstore(0x00, mload(add(hashesDataPtr, hashPosInBytes)))
                    hashPosInBytes := add(hashPosInBytes, 0x20)
                }
                switch lt(cvsPosInBytes, activatedOperatorsLengthInBytes)
                case 1 {
                    mstore(0x20, mload(add(cvsDataPtr, cvsPosInBytes)))
                    cvsPosInBytes := add(cvsPosInBytes, 0x20)
                }
                default {
                    mstore(0x20, mload(add(hashesDataPtr, hashPosInBytes)))
                    hashPosInBytes := add(hashPosInBytes, 0x20)
                }
                mstore(add(hashesDataPtr, shl(5, i)), keccak256(0x00, 0x40))
            }
            if iszero(eq(mload(add(hashesDataPtr, shl(5, sub(hashCount, 1)))), sload(s_merkleRoot.slot))) {
                mstore(0, 0x624dc351) // selector for MerkleVerificationFailed()
                revert(0x1c, 0x04)
            }

            // ** verify signer
            let round := sload(s_currentRound.slot)
            mstore(0x00, round)
            mstore(0x20, s_requestInfo.slot)
            let currentRequestInfoSlot := keccak256(0x00, 0x40)
            mstore(fmp, MESSAGE_TYPEHASH_DIRECT) // typehash, overwrite the previous value, which is not used anymore
            let startTime := sload(add(currentRequestInfoSlot, 1))
            mstore(add(fmp, 0x20), startTime)
            mstore(add(fmp, 0x60), hex"1901") // prefix and version
            mstore(add(fmp, 0x62), domainSeparator)
            for { let i } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                // signature malleability prevention
                let s := calldataload(add(ss.offset, shl(5, i)))
                if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                    mstore(0, 0xbf4bf5b8) // selector for InvalidSignatureS()
                    revert(0x1c, 0x04)
                }
                mstore(add(fmp, 0x40), mload(add(cvsDataPtr, shl(5, i)))) // cv
                mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                mstore(0x20, and(calldataload(add(vs.offset, shl(5, i))), 0xff)) // v, is `and` necessary?
                mstore(0x40, calldataload(add(rs.offset, shl(5, i)))) // r
                mstore(0x60, s) // s
                let operatorAddress := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                if iszero(returndatasize()) {
                    mstore(0x00, 0x8baa579f) // selector for InvalidSignature()
                    revert(0x1c, 0x04)
                }
                mstore(0x00, operatorAddress)
                mstore(0x20, s_activatedOperatorIndex1Based.slot)
                if iszero(sload(keccak256(0x00, 0x40))) {
                    mstore(0x00, 0x1b256530) // selector for NotActivatedOperator()
                    revert(0x1c, 0x04)
                }
            }

            // ** create random number
            calldatacopy(fmp, secrets.offset, activatedOperatorsLengthInBytes) // overwrite the previous value, which is not used anymore
            let randomNumber := keccak256(fmp, activatedOperatorsLengthInBytes)
            let nextRound := add(round, 1)

            switch eq(nextRound, sload(s_requestCount.slot))
            case 1 {
                sstore(s_isInProcess.slot, COMPLETED)
                mstore(0x00, startTime)
                mstore(0x20, COMPLETED)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
            default {
                mstore(0x00, nextRound) // round
                mstore(0x20, s_requestInfo.slot)
                sstore(add(keccak256(0x00, 0x40), 1), timestamp())
                sstore(s_currentRound.slot, nextRound)
                mstore(0x00, timestamp())
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
            // ** reward the last revealer
            mstore(0x00, s_activatedOperators.slot)
            mstore(
                0x00,
                sload(
                    add(
                        keccak256(0x00, 0x20), // s_activatedOperators first data slot
                        calldataload(add(revealOrders.offset, sub(activatedOperatorsLengthInBytes, 0x20))) // last revealer index
                    )
                )
            ) // last revealer address
            mstore(0x20, s_depositAmount.slot)
            let lastRevealerDepositSlot := keccak256(0x00, 0x40)
            sstore(lastRevealerDepositSlot, add(sload(lastRevealerDepositSlot), sload(add(currentRequestInfoSlot, 2))))

            mstore(0x00, 0x00fc98b6) // wrong selector intentionally
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
            let callbackGasLimit := sload(add(currentRequestInfoSlot, 3))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            let consumer := sload(currentRequestInfoSlot)
            if iszero(extcodesize(consumer)) { return(0, 0) }
            // sload(add(currentRequestInfoSlot, 3)) == consumer
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            mstore(0x60, call(callbackGasLimit, consumer, 0, 0x1c, 0x44, 0, 0))
            log1(0x20, 0x60, 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a) // emit RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess
        }
    }
}

contract CallbackContract {
    function callback(uint256 a) external {}
}

contract CallbackCaller {
    CallbackContract public callbackContract;
    uint256 public callbackGas = 100;

    constructor(address _callbackContract) {
        callbackContract = CallbackContract(_callbackContract);
    }

    function callCallback(uint256 a) public {
        assembly ("memory-safe") {
            mstore(0x00, 0xff585caf)
            mstore(0x20, a)
            let _callbackGas := sload(callbackGas.slot)
            mstore(0x40, call(_callbackGas, sload(callbackContract.slot), 0, 0x1c, 0x24, 0, 0))
            log0(0x40, 0x20)
        }
    }

    function dontCallback(uint256 a) public {
        assembly ("memory-safe") {
            mstore(0x00, 0xff585caf)
            mstore(0x20, a)
            let _callbackGas := sload(callbackGas.slot)
            mstore(0x40, call(_callbackGas, sload(1), 0, 0x1c, 0x24, 0, 0))
            log0(0x40, 0x20)
        }
    }
}

contract CallbackGasTest is Test {
    CallbackContract public callbackContract;
    CallbackCaller public callbackCaller;

    function setUp() public {
        vm.deal(address(this), 10000 ether);
        vm.txGasPrice(10 gwei);

        callbackContract = new CallbackContract();
        callbackCaller = new CallbackCaller(address(callbackContract));
    }

    function test_callbackGas() public {
        callbackCaller.dontCallback(type(uint256).max);
        uint256 gas = vm.lastCallGas().gasTotalUsed;
        console2.log("dontCallback gas", gas);

        callbackCaller.callCallback(type(uint256).max);
        gas = vm.lastCallGas().gasTotalUsed;
        console2.log("callback gas", gas);

        callbackContract.callback(type(uint256).max);
        gas = vm.lastCallGas().gasTotalUsed;
        console2.log("direct callback gas", gas);
    }
}
