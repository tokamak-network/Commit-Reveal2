// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./CommitReveal2.sol";

contract CommitReveal2L1 is CommitReveal2 {
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
        CommitReveal2(
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

    function _calculateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        internal
        view
        override
        returns (uint256)
    {
        return (gasPrice * (callbackGasLimit + (211 * numOfOperators + 1344))) + s_flatFee;
    }

    function requestRandomNumber(uint32 callbackGasLimit) external payable override returns (uint256 newRound) {
        assembly ("memory-safe") {
            // ** check if the callbackGasLimit is within the limit
            if gt(callbackGasLimit, MAX_CALLBACK_GAS_LIMIT) {
                mstore(0, 0x1cf7ab79) // selector for ExceedCallbackGasLimit()
                revert(0x1c, 0x04)
            }
            // ** check if there are enough activated operators
            let activatedOperatorsLength := sload(s_activatedOperators.slot)
            if lt(activatedOperatorsLength, 2) {
                mstore(0, 0x77599fd9) // selector for NotEnoughActivatedOperators()
                revert(0x1c, 0x04)
            }
            // ** check if the leader has enough deposit
            mstore(0x00, sload(_OWNER_SLOT))
            mstore(0x20, s_depositAmount.slot)
            if lt(sload(keccak256(0x00, 0x40)), sload(s_activationThreshold.slot)) {
                mstore(0, 0xc0013a5a) // selector for LeaderLowDeposit()
                revert(0x1c, 0x04)
            }
            // ** check if the fee amount is enough
            // submitRoot l2GasUsed = 47216
            // generateRandomNumber l2GasUsed = 21118.97⋅N + 87117.53
            // let fmp := mload(0x40) // cache the free memory pointer
            if lt(
                callvalue(),
                add(
                    mul(gasprice(), add(callbackGasLimit, add(mul(211, activatedOperatorsLength), 1344))),
                    sload(s_flatFee.slot)
                )
            ) {
                mstore(0, 0x5945ea56) // selector for InsufficientAmount()
                revert(0x1c, 0x04)
            }

            newRound := sload(s_requestCount.slot)
            sstore(s_requestCount.slot, add(newRound, 1))

            // ** flip the bit
            // calculate the storage slot corresponding to the round
            // wordPos = round >> 8
            mstore(0, shr(8, newRound))
            mstore(0x20, s_roundBitmap.slot)
            // the slot of self[wordPos] is keccak256(abi.encode(wordPos, self.slot))
            let slot := keccak256(0, 0x40)
            // mask = 1 << bitPos = 1 << (round & 0xff)
            // self[wordPos] ^= mask
            sstore(slot, xor(sload(slot), shl(and(newRound, 0xff), 1)))
            let startTime
            if eq(sload(s_isInProcess.slot), COMPLETED) {
                sstore(s_currentRound.slot, newRound)
                sstore(s_isInProcess.slot, IN_PROGRESS)
                startTime := timestamp()
                mstore(0, startTime)
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
            mstore(0x00, newRound)
            mstore(0x20, s_requestInfo.slot)
            let requestInfoSlot := keccak256(0x00, 0x40)
            sstore(requestInfoSlot, caller())
            sstore(add(requestInfoSlot, 1), startTime)
            sstore(add(requestInfoSlot, 2), callvalue())
            sstore(add(requestInfoSlot, 3), callbackGasLimit)
        }
    }
}
