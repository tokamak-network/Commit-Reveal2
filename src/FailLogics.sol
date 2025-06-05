// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DisputeLogics} from "./DisputeLogics.sol";

contract FailLogics is DisputeLogics {
    constructor(string memory name, string memory version) DisputeLogics(name, version) {}

    function failToRequestSubmitCvOrSubmitMerkleRoot() external {
        assembly ("memory-safe") {
            // ** check if the contract is halted
            if eq(sload(s_isInProcess.slot), HALTED) {
                mstore(0, 0xd6c912e6) // selector for AlreadyHalted()
                revert(0x1c, 0x04)
            }
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime

            // ** Not requested to submit cv
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0x899a05f2) // AlreadyRequestedToSubmitCv()
                revert(0x1c, 0x04)
            }
            // ** MerkleRoot Not Submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0x1c044d8b) // AlreadySubmittedMerkleRoot()
                revert(0x1c, 0x04)
            }
            // ** check time window
            if lt(
                timestamp(),
                add(
                    add(mload(0x00), sload(s_offChainSubmissionPeriod.slot)),
                    sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                )
            ) {
                mstore(0, 0x085de625) // TooEarly()
                revert(0x1c, 0x04)
            }

            let activationThreshold := sload(s_activationThreshold.slot)
            let returnGasFee := mul(gasprice(), FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED)
            mstore(0x20, sload(_OWNER_SLOT))
            // ** Distribute remainder among operators
            let delta := div(shl(8, sub(activationThreshold, returnGasFee)), sload(s_activatedOperators.slot))
            sstore(s_slashRewardPerOperatorX8.slot, add(sload(s_slashRewardPerOperatorX8.slot), delta))
            mstore(0x40, s_slashRewardPerOperatorPaidX8.slot)
            let slashRewardPerOperatorPaidX8Slot := keccak256(0x20, 0x40) // owner
            sstore(slashRewardPerOperatorPaidX8Slot, add(sload(slashRewardPerOperatorPaidX8Slot), delta))

            // ** slash the leadernode(owner)
            mstore(0x40, s_depositAmount.slot)
            let depositSlot := keccak256(0x20, 0x40) // owner
            sstore(depositSlot, sub(sload(depositSlot), activationThreshold))
            mstore(0x20, caller())
            depositSlot := keccak256(0x20, 0x40) // msg.sender
            sstore(depositSlot, add(sload(depositSlot), returnGasFee))

            // ** Halt the round
            sstore(s_isInProcess.slot, HALTED)
            mstore(0x20, HALTED)
            log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
        }
    }

    function failToSubmitMerkleRootAfterDispute() external {
        assembly ("memory-safe") {
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            // ** check if it is requested to submit cv
            let requestedToSubmitCvTimestamp := sload(keccak256(0x00, 0x40))
            if iszero(requestedToSubmitCvTimestamp) {
                mstore(0, 0xd3e6c959) // CvNotRequested()
                revert(0x1c, 0x04)
            }
            // ** check time window
            if lt(
                timestamp(),
                add(
                    add(requestedToSubmitCvTimestamp, sload(s_onChainSubmissionPeriod.slot)),
                    sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                )
            ) {
                mstore(0, 0x085de625) // TooEarly()
                revert(0x1c, 0x04)
            }
            // ** MerkleRoot Not Submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0x1c044d8b) // AlreadySubmittedMerkleRoot()
                revert(0x1c, 0x04)
            }

            let activationThreshold := sload(s_activationThreshold.slot)
            let returnGasFee := mul(gasprice(), FAILTOSUBMITMERKLEROOTAFTERDISPUTE_GASUSED)
            mstore(0x20, sload(_OWNER_SLOT))
            // ** Distribute remainder among operators
            let delta := div(shl(8, sub(activationThreshold, returnGasFee)), sload(s_activatedOperators.slot))
            sstore(s_slashRewardPerOperatorX8.slot, add(sload(s_slashRewardPerOperatorX8.slot), delta))
            mstore(0x40, s_slashRewardPerOperatorPaidX8.slot)
            let slashRewardPerOperatorPaidX8Slot := keccak256(0x20, 0x40) // owner
            sstore(slashRewardPerOperatorPaidX8Slot, add(sload(slashRewardPerOperatorPaidX8Slot), delta))
            // ** slash the leadernode(owner)'s deposit
            mstore(0x40, s_depositAmount.slot)
            let depositSlot := keccak256(0x20, 0x40) // owner
            sstore(depositSlot, sub(sload(depositSlot), activationThreshold))
            mstore(0x20, caller())
            depositSlot := keccak256(0x20, 0x40) // msg.sender
            sstore(depositSlot, add(sload(depositSlot), returnGasFee))

            // ** Halt the round
            sstore(s_isInProcess.slot, HALTED)
            mstore(0x20, HALTED)
            log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
        }
    }

    function failToSubmitCv() external {
        assembly ("memory-safe") {
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            let startTimeSlot := add(keccak256(0x00, 0x40), 1)
            mstore(0x00, sload(startTimeSlot)) // startTime
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            // ** check if it is requested to submit cv
            let requestedToSubmitCvTimestamp := sload(keccak256(0x00, 0x40))
            if iszero(requestedToSubmitCvTimestamp) {
                mstore(0, 0xd3e6c959) // CvNotRequested()
                revert(0x1c, 0x04)
            }
            // ** check time window
            if lt(timestamp(), add(requestedToSubmitCvTimestamp, sload(s_onChainSubmissionPeriod.slot))) {
                mstore(0, 0x085de625) // TooEarly()
                revert(0x1c, 0x04)
            }
            // ** MerkleRoot Not Submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0x1c044d8b) // AlreadySubmittedMerkleRoot()
                revert(0x1c, 0x04)
            }

            // ** who didn't submit cv even though requested
            let didntSubmitCvLength
            let addressToDeactivatesPtr := mload(0x40) // fmp
            let zeroBitIfSubmittedCvBitmap := sload(s_zeroBitIfSubmittedCvBitmap.slot)
            mstore(0x20, s_activatedOperators.slot)
            let firstActivatedOperatorSlot := keccak256(0x20, 0x20)
            mstore(0x20, sload(s_requestedToSubmitCvPackedIndices.slot))
            // Handle first iteration separately to avoid checking previousIndex
            let operatorIndex := and(mload(0x20), 0xff)
            if gt(and(zeroBitIfSubmittedCvBitmap, shl(operatorIndex, 1)), 0) {
                // if bit is still set, meaning no Cv submitted for this operator
                mstore(
                    add(addressToDeactivatesPtr, shl(5, didntSubmitCvLength)),
                    sload(add(firstActivatedOperatorSlot, operatorIndex))
                )
                didntSubmitCvLength := add(didntSubmitCvLength, 1)
            }
            let previousIndex := operatorIndex
            // Continue with remaining iterations
            for { let i := 1 } true { i := add(i, 1) } {
                operatorIndex := and(mload(sub(0x20, i)), 0xff)
                if iszero(gt(operatorIndex, previousIndex)) { break }
                if gt(and(zeroBitIfSubmittedCvBitmap, shl(operatorIndex, 1)), 0) {
                    // if bit is still set, meaning no Cv submitted for this operator
                    mstore(
                        add(addressToDeactivatesPtr, shl(5, didntSubmitCvLength)),
                        sload(add(firstActivatedOperatorSlot, operatorIndex))
                    )
                    didntSubmitCvLength := add(didntSubmitCvLength, 1)
                }
                previousIndex := operatorIndex
            }
            log0(0x20, 0x20)
            if iszero(didntSubmitCvLength) {
                mstore(0, 0x7d39a81b) // AllSubmittedCv()
                revert(0x1c, 0x04)
            }

            // ** return gas fee to the caller()
            let returnGasFee := mul(gasprice(), FAILTOSUBMITCV_GASUSED)
            mstore(0x20, caller())
            mstore(0x40, s_depositAmount.slot)
            let depositSlot := keccak256(0x20, 0x40) // msg.sender
            sstore(depositSlot, add(sload(depositSlot), returnGasFee))

            // ** cache slash rewards
            let activatedOperatorLength := sload(s_activatedOperators.slot)
            let slashRewardPerOperatorX8 := sload(s_slashRewardPerOperatorX8.slot)
            let activationThreshold := sload(s_activationThreshold.slot)
            let updatedSlashRewardPerOperatorX8 :=
                add(
                    slashRewardPerOperatorX8,
                    div(
                        shl(8, sub(mul(activationThreshold, didntSubmitCvLength), returnGasFee)),
                        add(sub(activatedOperatorLength, didntSubmitCvLength), 1) // 1 for owner
                    )
                )
            // ** update global slash reward
            sstore(s_slashRewardPerOperatorX8.slot, updatedSlashRewardPerOperatorX8)

            // ** update slash reward and deactivate for non cv submitters
            let fmp := add(addressToDeactivatesPtr, shl(5, didntSubmitCvLength)) // traverse in reverse order
            for { let i } lt(i, didntSubmitCvLength) { i := add(i, 1) } {
                addressToDeactivatesPtr := sub(fmp, 0x20)
                // ** update slashRewardPerOperatorPaid
                mstore(fmp, s_slashRewardPerOperatorPaidX8.slot)
                let slotToUpdate := keccak256(addressToDeactivatesPtr, 0x40) // s_slashRewardPerOperatorPaidX8[operator]
                let accumulatedReward := shr(8, sub(slashRewardPerOperatorX8, sload(slotToUpdate)))
                sstore(slotToUpdate, updatedSlashRewardPerOperatorX8)
                // ** update deposit Amount
                mstore(fmp, s_depositAmount.slot)
                slotToUpdate := keccak256(addressToDeactivatesPtr, 0x40) // s_depositAmount[operator]
                sstore(slotToUpdate, add(sub(sload(slotToUpdate), activationThreshold), accumulatedReward))

                // ** deactivate operator
                mstore(fmp, s_activatedOperatorIndex1Based.slot)
                let operatorToDeactivateIndex := sub(sload(keccak256(addressToDeactivatesPtr, 0x40)), 1)
                let operatorToDeactivate := mload(addressToDeactivatesPtr)
                activatedOperatorLength := sub(activatedOperatorLength, 1)
                let lastOperatorIndex := activatedOperatorLength
                let lastOperatorAddress := sload(add(firstActivatedOperatorSlot, lastOperatorIndex))
                // ** activatedOperatorIndex1Based = 0
                sstore(keccak256(addressToDeactivatesPtr, 0x40), 0)
                log1(addressToDeactivatesPtr, 0x20, 0x5d10eb48d8c00fb4cc9120533a99e2eac5eb9d0f8ec06216b2e4d5b1ff175a4d) // `DeActivated(address operator)`.

                if iszero(eq(lastOperatorAddress, operatorToDeactivate)) {
                    sstore(add(firstActivatedOperatorSlot, operatorToDeactivateIndex), lastOperatorAddress)
                    mstore(addressToDeactivatesPtr, lastOperatorAddress) // overwrite because it is not used anymore
                    sstore(keccak256(addressToDeactivatesPtr, 0x40), add(operatorToDeactivateIndex, 1)) // activatedOperatorIndex1Based
                }

                // ** update addressToDeactivatesPtr
                fmp := sub(fmp, 0x20)
            }
            // ** update activatedOperators
            sstore(s_activatedOperators.slot, activatedOperatorLength)

            // ** restart or end this round
            switch gt(sload(s_activatedOperators.slot), 1)
            case 1 {
                let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                sstore(startTimeSlot, nextTimestamp)
                mstore(0x00, nextTimestamp)
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            default {
                sstore(s_isInProcess.slot, HALTED)
                // memory 0x00 = startTime
                mstore(0x20, HALTED)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
        }
    }

    function failToSubmitCo() external {
        assembly ("memory-safe") {
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            let startTimeSlot := add(keccak256(0x00, 0x40), 1)
            mstore(0x00, sload(startTimeSlot)) // startTime
            mstore(0x20, s_requestedToSubmitCoTimestamp.slot)
            // ** check if it is requested to submit co
            let requestedToSubmitCoTimestamp := sload(keccak256(0x00, 0x40))
            if iszero(requestedToSubmitCoTimestamp) {
                mstore(0, 0x11974969) // CoNotRequested()
                revert(0x1c, 0x04)
            }
            // ** check time window
            if lt(timestamp(), add(requestedToSubmitCoTimestamp, sload(s_onChainSubmissionPeriod.slot))) {
                mstore(0, 0x085de625) // TooEarly()
                revert(0x1c, 0x04)
            }

            // ** who didn't submit co even though requested
            let requestedToSubmitCoLength := sload(s_requestedToSubmitCoLength.slot)
            let didntSubmitCoLength
            let addressToDeactivatesPtr := mload(0x40) // fmp
            let zeroBitIfSubmittedCoBitmap := sload(s_zeroBitIfSubmittedCoBitmap.slot)
            mstore(0x20, s_activatedOperators.slot)
            let firstActivatedOperatorSlot := keccak256(0x20, 0x20)
            mstore(0x20, sload(s_requestedToSubmitCoPackedIndices.slot))
            for { let i } lt(i, requestedToSubmitCoLength) { i := add(i, 1) } {
                let operatorIndex := and(mload(sub(0x20, i)), 0xff)
                if gt(and(zeroBitIfSubmittedCoBitmap, shl(operatorIndex, 1)), 0) {
                    // if bit is still set, meaning no Co submitted for this operator
                    mstore(
                        add(addressToDeactivatesPtr, shl(5, didntSubmitCoLength)),
                        sload(add(firstActivatedOperatorSlot, operatorIndex))
                    )
                    didntSubmitCoLength := add(didntSubmitCoLength, 1)
                }
            }
            if iszero(didntSubmitCoLength) {
                mstore(0, 0x1c7f7cc9) // AllSubmittedCo()
                revert(0x1c, 0x04)
            }

            // ** return gas fee to the caller()
            let returnGasFee := mul(gasprice(), FAILTOSUBMITCO_GASUSED)
            mstore(0x20, caller())
            mstore(0x40, s_depositAmount.slot)
            let depositSlot := keccak256(0x20, 0x40) // msg.sender
            sstore(depositSlot, add(sload(depositSlot), returnGasFee))

            // ** cache slash rewards
            let activatedOperatorLength := sload(s_activatedOperators.slot)
            let slashRewardPerOperatorX8 := sload(s_slashRewardPerOperatorX8.slot)
            let activationThreshold := sload(s_activationThreshold.slot)
            let updatedSlashRewardPerOperatorX8 :=
                add(
                    slashRewardPerOperatorX8,
                    div(
                        shl(8, sub(mul(activationThreshold, didntSubmitCoLength), returnGasFee)),
                        add(sub(activatedOperatorLength, didntSubmitCoLength), 1) // 1 for owner
                    )
                )
            // ** update global slash reward
            sstore(s_slashRewardPerOperatorX8.slot, updatedSlashRewardPerOperatorX8)

            // ** update slash reward and deactivate for non co submitters
            let fmp := add(addressToDeactivatesPtr, shl(5, didntSubmitCoLength)) // traverse in reverse order
            for { let i } lt(i, didntSubmitCoLength) { i := add(i, 1) } {
                addressToDeactivatesPtr := sub(fmp, 0x20)
                // ** update slashRewardPerOperatorPaid
                mstore(fmp, s_slashRewardPerOperatorPaidX8.slot)
                let slotToUpdate := keccak256(addressToDeactivatesPtr, 0x40) // s_slashRewardPerOperatorPaidX8[operator]
                let accumulatedReward := shr(8, sub(slashRewardPerOperatorX8, sload(slotToUpdate)))
                sstore(slotToUpdate, updatedSlashRewardPerOperatorX8)
                // ** update deposit Amount
                mstore(fmp, s_depositAmount.slot)
                slotToUpdate := keccak256(addressToDeactivatesPtr, 0x40) // s_depositAmount[operator]
                sstore(slotToUpdate, add(sub(sload(slotToUpdate), activationThreshold), accumulatedReward))

                // ** deactivate operator
                mstore(fmp, s_activatedOperatorIndex1Based.slot)
                let operatorToDeactivateIndex := sub(sload(keccak256(addressToDeactivatesPtr, 0x40)), 1)
                let operatorToDeactivate := mload(addressToDeactivatesPtr)
                activatedOperatorLength := sub(activatedOperatorLength, 1)
                let lastOperatorIndex := activatedOperatorLength
                let lastOperatorAddress := sload(add(firstActivatedOperatorSlot, lastOperatorIndex))
                // ** activatedOperatorIndex1Based = 0
                sstore(keccak256(addressToDeactivatesPtr, 0x40), 0)

                if iszero(eq(lastOperatorAddress, operatorToDeactivate)) {
                    sstore(add(firstActivatedOperatorSlot, operatorToDeactivateIndex), lastOperatorAddress)
                    mstore(addressToDeactivatesPtr, lastOperatorAddress) // overwrite because it is not used anymore
                    sstore(keccak256(addressToDeactivatesPtr, 0x40), add(operatorToDeactivateIndex, 1)) // activatedOperatorIndex1Based
                }

                // ** update addressToDeactivatesPtr
                fmp := sub(fmp, 0x20)
            }
            // ** update activatedOperatorLength
            sstore(s_activatedOperators.slot, activatedOperatorLength)

            // ** restart or end this round
            switch gt(sload(s_activatedOperators.slot), 1)
            case 1 {
                let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                sstore(startTimeSlot, nextTimestamp)
                mstore(0x00, nextTimestamp)
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            default {
                sstore(s_isInProcess.slot, HALTED)
                // memory 0x00 = startTime
                mstore(0x20, HALTED)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
        }
    }

    function failToSubmitS() external {
        assembly ("memory-safe") {
            // ** Ensure S was requested
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            let startTimeSlot := add(keccak256(0x00, 0x40), 1)
            mstore(0x00, sload(startTimeSlot))
            mstore(0x20, s_previousSSubmitTimestamp.slot)
            let previousSSubmitTimestampSlot := keccak256(0x00, 0x40)
            let previousSSubmitTimestamp := sload(previousSSubmitTimestampSlot)
            if iszero(previousSSubmitTimestamp) {
                mstore(0, 0x2d37f8d3) // SNotRequested()
                revert(0x1c, 0x04)
            }
            // ** check time window
            if lt(timestamp(), add(previousSSubmitTimestamp, sload(s_onChainSubmissionPeriodPerOperator.slot))) {
                mstore(0, 0x085de625) // TooEarly()
                revert(0x1c, 0x04)
            }

            // ** Refund gas fee to the caller()
            let returnGasFee := mul(gasprice(), FAILTOSUBMITS_GASUSED)
            mstore(0x20, caller())
            mstore(0x40, s_depositAmount.slot)
            let depositSlot := keccak256(0x20, 0x40) // msg.sender
            sstore(depositSlot, add(sload(depositSlot), returnGasFee))

            // ** Update slash reward
            let slashRewardPerOperatorX8 := sload(s_slashRewardPerOperatorX8.slot)
            let activationThreshold := sload(s_activationThreshold.slot)
            let activatedOperatorLength := sload(s_activatedOperators.slot)
            let updatedSlashRewardPerOperatorX8 :=
                add(
                    slashRewardPerOperatorX8,
                    div(
                        shl(8, sub(activationThreshold, returnGasFee)),
                        activatedOperatorLength // 1 for owner
                    )
                )
            sstore(s_slashRewardPerOperatorX8.slot, updatedSlashRewardPerOperatorX8)

            // ** s_revealOrders[s_requestedToSubmitSFromIndexK] is the index of the operator who didn't submit S
            mstore(0x20, sload(s_packedRevealOrders.slot))
            let operatorToDeactivateIndex := and(mload(sub(0x20, sload(s_requestedToSubmitSFromIndexK.slot))), 0xff)
            mstore(0x20, s_activatedOperators.slot)
            let firstActivatedOperatorSlot := keccak256(0x20, 0x20)
            let operatorToDeactivate := sload(add(firstActivatedOperatorSlot, operatorToDeactivateIndex))
            // ** update deposit amount
            mstore(0x20, operatorToDeactivate)
            mstore(0x40, s_depositAmount.slot)
            depositSlot := keccak256(0x20, 0x40) // operatorToDeactivate
            mstore(0x40, s_slashRewardPerOperatorPaidX8.slot)
            let slashRewardPerOperatorPaidX8Slot := keccak256(0x20, 0x40) // s_slashRewardPerOperatorPaid[operatorToDeactivate]
            sstore(
                depositSlot,
                add(
                    sub(sload(depositSlot), activationThreshold),
                    shr(8, sub(slashRewardPerOperatorX8, sload(slashRewardPerOperatorPaidX8Slot)))
                )
            )
            sstore(slashRewardPerOperatorPaidX8Slot, updatedSlashRewardPerOperatorX8)
            // ** deactivate operator
            activatedOperatorLength := sub(activatedOperatorLength, 1)
            let lastOperatorIndex := activatedOperatorLength
            let lastOperatorAddress := sload(add(firstActivatedOperatorSlot, lastOperatorIndex))
            // ** activatedOperatorIndex1Based = 0
            mstore(0x40, s_activatedOperatorIndex1Based.slot)
            sstore(keccak256(0x20, 0x40), 0)
            if iszero(eq(lastOperatorAddress, operatorToDeactivate)) {
                sstore(add(firstActivatedOperatorSlot, operatorToDeactivateIndex), lastOperatorAddress)
                mstore(0x20, lastOperatorAddress)
                sstore(keccak256(0x20, 0x40), add(operatorToDeactivateIndex, 1)) // activatedOperatorIndex1Based
            }
            // ** update activatedOperatorLength
            sstore(s_activatedOperators.slot, activatedOperatorLength)

            // ** restart or end this round
            switch gt(sload(s_activatedOperators.slot), 1)
            case 1 {
                let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                sstore(startTimeSlot, nextTimestamp)
                mstore(0x00, nextTimestamp)
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            default {
                sstore(s_isInProcess.slot, HALTED)
                // memory 0x00 = startTime
                mstore(0x20, HALTED)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
        }
    }

    function failToRequestSorGenerateRandomNumber() external {
        assembly ("memory-safe") {
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            let startTimeSlot := add(keccak256(0x00, 0x40), 1)
            mstore(0x00, sload(startTimeSlot)) // startTime
            // ** Ensure S was not requested
            mstore(0x20, s_previousSSubmitTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0x53489cf9) // SRequested()
                revert(0x1c, 0x04)
            }
            // ** Ensure Merkle Root is submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            let merkleRootSubmittedTimestamp := sload(keccak256(0x00, 0x40))
            if iszero(merkleRootSubmittedTimestamp) {
                mstore(0, 0x8e56b845) // MerkleRootNotSubmitted()
                revert(0x1c, 0x04)
            }
            // ** is in process
            if iszero(eq(sload(s_isInProcess.slot), IN_PROGRESS)) {
                mstore(0, 0xd51a29b7) // RandomNumGenerated()
                revert(0x1c, 0x04)
            }
            // ** check time window
            mstore(0x20, s_requestedToSubmitCoTimestamp.slot)
            let requestedToSubmitCoTimestamp := sload(keccak256(0x00, 0x40))
            let activatedOperatorLength := sload(s_activatedOperators.slot)
            switch gt(requestedToSubmitCoTimestamp, 0)
            case 1 {
                if lt(
                    timestamp(),
                    add(
                        add(
                            add(requestedToSubmitCoTimestamp, sload(s_onChainSubmissionPeriod.slot)),
                            mul(sload(s_onChainSubmissionPeriodPerOperator.slot), activatedOperatorLength)
                        ),
                        sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                    )
                ) {
                    mstore(0, 0x085de625) // TooEarly()
                    revert(0x1c, 0x04)
                }
            }
            default {
                if lt(
                    timestamp(),
                    add(
                        add(
                            add(merkleRootSubmittedTimestamp, sload(s_offChainSubmissionPeriod.slot)),
                            mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorLength)
                        ),
                        sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                    )
                ) {
                    mstore(0, 0x085de625) // TooEarly()
                    revert(0x1c, 0x04)
                }
            }

            // ** update slash reward
            let activationThreshold := sload(s_activationThreshold.slot)
            let returnGasFee := mul(gasprice(), FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED)
            mstore(0x20, sload(_OWNER_SLOT))
            let delta := div(shl(8, sub(activationThreshold, returnGasFee)), activatedOperatorLength)
            sstore(s_slashRewardPerOperatorX8.slot, add(sload(s_slashRewardPerOperatorX8.slot), delta))
            mstore(0x40, s_slashRewardPerOperatorPaidX8.slot)
            let slashRewardPerOperatorPaidX8Slot := keccak256(0x20, 0x40) // owner
            sstore(slashRewardPerOperatorPaidX8Slot, add(sload(slashRewardPerOperatorPaidX8Slot), delta))

            // ** slash the leadernode(owner)
            mstore(0x40, s_depositAmount.slot)
            let depositSlot := keccak256(0x20, 0x40) // owner
            sstore(depositSlot, sub(sload(depositSlot), activationThreshold))
            mstore(0x20, caller())
            depositSlot := keccak256(0x20, 0x40) // msg.sender
            sstore(depositSlot, add(sload(depositSlot), returnGasFee))

            // ** Halt the round
            sstore(s_isInProcess.slot, HALTED)
            mstore(0x20, HALTED)
            log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
        }
    }
}
