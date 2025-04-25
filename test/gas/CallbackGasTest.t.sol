// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2L1} from "./../../src/CommitReveal2L1.sol";

import {Test, console2} from "forge-std/Test.sol";

contract CommitReveal2CallbackTest is CommitReveal2L1 {
    constructor(
        uint256 activationThreshold,
        uint256 flatFee,
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
        SecretAndSigRS[] calldata secretSigRSs,
        uint256, // packedVs
        uint256 packedRevealOrders
    ) external override {
        bytes32 domainSeparator = _domainSeparatorV4();
        assembly ("memory-safe") {
            let activatedOperatorsLength := sload(s_activatedOperators.slot)
            // ** check if all secrets are submitted
            if gt(activatedOperatorsLength, secretSigRSs.length) {
                mstore(0, 0xe0767fa4) // selector for InvalidSecretLength()
                revert(0x1c, 0x04)
            }

            // ** initialize cos and cvs arrays memory, without length data
            let activatedOperatorsLengthInBytes := shl(5, activatedOperatorsLength)
            let cos := mload(0x40)
            let cvs := add(cos, activatedOperatorsLengthInBytes)
            let secrets := add(cvs, activatedOperatorsLengthInBytes)
            mstore(0x40, add(secrets, activatedOperatorsLengthInBytes)) // update the free memory pointer

            // ** get cos and cvs
            for { let i } lt(i, activatedOperatorsLengthInBytes) { i := add(i, 0x20) } {
                let secretMemP := add(secrets, i)
                mstore(secretMemP, calldataload(add(secretSigRSs.offset, mul(i, 3)))) // secret
                let cosMemP := add(cos, i)
                mstore(cosMemP, keccak256(secretMemP, 0x20))
                mstore(add(cvs, i), keccak256(cosMemP, 0x20))
            }

            // ** verify reveal order
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let rv := keccak256(cos, activatedOperatorsLengthInBytes)
            let index := and(packedRevealOrders, 0xff) // first reveal index
            let revealBitmap := shl(index, 1)
            let before := _diff(rv, mload(add(cvs, shl(5, index))))
            // revealOrdersOffset = 0x44
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                index := and(calldataload(sub(0x44, i)), 0xff)
                revealBitmap := or(revealBitmap, shl(index, 1))
                let after := _diff(rv, mload(add(cvs, shl(5, index))))
                if lt(before, after) {
                    mstore(0, 0x24f1948e) // selector for RevealNotInDescendingOrder()
                    revert(0x1c, 0x04)
                }
                before := after
            }
            if iszero(eq(revealBitmap, sub(shl(activatedOperatorsLength, 1), 1))) {
                mstore(0, 0x06efcba4) // selector for RevealOrderHasDuplicates()
                revert(0x1c, 0x04)
            }
            // ** Create Merkle Root and verify it
            let hashCountInBytes := sub(activatedOperatorsLengthInBytes, 0x20)
            let fmp := mload(0x40) // used to store the hashes
            let cvsPosInBytes
            let hashPosInBytes
            for { let i } lt(i, hashCountInBytes) { i := add(i, 0x20) } {
                switch lt(cvsPosInBytes, activatedOperatorsLengthInBytes)
                case 1 {
                    mstore(0x00, mload(add(cvs, cvsPosInBytes)))
                    cvsPosInBytes := add(cvsPosInBytes, 0x20)
                }
                default {
                    mstore(0x00, mload(add(fmp, hashPosInBytes)))
                    hashPosInBytes := add(hashPosInBytes, 0x20)
                }
                switch lt(cvsPosInBytes, activatedOperatorsLengthInBytes)
                case 1 {
                    mstore(0x20, mload(add(cvs, cvsPosInBytes)))
                    cvsPosInBytes := add(cvsPosInBytes, 0x20)
                }
                default {
                    mstore(0x20, mload(add(fmp, hashPosInBytes)))
                    hashPosInBytes := add(hashPosInBytes, 0x20)
                }
                mstore(add(fmp, i), keccak256(0x00, 0x40))
            }
            if iszero(eq(mload(add(fmp, sub(hashCountInBytes, 0x20))), sload(s_merkleRoot.slot))) {
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
            for { let i } lt(i, activatedOperatorsLengthInBytes) { i := add(i, 0x20) } {
                // signature malleability prevention
                let rSOffset := add(secretSigRSs.offset, add(mul(i, 3), 0x20))
                let s := calldataload(add(rSOffset, 0x20))
                if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                    mstore(0, 0xbf4bf5b8) // selector for InvalidSignatureS()
                    revert(0x1c, 0x04)
                }
                mstore(add(fmp, 0x40), mload(add(cvs, i))) // cv
                mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                mstore(0x20, and(calldataload(sub(0x24, shr(5, i))), 0xff)) // v, 0x24: packedVsOffset
                mstore(0x40, calldataload(rSOffset)) // r
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
            let randomNumber := keccak256(secrets, activatedOperatorsLengthInBytes)
            let nextRound := add(round, 1)

            switch eq(nextRound, sload(s_requestCount.slot))
            case 1 {
                sstore(s_isInProcess.slot, COMPLETED)
                mstore(0x00, startTime)
                mstore(0x20, COMPLETED)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            default {
                mstore(0x00, nextRound) // round
                mstore(0x20, s_requestInfo.slot)
                sstore(add(keccak256(0x00, 0x40), 1), timestamp())
                sstore(s_currentRound.slot, nextRound)
                mstore(0x00, timestamp())
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            // ** reward the flatFee to last revealer
            // ** reward the leaderNode (requestFee - flatFee) for submitMerkleRoot and generateRandomNumber
            mstore(0x00, s_activatedOperators.slot)
            mstore(
                0x00,
                sload(
                    add(
                        keccak256(0x00, 0x20), // s_activatedOperators first data slot
                        and(calldataload(sub(0x44, sub(activatedOperatorsLength, 1))), 0xff) // last revealer index, 0x44: revealOrdersOffset
                    )
                )
            ) // last revealer address
            mstore(0x20, s_depositAmount.slot)
            let depositSlot := keccak256(0x00, 0x40) // last revealer
            let flatFee := sload(s_flatFee.slot)
            sstore(depositSlot, add(sload(depositSlot), flatFee))
            // reward sload(add(currentRequestInfoSlot, 2)) - flatFee to the leader
            mstore(0x00, sload(_OWNER_SLOT))
            depositSlot := keccak256(0x00, 0x40) // leader
            sstore(depositSlot, add(sload(depositSlot), sub(sload(add(currentRequestInfoSlot, 2)), flatFee)))

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
            switch extcodesize(consumer)
            case 0 {
                mstore(0x60, 0)
                log1(0x20, 0x60, 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a) // emit RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess
            }
            default {
                // call and return whether we succeeded. ignore return data
                // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
                mstore(0x60, call(callbackGasLimit, consumer, 0, 0x1c, 0x44, 0, 0))
                log1(0x20, 0x60, 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a) // emit RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess
            }
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
