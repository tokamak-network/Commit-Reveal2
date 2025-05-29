// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OperatorManager} from "./OperatorManager.sol";
import {CommitReveal2Storage} from "./CommitReveal2Storage.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract DisputeLogics is EIP712, OperatorManager, CommitReveal2Storage {
    constructor(string memory name, string memory version) EIP712(name, version) {}

    function requestToSubmitCv(uint256 packedIndicesAscendingFromLSB) external onlyOwner {
        assembly ("memory-safe") {
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
            let previousIndex := and(packedIndicesAscendingFromLSB, 0xff)
            if gt(previousIndex, maxIndex) {
                mstore(0, 0x63df8171) // InvalidIndex()
                revert(0x1c, 0x04)
            }
            mstore(0x20, packedIndicesAscendingFromLSB)
            let i := 1
            for {} true { i := add(i, 1) } {
                let currentIndex := and(mload(sub(0x20, i)), 0xff)
                if gt(currentIndex, maxIndex) {
                    mstore(0, 0x63df8171) // InvalidIndex()
                    revert(0x1c, 0x04)
                }
                if iszero(gt(currentIndex, previousIndex)) { break }
            }
            sstore(requestedToSubmitCvTimestampSlot, timestamp())
            sstore(s_requestedToSubmitCvLength.slot, i)
            sstore(s_requestedToSubmitCvPackedIndices.slot, packedIndicesAscendingFromLSB)
            sstore(s_zeroBitIfSubmittedCvBitmap.slot, 0xffffffff) // set all bits to 1
            log1(0x00, 0x40, 0x18d0e75c02ebf9429b0b69ace609256eb9c9e12d5c9301a2d4a04fd7599b5cfc) // emit RequestedToSubmitCv(uint256 startTime, uint256 packedIndices)
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
            mstore(0x40, activatedOperatorIndex)
            log1(0x00, 0x60, 0x689880904ca6a1080ab52c3fd53043e57fddaa2af740366f4fd4275e91512438) // emit CvSubmitted(uint256 startTime, bytes32 cv, uint256 index)
        }
    }

    function requestToSubmitCo(
        CvAndSigRS[] calldata cvRSsForCvsNotOnChainAndReqToSubmitCo,
        uint256, // packedVsForCvsNotOnChainAndReqToSubmitCo,
        uint256 indicesLength,
        uint256 packedIndicesFirstCvNotOnChainRestCvOnChain
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
                if iszero(eq(indicesLength, cvRSsForCvsNotOnChainAndReqToSubmitCo.length)) {
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

            for { let i } lt(i, cvRSsForCvsNotOnChainAndReqToSubmitCo.length) { i := add(i, 1) } {
                // ** check duplicate
                let requestToSubmitCoIndex := and(calldataload(sub(0x64, i)), 0xff) // 0x64: packedIndicesFirstCvNotOnChainRestCvOnChain
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
                let cvsRSsOffset := add(cvRSsForCvsNotOnChainAndReqToSubmitCo.offset, mul(0x60, i))
                let s := calldataload(add(cvsRSsOffset, 0x40))
                if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                    mstore(0, 0xbf4bf5b8) // InvalidSignatureS()
                    revert(0x1c, 0x04)
                }
                mstore(add(fmp, 0x40), calldataload(cvsRSsOffset)) // cv
                mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                mstore(0x20, and(calldataload(sub(0x24, i)), 0xff)) // v, 0x24: packedVsForCvsNotOnChainAndReqToSubmitCo offset
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
            for { let i := cvRSsForCvsNotOnChainAndReqToSubmitCo.length } lt(i, indicesLength) { i := add(i, 1) } {
                let requestToSubmitCoIndex := and(calldataload(sub(0x64, i)), 0xff) // 0x64: packedIndicesFirstCvNotOnChainRestCvOnChain
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

            sstore(s_requestedToSubmitCoPackedIndices.slot, packedIndicesFirstCvNotOnChainRestCvOnChain)
            sstore(s_requestedToSubmitCoLength.slot, indicesLength)
            sstore(requestedToSubmitCoTimestampSlot, timestamp())
            sstore(s_zeroBitIfSubmittedCoBitmap.slot, 0xffffffff) // set all bits to 1

            // ** event
            mstore(0x00, startTime)
            mstore(0x20, indicesLength)
            mstore(0x40, packedIndicesFirstCvNotOnChainRestCvOnChain)
            log1(0x00, 0x60, 0x3a1aae8ec96f949b8b598464ca094f2ba50e8826b0bd3245fd24ec868a27ab57) // emit RequestedToSubmitCo(uint256 startTime, uint256 indicesLength, uint256 packedIndices);
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
                // this operator was not requested to submit Co
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
            mstore(0x40, activatedOperatorIndex)
            log1(0x00, 0x60, 0x881e94fac6a4a0f5fbeeb59a652c0f4179a070b4e73db759ec4ef38e080eb4a8) // emit CoSubmitted(uint256 startTime, bytes32 co, uint256 index)
        }
    }

    function requestToSubmitS(
        bytes32[] calldata allCos, // all cos
        bytes32[] calldata secretsReceivedOffchainInRevealOrder, // already received offchain
        uint256, // packedVsForAllCvsNotOnChain
        SigRS[] calldata sigRSsForAllCvsNotOnChain,
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
                    let rSOffset := add(sigRSsForAllCvsNotOnChain.offset, shl(6, sigCounter))
                    let s := calldataload(add(rSOffset, 0x20))
                    if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                        mstore(0, 0xbf4bf5b8) // InvalidSignatureS()
                        revert(0x1c, 0x04)
                    }
                    mstore(add(fmp, 0x40), cv)
                    mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                    mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                    mstore(0x20, and(calldataload(sub(0x44, sigCounter)), 0xff)) // v, 0x44: packedVsForAllCvsNotOnChain offset
                    sigCounter := add(sigCounter, 1)
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
                mstore(0, 0x06efcba4) // selector for RevealOrderHasDuplicates()
                revert(0x1c, 0x04)
            }
            // skip updating zeroBitIfSubmittedCvBitmap because it is not used anymore
            sstore(s_packedRevealOrders.slot, packedRevealOrders) // update packedRevealOrders
            sstore(s_requestedToSubmitSFromIndexK.slot, secretsReceivedOffchainInRevealOrder.length)
            mstore(0x00, startTime)
            mstore(0x20, secretsReceivedOffchainInRevealOrder.length)
            log1(0x00, 0x40, 0x6f5c0fbf1eb0f90db5f97e1e5b4c0bc94060698d6f59c07e07695ddea198b778) // emit RequestedToSubmitSFromIndexK(uint256 startTime, uint256 indexK)
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
                    log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
                }
                default {
                    mstore(0x00, nextRound) // round
                    mstore(0x20, s_requestInfo.slot)
                    let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                    sstore(add(keccak256(0x00, 0x40), 1), nextTimestamp)
                    sstore(s_currentRound.slot, nextRound)
                    mstore(0x00, nextTimestamp)
                    mstore(0x20, IN_PROGRESS)
                    log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
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

    function generateRandomNumberWhenSomeCvsAreOnChain(
        bytes32[] calldata allSecrets,
        SigRS[] calldata sigRSsForAllCvsNotOnChain,
        uint256, // packedVsForAllCvsNotOnChain
        uint256 packedRevealOrders
    ) external {
        bytes32 domainSeparator = _domainSeparatorV4();
        assembly ("memory-safe") {
            // ** check if some cvs are on-chain
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime
            mstore(0x20, s_requestedToSubmitCvTimestamp.slot)
            let requestedToSubmitCvTimestampSlot := keccak256(0x00, 0x40)
            if iszero(sload(requestedToSubmitCvTimestampSlot)) {
                mstore(0, 0x96fbee7b) // NoCvsOnChain()
                revert(0x1c, 0x04)
            }
            // ** initialize cos and cvs arrays memory, without length data
            let activatedOperatorsLength := sload(s_activatedOperators.slot)
            let activatedOperatorsLengthInBytes := shl(5, activatedOperatorsLength)
            let cos := mload(0x40)
            let cvs := add(cos, activatedOperatorsLengthInBytes)
            let secrets := add(cvs, activatedOperatorsLengthInBytes)
            mstore(0x40, add(secrets, activatedOperatorsLengthInBytes)) // update the free memory pointer

            // ** get cos and cvs
            for { let i } lt(i, activatedOperatorsLengthInBytes) { i := add(i, 0x20) } {
                let secretMemP := add(secrets, i)
                mstore(secretMemP, calldataload(add(allSecrets.offset, i))) // secret
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
            // revealOrdersOffset = 0x64
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                index := and(calldataload(sub(0x64, i)), 0xff)
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
            // ** check if the merkle root is submitted
            let round := sload(s_currentRound.slot)
            mstore(0x00, round)
            mstore(0x20, s_requestInfo.slot)
            let currentRequestInfoSlot := keccak256(0x00, 0x40)
            mstore(0x00, sload(add(currentRequestInfoSlot, 1)))
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            if iszero(sload(keccak256(0x00, 0x40))) {
                mstore(0, 0x8e56b845) // selector for MerkleRootNotSubmitted()
                revert(0x1c, 0x04)
            }
            // ** verify the merkle root
            if iszero(eq(mload(add(fmp, sub(hashCountInBytes, 0x20))), sload(s_merkleRoot.slot))) {
                mstore(0, 0x624dc351) // selector for MerkleVerificationFailed()
                revert(0x1c, 0x04)
            }

            // ** verify signatures or cvs on-chain
            mstore(fmp, MESSAGE_TYPEHASH_DIRECT) // typehash, overwrite the previous value, which is not used anymore
            let startTime := sload(add(currentRequestInfoSlot, 1))
            mstore(add(fmp, 0x20), startTime)
            mstore(add(fmp, 0x60), hex"1901") // prefix and version
            mstore(add(fmp, 0x62), domainSeparator)
            let zeroBitIfSubmittedCvBitmap := sload(s_zeroBitIfSubmittedCvBitmap.slot)
            let sigCounter
            for { let i } lt(i, activatedOperatorsLengthInBytes) { i := add(i, 0x20) } {
                index := shr(5, i)
                switch iszero(and(zeroBitIfSubmittedCvBitmap, shl(index, 1)))
                case 1 {
                    // cv is on-chain
                    if iszero(eq(sload(add(s_cvs.slot, index)), mload(add(cvs, i)))) {
                        mstore(0, 0xa39ecadf) // selector for OnChainCvNotEqualDoubleHashS()
                        revert(0x1c, 0x04)
                    }
                }
                default {
                    // signature malleability prevention
                    let rOffset := add(sigRSsForAllCvsNotOnChain.offset, shl(6, sigCounter))
                    let s := calldataload(add(rOffset, 0x20))
                    if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                        mstore(0, 0xbf4bf5b8) // selector for InvalidSignatureS()
                        revert(0x1c, 0x04)
                    }
                    mstore(add(fmp, 0x40), mload(add(cvs, i))) // cv
                    mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                    mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                    mstore(0x20, and(calldataload(sub(0x44, sigCounter)), 0xff)) // v, 0x44: packedVsOffset
                    sigCounter := add(sigCounter, 1)
                    mstore(0x40, calldataload(rOffset)) // r
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
            }

            // ** create random number
            let randomNumber := keccak256(secrets, activatedOperatorsLengthInBytes)
            let nextRound := add(round, 1)

            switch eq(nextRound, sload(s_requestCount.slot))
            case 1 {
                // there is no next round
                if eq(sload(s_isInProcess.slot), COMPLETED) {
                    mstore(0x00, 0x195332a5) // selector for AlreadyCompleted()
                    revert(0x1c, 0x04)
                }
                sstore(s_isInProcess.slot, COMPLETED)
                mstore(0x00, startTime)
                mstore(0x20, COMPLETED)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            default {
                // there is a next round
                mstore(0x00, nextRound) // round
                mstore(0x20, s_requestInfo.slot)
                let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                sstore(add(keccak256(0x00, 0x40), 1), nextTimestamp)
                sstore(s_currentRound.slot, nextRound)
                mstore(0x00, nextTimestamp)
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
                        and(calldataload(sub(0x64, sub(activatedOperatorsLength, 1))), 0xff) // last revealer index, 0x64: revealOrdersOffset
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
                log1(0x20, 0x60, 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a) // emit RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess)
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
