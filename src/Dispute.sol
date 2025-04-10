// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OperatorManager} from "./OperatorManager.sol";
import {CommitReveal2Storage} from "./CommitReveal2Storage.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract Dispute is EIP712, OperatorManager, CommitReveal2Storage {
    constructor(string memory name, string memory version) EIP712(name, version) {}

    function requestToSubmitCv(uint256 length, uint256 packedIndices) external onlyOwner {
        assembly ("memory-safe") {
            if iszero(length) {
                mstore(0, 0xbf557497) // ZeroLength()
                revert(0x1c, 0x04)
            }
            if gt(length, MAX_ACTIVATED_OPERATORS) {
                mstore(0, 0x12466af8) // LengthExceedsMax()
                revert(0x1c, 0x04)
            }
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            let requestedToSubmitCvTimestampSlot := keccak256(0x00, 0x40)
            if gt(sload(requestedToSubmitCvTimestampSlot), 0) {
                mstore(0, 0x899a05f2) // AlreadyRequestedToSubmitCv()
                revert(0x1c, 0x04)
            }
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0xf6b442ac) // MerkleRootIsSubmitted()
                revert(0x1c, 0x04)
            }
            let maxIndex := sub(sload(s_activatedOperators.slot), 1) // max index
            let checkDuplicate
            for { let i } lt(i, length) { i := add(i, 1) } {
                let index := and(calldataload(sub(0x24, i)), 0xff)
                if gt(index, maxIndex) {
                    // if greater than max index
                    mstore(0, 0x63df8171) // InvalidIndex()
                    revert(0x1c, 0x04)
                }
                let mask := shl(index, 1)
                if gt(and(checkDuplicate, mask), 0) {
                    // if already set
                    mstore(0, 0x7a69f8d3) // DuplicateIndices()
                    revert(0x1c, 0x04)
                }
                checkDuplicate := or(checkDuplicate, mask)
            }
            sstore(requestedToSubmitCvTimestampSlot, timestamp())
            sstore(s_requestedToSubmitCvLength.slot, length)
            sstore(s_requestedToSubmitCvPackedIndices.slot, packedIndices)
            sstore(s_zeroBitIfSubmittedCvBitmap.slot, 0xffffffff) // set all bits to 1
            mstore(0x20, packedIndices)
            log1(0x00, 0x40, 0x18d0e75c02ebf9429b0b69ace609256eb9c9e12d5c9301a2d4a04fd7599b5cfc) // emit RequestedToSubmitCv(uint256 startTime, uint256 indices)
        }
    }

    function submitCv(bytes32 cv) external {
        assembly ("memory-safe") {
            mstore(0x00, caller())
            mstore(0x20, s_activatedOperatorIndex1Based.slot)
            let activatedOperatorIndex := sub(sload(keccak256(0x00, 0x40)), 1) // overflows when s_activatedOperatorIndex1Based is 0
            if gt(activatedOperatorIndex, MAX_OPERATOR_INDEX) {
                mstore(0, 0x1b256530) // NotActivatedOperator()
                revert(0x1c, 0x04)
            }
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime
            // ** can only submit cv if merkleRoot is not submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if gt(sload(keccak256(0x00, 0x40)), 0) {
                mstore(0, 0xf6b442ac) // MerkleRootIsSubmitted()
                revert(0x1c, 0x04)
            }
            sstore(add(s_cvs.slot, activatedOperatorIndex), cv)
            sstore(
                s_zeroBitIfSubmittedCvBitmap.slot,
                and(sload(s_zeroBitIfSubmittedCvBitmap.slot), not(shl(activatedOperatorIndex, 1)))
            ) // set to zero

            mstore(0x20, cv)
            log1(0x00, 0x40, 0x689880904ca6a1080ab52c3fd53043e57fddaa2af740366f4fd4275e91512438) // emit CvSubmitted(uint256 startTime, bytes32 cv, uint256 index)
        }
    }

    function failToRequestSubmitCvOrSubmitMerkleRoot() external {
        assembly ("memory-safe") {
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
                mstore(0, 0x7a69f8d3) // AlreadySubmittedMerkleRoot()
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
            log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
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
                mstore(0, 0x7a69f8d3) // AlreadySubmittedMerkleRoot()
                revert(0x1c, 0x04)
            }

            // ** who didn't submit cv even though requested
            let requestedToSubmitCvLength := sload(s_requestedToSubmitCvLength.slot)
            let didntSubmitCvLength
            let addressToDeactivatesPtr := mload(0x40) // fmp
            let zeroBitIfSubmittedCvBitmap := sload(s_zeroBitIfSubmittedCvBitmap.slot)
            mstore(0x20, s_activatedOperators.slot)
            let firstActivatedOperatorSlot := keccak256(0x20, 0x20)
            mstore(0x20, sload(s_requestedToSubmitCvPackedIndices.slot))
            for { let i } lt(i, requestedToSubmitCvLength) { i := add(i, 1) } {
                let operatorIndex := and(mload(sub(0x20, i)), 0xff)
                if gt(and(zeroBitIfSubmittedCvBitmap, shl(operatorIndex, 1)), 0) {
                    // if bit is still set, meaning no Cv submitted for this operator
                    mstore(
                        add(addressToDeactivatesPtr, shl(5, didntSubmitCvLength)),
                        sload(add(firstActivatedOperatorSlot, operatorIndex))
                    )
                    didntSubmitCvLength := add(didntSubmitCvLength, 1)
                }
            }
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
                sstore(startTimeSlot, timestamp())
                mstore(0x00, timestamp())
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
            default {
                sstore(s_isInProcess.slot, HALTED)
                // memory 0x00 = startTime
                mstore(0x20, HALTED)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
        }
    }

    function requestToSubmitCo(
        CvAndSigRS[] calldata cvRSsForCvsNotOnChain,
        uint256, // packedVsForCvsNotOnChain,
        uint256 indicesLength,
        uint256 indicesFirstCvNotOnChainRestCvOnChain
    ) external onlyOwner {
        bytes32 domainSeparator = _domainSeparatorV4();
        assembly ("memory-safe") {
            if iszero(indicesLength) {
                mstore(0, 0xbf557497) // ZeroLength()
                revert(0x1c, 0x04)
            }
            if gt(indicesLength, MAX_ACTIVATED_OPERATORS) {
                mstore(0, 0x12466af8) // LengthExceedsMax()
                revert(0x1c, 0x04)
            }

            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            let startTime := sload(add(keccak256(0x00, 0x40), 1))
            mstore(0x00, startTime)
            // ** can only request to submit co if merkleRoot is submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            let merkleRootSubmittedTimestamp := sload(keccak256(0x00, 0x40))
            if iszero(merkleRootSubmittedTimestamp) {
                mstore(0, 0x8e56b845) // MerkleRootNotSubmitted()
                revert(0x1c, 0x04)
            }
            // ** check if already requested to submit co
            mstore(0x20, s_requestedToSubmitCoTimestamp.slot)
            let requestedToSubmitCoTimestampSlot := keccak256(0x00, 0x40)
            if gt(sload(requestedToSubmitCoTimestampSlot), 0) {
                mstore(0, 0x13efcda2) // AlreadyRequestedToSubmitCo()
                revert(0x1c, 0x04)
            }
            // ** check time window
            if gt(
                timestamp(),
                add(
                    merkleRootSubmittedTimestamp,
                    add(sload(s_offChainSubmissionPeriod.slot), sload(s_requestOrSubmitOrFailDecisionPeriod.slot))
                )
            ) {
                mstore(0, 0xecdd1c29) // TooLate()
                revert(0x1c, 0x04)
            }

            // ** check cv status
            let operatorsLength := sload(s_activatedOperators.slot)
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            let requestedToSubmitCvTimestampSlot := keccak256(0x00, 0x40)
            // if not requested to submit cv, it means no cvs are on-chain
            let zeroBitIfSubmittedCvBitmap
            switch sload(requestedToSubmitCvTimestampSlot)
            case 0 {
                if iszero(eq(indicesLength, cvRSsForCvsNotOnChain.length)) {
                    mstore(0, 0xad029eb9)
                    revert(0x1c, 0x04) // AllCvsNotSubmitted()
                }
                sstore(requestedToSubmitCvTimestampSlot, 1) // set to 1 to indicate that cvs are on-chain
                zeroBitIfSubmittedCvBitmap := 0xffffffff // set all bits to 1
            }
            default { zeroBitIfSubmittedCvBitmap := sload(s_zeroBitIfSubmittedCvBitmap.slot) }

            // **
            let maxIndex := sub(operatorsLength, 1) // max index
            let checkDuplicate

            let fmp := mload(0x40) // fmp
            mstore(fmp, MESSAGE_TYPEHASH_DIRECT)
            mstore(add(fmp, 0x20), startTime) // startTime
            mstore(add(fmp, 0x60), hex"1901") // prefix and version
            mstore(add(fmp, 0x62), domainSeparator)

            for { let i } lt(i, cvRSsForCvsNotOnChain.length) { i := add(i, 1) } {
                // ** check duplicate
                let requestToSubmitCoIndex := and(calldataload(sub(0x64, i)), 0xff) // 0x64: indicesFirstCvNotOnChainRestCvOnChain
                if gt(requestToSubmitCoIndex, maxIndex) {
                    // if greater than max index
                    mstore(0, 0x63df8171) // InvalidIndex()
                    revert(0x1c, 0x04)
                }
                let mask := shl(requestToSubmitCoIndex, 1)
                if gt(and(checkDuplicate, mask), 0) {
                    // if already set
                    mstore(0, 0x7a69f8d3) // DuplicateIndices()
                    revert(0x1c, 0x04)
                }
                checkDuplicate := or(checkDuplicate, mask)

                // ** check signature
                let cvsRSsOffset := add(cvRSsForCvsNotOnChain.offset, mul(0x60, i))
                let s := calldataload(add(cvsRSsOffset, 0x40))
                if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                    mstore(0, 0xbf4bf5b8) // InvalidSignatureS()
                    revert(0x1c, 0x04)
                }
                mstore(add(fmp, 0x40), calldataload(cvsRSsOffset)) // cv
                mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                mstore(0x20, and(calldataload(sub(0x24, i)), 0xff)) // v, 0x24: packedVs offset
                mstore(0x40, calldataload(add(cvsRSsOffset, 0x20))) // r
                mstore(0x60, s)
                let operatorAddress := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                if iszero(returndatasize()) {
                    mstore(0x00, 0x8baa579f) // selector for InvalidSignature()
                    revert(0x1c, 0x04)
                }
                mstore(0x00, operatorAddress)
                mstore(0x20, s_activatedOperatorIndex1Based.slot)
                if iszero(eq(add(requestToSubmitCoIndex, 1), sload(keccak256(0x00, 0x40)))) {
                    mstore(0, 0x980c4296) // SignatureAndIndexDoNotMatch()
                    revert(0x1c, 0x04)
                }

                // ** submit cv on-chain
                sstore(add(s_cvs.slot, requestToSubmitCoIndex), calldataload(cvsRSsOffset)) // cv
                zeroBitIfSubmittedCvBitmap := and(zeroBitIfSubmittedCvBitmap, not(shl(requestToSubmitCoIndex, 1))) // set to zero
            }
            sstore(s_zeroBitIfSubmittedCvBitmap.slot, zeroBitIfSubmittedCvBitmap) // update bitmap

            // ** Operators who already submitted Cv on-chain, simply confirm it exists
            for { let i := cvRSsForCvsNotOnChain.length } lt(i, indicesLength) { i := add(i, 1) } {
                let requestToSubmitCoIndex := and(calldataload(sub(0x64, i)), 0xff) // 0x64: indicesFirstCvNotOnChainRestCvOnChain
                // ** check duplicate
                if gt(requestToSubmitCoIndex, maxIndex) {
                    // if greater than max index
                    mstore(0, 0x63df8171) // InvalidIndex()
                    revert(0x1c, 0x04)
                }
                let mask := shl(requestToSubmitCoIndex, 1)
                if gt(and(checkDuplicate, mask), 0) {
                    // if already set
                    mstore(0, 0x7a69f8d3) // DuplicateIndices()
                    revert(0x1c, 0x04)
                }
                checkDuplicate := or(checkDuplicate, mask)
                // ** check cv bitmap
                if gt(and(zeroBitIfSubmittedCvBitmap, mask), 0) {
                    // if bit is still set, meaning no Cv submitted for this operator
                    mstore(0, 0x03798920) // CvNotSubmitted()
                    revert(0x1c, 0x04)
                }
            }

            sstore(s_requestedToSubmitCoPackedIndices.slot, indicesFirstCvNotOnChainRestCvOnChain)
            sstore(s_requestedToSubmitCoLength.slot, indicesLength)
            sstore(requestedToSubmitCoTimestampSlot, timestamp())
            sstore(s_zeroBitIfSubmittedCoBitmap.slot, 0xffffffff) // set all bits to 1

            // ** event
            mstore(0x00, startTime)
            mstore(0x20, indicesFirstCvNotOnChainRestCvOnChain)
            log1(0x00, 0x40, 0xa3be0347f45bfc2dee4a4ba1d73c735d156d2c7f4c8134c13f48659942996846) // emit RequestedToSubmitCo(uint256 startTime, uint256 packedIndices);
        }
    }

    function submitCo(bytes32 co) external {
        assembly ("memory-safe") {
            // ** check co status
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime
            mstore(0x20, s_requestedToSubmitCoTimestamp.slot)
            if iszero(sload(keccak256(0x00, 0x40))) {
                mstore(0, 0x11974969) // CoNotRequested()
                revert(0x1c, 0x04)
            }
            // ** check cv == hash(co)
            mstore(0x20, caller())
            mstore(0x40, s_activatedOperatorIndex1Based.slot)
            let activatedOperatorIndex := sub(sload(keccak256(0x20, 0x40)), 1) // underflows when s_activatedOperatorIndex1Based is 0
            if gt(activatedOperatorIndex, MAX_OPERATOR_INDEX) {
                mstore(0, 0x1b256530) // NotActivatedOperator()
                revert(0x1c, 0x04)
            }
            let zeroBitIfSubmittedCvBitmap := sload(s_zeroBitIfSubmittedCvBitmap.slot)
            if gt(and(zeroBitIfSubmittedCvBitmap, shl(activatedOperatorIndex, 1)), 0) {
                // if bit is still set, meaning no Cv submitted for this operator
                mstore(0, 0x03798920) // CvNotSubmitted()
                revert(0x1c, 0x04)
            }
            mstore(0x20, co)
            if iszero(eq(sload(add(s_cvs.slot, activatedOperatorIndex)), keccak256(0x20, 0x20))) {
                mstore(0, 0x67b3c693) // CvNotEqualHashCo()
                revert(0x1c, 0x04)
            }
            // ** bitmap
            sstore(
                s_zeroBitIfSubmittedCoBitmap.slot,
                and(sload(s_zeroBitIfSubmittedCoBitmap.slot), not(shl(activatedOperatorIndex, 1)))
            ) // set to zero bit
            // ** event
            log1(0x00, 0x40, 0x881e94fac6a4a0f5fbeeb59a652c0f4179a070b4e73db759ec4ef38e080eb4a8) // emit CoSubmitted(uint256 startTime, bytes32 co, uint256 index)
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
            mstore(0x20, s_requestedToSubmitCoPackedIndices.slot)
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
                sstore(startTimeSlot, timestamp())
                mstore(0x00, timestamp())
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
            default {
                sstore(s_isInProcess.slot, HALTED)
                // memory 0x00 = startTime
                mstore(0x20, HALTED)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
        }
    }

    function requestToSubmitS(
        bytes32[] calldata allCos, // all cos
        bytes32[] calldata secretsReceivedOffchainInRevealOrder, // already received offchain
        uint256, // packedVsForCvsNotOnChain
        SigRS[] calldata sigRSsForCvsNotOnChain,
        uint256 packedRevealOrders
    ) external {
        bytes32 domainSeparator = _domainSeparatorV4();
        assembly ("memory-safe") {
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            let startTime := sload(add(keccak256(0x00, 0x40), 1))
            mstore(0x00, startTime)
            // ** can only request to submit S if merkleRoot is submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if iszero(sload(keccak256(0x00, 0x40))) {
                mstore(0, 0x8e56b845) // MerkleRootNotSubmitted()
                revert(0x1c, 0x04)
            }
            // ** check if already requested to submit S
            mstore(0x20, s_previousSSubmitTimestamp.slot)
            let previousSSubmitTimestampSlot := keccak256(0x00, 0x40)
            if gt(sload(previousSSubmitTimestampSlot), 0) {
                mstore(0, 0x0d934196) // AlreadyRequestedToSubmitS()
                revert(0x1c, 0x04)
            }
            // ** check allCos length
            let activatedOperatorsLength := sload(s_activatedOperators.slot)
            if iszero(eq(activatedOperatorsLength, allCos.length)) {
                mstore(0, 0x15467973) // AllCosNotSubmitted()
                revert(0x1c, 0x04)
            }
            // ** check cv status
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            let requestedToSubmitCvTimestampSlot := keccak256(0x00, 0x40)
            let zeroBitIfSubmittedCvBitmap
            switch sload(requestedToSubmitCvTimestampSlot)
            case 0 {
                sstore(requestedToSubmitCvTimestampSlot, 1) // set to 1 to indicate that cvs are on-chain
                zeroBitIfSubmittedCvBitmap := 0xffffffff // set all bits to 1
            }
            default { zeroBitIfSubmittedCvBitmap := sload(s_zeroBitIfSubmittedCvBitmap.slot) }

            // ****
            let cos := mload(0x40) // fmp
            let operatorLengthInBytes := mul(activatedOperatorsLength, 0x20)
            calldatacopy(cos, allCos.offset, operatorLengthInBytes) // allCos
            let rv := keccak256(cos, operatorLengthInBytes) // hash of all cos
            let cvs := add(cos, operatorLengthInBytes) // cvs
            let diffs := add(cvs, operatorLengthInBytes) // diffs
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let fmp := add(diffs, operatorLengthInBytes) // fmp
            mstore(fmp, MESSAGE_TYPEHASH_DIRECT)
            mstore(add(fmp, 0x20), startTime) // startTime
            mstore(add(fmp, 0x60), hex"1901") // prefix and version
            mstore(add(fmp, 0x62), domainSeparator)
            let sigCounter
            for { let i } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                let cv := keccak256(add(cos, shl(5, i)), 0x20)
                mstore(add(cvs, shl(5, i)), cv) // cv
                mstore(add(diffs, shl(5, i)), _diff(rv, cv)) // diff
                switch iszero(and(zeroBitIfSubmittedCvBitmap, shl(i, 1)))
                case 1 {
                    // cv is on-chain
                    if iszero(eq(sload(add(s_cvs.slot, i)), cv)) {
                        mstore(0, 0x67b3c693) // CvNotEqualHashCo()
                        revert(0x1c, 0x04)
                    }
                }
                default {
                    // cv is not on-chain
                    // ** check signature
                    let rSOffset := add(sigRSsForCvsNotOnChain.offset, shl(6, sigCounter))
                    sigCounter := add(sigCounter, 1)
                    let s := calldataload(add(rSOffset, 0x20))
                    if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                        mstore(0, 0xbf4bf5b8) // InvalidSignatureS()
                        revert(0x1c, 0x04)
                    }
                    mstore(add(fmp, 0x40), cv)
                    mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                    mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                    mstore(0x20, and(calldataload(sub(0x44, i)), 0xff)) // v, 0x44: packedVsForCvsNotOnChain offset
                    mstore(0x40, calldataload(rSOffset)) // r
                    mstore(0x60, s)
                    let operatorAddress := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                    if iszero(returndatasize()) {
                        mstore(0x00, 0x8baa579f) // selector for InvalidSignature()
                        revert(0x1c, 0x04)
                    }
                    mstore(0x00, operatorAddress)
                    mstore(0x20, s_activatedOperatorIndex1Based.slot)
                    if iszero(eq(add(i, 1), sload(keccak256(0x00, 0x40)))) {
                        mstore(0, 0x980c4296) // SignatureAndIndexDoNotMatch()
                        revert(0x1c, 0x04)
                    }
                    // ** submit cv on-chain
                    sstore(add(s_cvs.slot, i), cv) // cv
                    zeroBitIfSubmittedCvBitmap := and(zeroBitIfSubmittedCvBitmap, not(shl(i, 1))) // set to zero
                }
            }
            // ** verify reveal orders
            let index := and(packedRevealOrders, 0xff) // first reveal index
            let revealBitmap := shl(index, 1)
            let before := mload(add(diffs, shl(5, index)))
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                index := and(calldataload(sub(0x84, i)), 0xff) // 0x84: packedRevealOrders offset
                revealBitmap := or(revealBitmap, shl(index, 1))
                let after := mload(add(diffs, shl(5, index)))
                if lt(before, after) {
                    mstore(0, 0x24f1948e) // RevealNotInDescendingOrder()
                    revert(0x1c, 0x04)
                }
                before := after
            }
            if iszero(eq(revealBitmap, sub(shl(activatedOperatorsLength, 1), 1))) {
                mstore(0, 0xe3ae7cc0) // selector for WrongRevealOrder()
                revert(0x1c, 0x04)
            }
            // skip updating zeroBitIfSubmittedCvBitmap because it is not used anymore
            sstore(s_packedRevealOrders.slot, packedRevealOrders) // update packedRevealOrders
            sstore(s_requestedToSubmitSFromIndexK.slot, secretsReceivedOffchainInRevealOrder.length)
            mstore(0x00, startTime)
            mstore(0x20, secretsReceivedOffchainInRevealOrder.length)
            log1(0x00, 0x40, 0x6f5c0fbf1eb0f90db5f97e1e5b4c0bc94060698d6f59c07e07695ddea198b778) // emit RequestedToSubmitSFromIndexK(uint256 startTime, uint256 index)
            // ** store secrets
            for { let i } lt(i, secretsReceivedOffchainInRevealOrder.length) { i := add(i, 1) } {
                index := and(calldataload(sub(0x84, i)), 0xff) // 0x84: packedRevealOrders offset
                let secret := calldataload(add(secretsReceivedOffchainInRevealOrder.offset, shl(5, i)))
                mstore(0x00, secret)
                mstore(0x00, keccak256(0x00, 0x20)) // co
                if iszero(eq(mload(add(cvs, shl(5, index))), keccak256(0x00, 0x20))) {
                    mstore(0, 0x5bcc2334) // CvNotEqualDoubleHashS()
                    revert(0x1c, 0x04)
                }
                sstore(add(s_secrets.slot, index), secret) // store secret)
            }
            // Record the timestamp of the last S submission
            sstore(previousSSubmitTimestampSlot, timestamp())
        }
    }

    function submitS(bytes32 s) external {
        assembly ("memory-safe") {
            let round := sload(s_currentRound.slot)
            mstore(0x00, round)
            mstore(0x20, s_requestInfo.slot)
            let currentRequestInfoSlot := keccak256(0x00, 0x40)
            let startTime := sload(add(currentRequestInfoSlot, 1))
            mstore(0x00, startTime) // startTime
            // ** check if S was requested
            mstore(0x20, s_previousSSubmitTimestamp.slot)
            let previousSSubmitTimestampSlot := keccak256(0x00, 0x40)
            if iszero(sload(previousSSubmitTimestampSlot)) {
                mstore(0, 0x2d37f8d3) // SNotRequested()
                revert(0x1c, 0x04)
            }

            // ** check reveal order
            let fmp := mload(0x40) // cache fmp
            mstore(0x20, caller())
            mstore(0x40, s_activatedOperatorIndex1Based.slot)
            let activatedOperatorIndex := sub(sload(keccak256(0x20, 0x40)), 1) // underflows when s_activatedOperatorIndex1Based is 0
            if gt(activatedOperatorIndex, MAX_OPERATOR_INDEX) {
                mstore(0, 0x1b256530) // NotActivatedOperator()
                revert(0x1c, 0x04)
            }
            mstore(fmp, sload(s_packedRevealOrders.slot))
            let requestedToSubmitSFromIndexK := sload(s_requestedToSubmitSFromIndexK.slot)
            if iszero(eq(activatedOperatorIndex, and(mload(sub(fmp, requestedToSubmitSFromIndexK)), 0xff))) {
                mstore(0, 0xe3ae7cc0) // WrongRevealOrder()
                revert(0x1c, 0x04)
            }
            // ** check cv = doubleHashS
            mstore(0x20, s)
            mstore(0x40, keccak256(0x20, 0x20)) // co
            if iszero(eq(sload(add(s_cvs.slot, activatedOperatorIndex)), keccak256(0x40, 0x20))) {
                mstore(0, 0x5bcc2334) // CvNotEqualDoubleHashS()
                revert(0x1c, 0x04)
            }
            // ** store S and emit event
            mstore(0x60, activatedOperatorIndex)
            log1(0x00, 0x60, 0x1f2f0bf333e80ee899084dda13e87c0b04096ba331a8d993487a116d166947ec) // emit SSubmitted(uint256 startTime, bytes32 s, uint256 index)

            // ** If msg.sender is the last revealer, finalize the random number
            let activatedOperatorsLength := sload(s_activatedOperators.slot)
            switch eq(requestedToSubmitSFromIndexK, sub(activatedOperatorsLength, 1))
            case 1 {
                let storedSLength := sub(activatedOperatorsLength, 1)
                for { let i } lt(i, storedSLength) { i := add(i, 1) } {
                    mstore(add(fmp, shl(5, i)), sload(add(s_secrets.slot, i))) // store secrets, overwrites fmp because it is not used anymore
                }
                mstore(add(fmp, shl(5, storedSLength)), s) // last secret
                let randomNumber := keccak256(fmp, shl(5, activatedOperatorsLength))
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

                // ** reward the flatFee to last revealer
                // ** reward the leaderNode (requestFee - flatFee) for submitMerkleRoot and generateRandomNumber
                mstore(0x00, caller())
                mstore(0x20, s_depositAmount.slot)
                let depositSlot := keccak256(0x00, 0x40) // last revealer
                let flatFee := sload(s_flatFee.slot)
                sstore(depositSlot, add(sload(depositSlot), flatFee))
                // reward sload(add(currentRequestInfoSlot, 2)) - flatFee to the leader
                mstore(0x00, sload(_OWNER_SLOT))
                depositSlot := keccak256(0x00, 0x40) // leader
                sstore(depositSlot, add(sload(depositSlot), sub(sload(add(currentRequestInfoSlot, 2)), flatFee)))

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
            default {
                sstore(add(s_secrets.slot, activatedOperatorIndex), s) // store secret
                sstore(s_requestedToSubmitSFromIndexK.slot, add(requestedToSubmitSFromIndexK, 1)) // increment index
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
                sstore(startTimeSlot, timestamp())
                mstore(0x00, timestamp())
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
            }
            default {
                sstore(s_isInProcess.slot, HALTED)
                // memory 0x00 = startTime
                mstore(0x20, HALTED)
                log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
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
            // ** Merkle Root submitted
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            let merkleRootSubmittedTimestamp := sload(keccak256(0x00, 0x40))
            if gt(merkleRootSubmittedTimestamp, 0) {
                mstore(0, 0x22b9d231) // MerkleRootIsSubmitted()
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
            log1(0x00, 0x40, 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe) // emit Round(uint256 startTime, uint256 state)
        }
    }
}
