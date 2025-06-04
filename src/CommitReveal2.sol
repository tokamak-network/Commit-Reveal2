// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FailLogics} from "./FailLogics.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {Bitmap} from "./libraries/Bitmap.sol";

contract CommitReveal2 is FailLogics, OptimismL1Fees {
    using Bitmap for mapping(uint248 => uint256);

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
    ) payable FailLogics(name, version) {
        require(msg.value >= activationThreshold);
        s_depositAmount[msg.sender] = msg.value;
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_offChainSubmissionPeriod = offChainSubmissionPeriod;
        s_requestOrSubmitOrFailDecisionPeriod = requestOrSubmitOrFailDecisionPeriod;
        s_onChainSubmissionPeriod = onChainSubmissionPeriod;
        s_offChainSubmissionPeriodPerOperator = offChainSubmissionPeriodPerOperator;
        s_onChainSubmissionPeriodPerOperator = onChainSubmissionPeriodPerOperator;
        s_isInProcess = COMPLETED;
    }

    function setFees(uint256 activationThreshold, uint256 flatFee) external onlyOwner {
        assembly ("memory-safe") {
            sstore(s_activationThreshold.slot, activationThreshold)
            sstore(s_flatFee.slot, flatFee)
        }
    }

    function setPeriods(
        uint256 offChainSubmissionPeriod,
        uint256 requestOrSubmitOrFailDecisionPeriod,
        uint256 onChainSubmissionPeriod,
        uint256 offChainSubmissionPeriodPerOperator,
        uint256 onChainSubmissionPeriodPerOperator
    ) external onlyOwner {
        assembly ("memory-safe") {
            sstore(s_offChainSubmissionPeriod.slot, offChainSubmissionPeriod)
            sstore(s_requestOrSubmitOrFailDecisionPeriod.slot, requestOrSubmitOrFailDecisionPeriod)
            sstore(s_onChainSubmissionPeriod.slot, onChainSubmissionPeriod)
            sstore(s_offChainSubmissionPeriodPerOperator.slot, offChainSubmissionPeriodPerOperator)
            sstore(s_onChainSubmissionPeriodPerOperator.slot, onChainSubmissionPeriodPerOperator)
        }
    }

    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, gasPrice, s_activatedOperators.length);
    }

    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        external
        view
        returns (uint256)
    {
        return _calculateRequestPrice(callbackGasLimit, gasPrice, numOfOperators);
    }

    function requestRandomNumber(uint32 callbackGasLimit) external payable virtual returns (uint256) {
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
            // l2GasUsed(SubmitMerkleRoot+GenerateRandomNumber):3931.70 × numOfOperators + 131,508.96
            // l1GasFee: l1GasFee(submitMerkleRoot callDataSize) + l1GasFee(generateRandomNumber calDataSize)
            // = l1GasFee(36) + l1GasFee(132 + (96 * numOfOperators))
            mstore(0x00, 0xf1c7a58b) // selector for "getL1FeeUpperBound(uint256 _unsignedTxSize) external view returns (uint256)"
            mstore(0x20, add(MERKLEROOTSUB_CALLDATA_BYTES_SIZE, L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE))
            if iszero(staticcall(gas(), OVM_GASPRICEORACLE_ADDR, 0x1c, 0x24, 0x40, 0x20)) {
                mstore(0, 0xb75f34bf) // selector for L1FeeEstimationFailed()
                revert(0x1c, 0x04)
            }
            mstore(
                0x20,
                add(
                    add(
                        mul(GENRANDNUM_CALLDATA_BYTES_SIZE_A, activatedOperatorsLength),
                        GENRANDNUM_CALLDATA_BYTES_SIZE_B
                    ),
                    L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                )
            )
            if iszero(staticcall(gas(), OVM_GASPRICEORACLE_ADDR, 0x1c, 0x24, 0x20, 0x20)) {
                mstore(0, 0xb75f34bf) // selector for L1FeeEstimationFailed()
                revert(0x1c, 0x04)
            }
            if lt(
                callvalue(),
                add(
                    add(
                        mul(
                            gasprice(),
                            add(
                                callbackGasLimit,
                                add(
                                    mul(GASUSED_MERKLEROOTSUB_GENRANDNUM_A, activatedOperatorsLength),
                                    GASUSED_MERKLEROOTSUB_GENRANDNUM_B
                                )
                            )
                        ),
                        sload(s_flatFee.slot)
                    ), // l2GasFee
                    div(mul(sload(s_l1FeeCoefficient.slot), add(mload(0x20), mload(0x40))), 100) // L1GasFee
                )
            ) {
                mstore(0, 0x5945ea56) // selector for InsufficientAmount()
                revert(0x1c, 0x04)
            }
            let newRound := sload(s_requestCount.slot)
            sstore(s_requestCount.slot, add(newRound, 1))
            if gt(sub(newRound, sload(s_currentRound.slot)), 2000) {
                mstore(0, 0x02cd147b) // selector for TooManyRequestsQueued()
                revert(0x1c, 0x04)
            }

            // ** set the bit
            // calculate the storage slot corresponding to the round
            // wordPos = round >> 8
            mstore(0, shr(8, newRound))
            mstore(0x20, s_roundBitmap.slot)
            // the slot of self[wordPos] is keccak256(abi.encode(wordPos, self.slot))
            let slot := keccak256(0, 0x40)
            // mask = 1 << bitPos = 1 << (round & 0xff)
            // self[wordPos] |= mask
            sstore(slot, or(sload(slot), shl(and(newRound, 0xff), 1)))
            let startTime
            // ** check if the current round is completed
            // ** if the current round is completed, start a new round
            if eq(sload(s_isInProcess.slot), COMPLETED) {
                sstore(s_currentRound.slot, newRound)
                sstore(s_isInProcess.slot, IN_PROGRESS)
                startTime := add(timestamp(), 1) // Just in case of timestamp collision
                mstore(0, startTime)
                mstore(0x20, IN_PROGRESS)
                log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
            }
            // *** store the request info
            mstore(0x00, newRound)
            mstore(0x20, s_requestInfo.slot)
            let requestInfoSlot := keccak256(0x00, 0x40)
            sstore(requestInfoSlot, caller())
            sstore(add(requestInfoSlot, 1), startTime)
            sstore(add(requestInfoSlot, 2), callvalue())
            sstore(add(requestInfoSlot, 3), callbackGasLimit)
            return(0x00, 0x20)
        }
    }

    /**
     * @notice Calculates the total fee required for requesting a random number, factoring in:
     *         1. L2 execution costs (based on the callback gas limit and the number of operators).
     *         2. A flat fee (s_flatFee).
     *         3. L1 data costs for sending required transaction calldata.
     * @dev
     *      - The internal gas usage estimation is derived from two operations:
     *        (i) "submitMerkleRoot" (~47,216 L2 gas).
     *        (ii) "generateRandomNumber" (~21,119 × numOfOperators + 134,334 L2 gas).
     *      - The final fee also includes `_getL1CostWeiForcalldataSize2(...)` to account for the
     *        cost of posting data to the L1 chain.
     * @param callbackGasLimit The gas required by the consumer’s callback execution.
     * @param gasPrice The L2 gas price to be used for cost estimation.
     * @param numOfOperators The number of active operators factored into the total gas cost.
     * @return totalPrice The calculated total fee (in wei) needed to cover the request.
     */
    function _calculateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        internal
        view
        virtual
        returns (uint256)
    {
        // submitRoot l2GasUsed = 47216
        // generateRandomNumber l2GasUsed = 21118.97⋅N + 87117.53
        return (
            gasPrice
                * (
                    callbackGasLimit
                        + (GASUSED_MERKLEROOTSUB_GENRANDNUM_A * numOfOperators + GASUSED_MERKLEROOTSUB_GENRANDNUM_B)
                )
        ) + s_flatFee
            + _getL1CostWeiForcalldataSize2(
                MERKLEROOTSUB_CALLDATA_BYTES_SIZE,
                (GENRANDNUM_CALLDATA_BYTES_SIZE_A * numOfOperators) + GENRANDNUM_CALLDATA_BYTES_SIZE_B
            );
    }

    /**
     * @notice Computes the total L1 cost (in wei) for two separate calldata payload sizes.
     * @dev This is a helper function that sums the cost of submitting data of two different lengths
     *      to L1. Each call to `_getL1CostWeiForCalldataSize(...)` accounts for the overhead of
     *      RLP-encoding and L1 gas price adjustments in Optimism.
     * @param calldataSizeBytes1 The size (in bytes) of the first calldata payload.
     * @param calldataSizeBytes2 The size (in bytes) of the second calldata payload.
     * @return l1Cost The total cost (in wei) for posting both payloads to L1.
     */
    function _getL1CostWeiForcalldataSize2(uint256 calldataSizeBytes1, uint256 calldataSizeBytes2)
        private
        view
        returns (uint256)
    {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
        return _getL1CostWeiForCalldataSize(calldataSizeBytes1) + _getL1CostWeiForCalldataSize(calldataSizeBytes2);
    }

    function submitMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        assembly ("memory-safe") {
            mstore(0x00, sload(s_currentRound.slot))
            mstore(0x20, s_requestInfo.slot)
            mstore(0x00, sload(add(keccak256(0x00, 0x40), 1))) // startTime
            mstore(0x20, s_merkleRootSubmittedTimestamp.slot)
            let merkleRootSubmittedTimestampSlot := keccak256(0x00, 0x40)
            if gt(sload(merkleRootSubmittedTimestampSlot), 0) {
                mstore(0, 0xa34402b2) // selector for MerkleRootAlreadySubmitted()
                revert(0x1c, 0x04)
            }
            sstore(s_merkleRoot.slot, merkleRoot)
            sstore(merkleRootSubmittedTimestampSlot, timestamp())
            mstore(0x20, merkleRoot)
            log1(0x00, 0x40, 0xb3a8f3e59050d3f97f1bf1b668c8216c654869aa24e3e03cd8891dc68b7db097) // emit MerkleRootSubmitted(uint256 startTime, bytes32 merkleRoot)
        }
    }

    function generateRandomNumber(
        SecretAndSigRS[] calldata secretSigRSs,
        uint256, // packedVs
        uint256 packedRevealOrders
    ) external virtual {
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

            // ** verify signatures
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
            let requestCount := sload(s_requestCount.slot)
            switch eq(nextRound, requestCount)
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
                // get next round
                function leastSignificantBit(x) -> r {
                    x := and(x, sub(0, x))
                    r :=
                        shl(
                            5,
                            shr(
                                252,
                                shl(
                                    shl(
                                        2,
                                        shr(250, mul(x, 0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))
                                    ),
                                    0x8040405543005266443200005020610674053026020000107506200176117077
                                )
                            )
                        )
                    r :=
                        or(
                            r,
                            byte(
                                and(div(0xd76453e0, shr(r, x)), 0x1f),
                                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405
                            )
                        )
                }
                function nextRequestedRound(_round) -> _next, _requested {
                    let wordPos := shr(8, _round)
                    let bitPos := and(_round, 0xff)
                    let mask := not(sub(shl(bitPos, 1), 1))
                    mstore(0x00, wordPos)
                    mstore(0x20, s_roundBitmap.slot)
                    let masked := and(sload(keccak256(0x00, 0x40)), mask)
                    _requested := gt(masked, 0)
                    switch _requested
                    case 1 { _next := sub(add(_round, leastSignificantBit(masked)), bitPos) }
                    default { _next := sub(add(_round, 255), bitPos) }
                }
                let requested
                for { let i } lt(i, 10) { i := add(i, 1) } {
                    nextRound, requested := nextRequestedRound(nextRound)
                    if requested {
                        mstore(0x00, nextRound) // round
                        mstore(0x20, s_requestInfo.slot)
                        let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                        sstore(add(keccak256(0x00, 0x40), 1), nextTimestamp)
                        sstore(s_currentRound.slot, nextRound)
                        mstore(0x00, nextTimestamp)
                        mstore(0x20, IN_PROGRESS)
                        log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
                        break
                    }
                    if iszero(lt(nextRound, requestCount)) {
                        if eq(sload(s_isInProcess.slot), COMPLETED) {
                            mstore(0x00, 0x195332a5) // selector for AlreadyCompleted()
                            revert(0x1c, 0x04)
                        }
                        sstore(s_isInProcess.slot, COMPLETED)
                        sstore(s_currentRound.slot, sub(requestCount, 1))
                        mstore(0x00, startTime)
                        mstore(0x20, COMPLETED)
                        log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
                        break
                    }
                    nextRound := add(nextRound, 1)
                }
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

    function refund(uint256 round) external {
        assembly ("memory-safe") {
            // ** check if the contract is halted
            if iszero(eq(sload(s_isInProcess.slot), HALTED)) {
                mstore(0, 0x78b19eb2) // selector for NotHalted()
                revert(0x1c, 0x04)
            }
            // ** check if the round is valid
            if iszero(lt(round, sload(s_requestCount.slot))) {
                mstore(0, 0xa2b52a54) // selector for InvalidRound()
                revert(0x1c, 0x04)
            }
            if lt(round, sload(s_currentRound.slot)) {
                mstore(0, 0xa2b52a54) // selector for InvalidRound()
                revert(0x1c, 0x04)
            }
            mstore(0x00, round)
            mstore(0x20, s_requestInfo.slot)
            let consumerSlot := keccak256(0x00, 0x40)
            // ** check if the caller is the consumer
            if iszero(eq(sload(consumerSlot), caller())) {
                mstore(0, 0x8c7dc13d) // selector for NotConsumer()
                revert(0x1c, 0x04)
            }

            // ** flip the roundBitmap 1 -> 0
            // calculate the storage slot corresponding to the round
            // wordPos = round >> 8
            mstore(0x00, shr(8, round))
            mstore(0x20, s_roundBitmap.slot)
            // the slot of self[wordPos] is keccak256(abi.encode(wordPos, self.slot))
            let slot := keccak256(0, 0x40)
            // mask = 1 << bitPos = 1 << (round & 0xff)
            // self[wordPos] ^= mask
            sstore(slot, xor(sload(slot), shl(and(round, 0xff), 1)))

            // ** refund
            slot := add(consumerSlot, 2) // cost
            let cost := sload(slot)
            if iszero(cost) {
                mstore(0, 0xa85e6f1a) // selector for AlreadyRefunded()
                revert(0x1c, 0x04)
            }
            sstore(slot, 0)
            // Transfer the ETH and check if it succeeded or not.
            if iszero(call(gas(), caller(), cost, 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    function resume() external payable onlyOwner {
        uint256 nextRequestedRound;
        bool requested;
        uint256 requestCountMinusOne;
        assembly ("memory-safe") {
            if iszero(eq(sload(s_isInProcess.slot), HALTED)) {
                mstore(0, 0x78b19eb2) // selector for NotHalted()
                revert(0x1c, 0x04)
            }
            if lt(sload(s_activatedOperators.slot), 2) {
                mstore(0, 0x77599fd9) // selector for NotEnoughActivatedOperators()
                revert(0x1c, 0x04)
            }
            mstore(0x00, sload(_OWNER_SLOT))
            mstore(0x20, s_depositAmount.slot)
            let ownerDepositSlot := keccak256(0x00, 0x40)
            let ownderDepositAmount := sload(ownerDepositSlot)
            if gt(callvalue(), 0) {
                ownderDepositAmount := add(ownderDepositAmount, callvalue())
                sstore(ownerDepositSlot, ownderDepositAmount)
            }
            if lt(ownderDepositAmount, sload(s_activationThreshold.slot)) {
                mstore(0, 0xc0013a5a) // selector for LeaderLowDeposit()
                revert(0x1c, 0x04)
            }
            nextRequestedRound := sload(s_currentRound.slot)
            requestCountMinusOne := sub(sload(s_requestCount.slot), 1)
        }
        for (uint256 i; i < 10; i++) {
            (nextRequestedRound, requested) = s_roundBitmap.nextRequestedRound(nextRequestedRound);
            assembly ("memory-safe") {
                if requested {
                    // Start this requested round
                    mstore(0x00, nextRequestedRound)
                    mstore(0x20, s_requestInfo.slot)
                    let nextTimestamp := add(timestamp(), 1) // Just in case of timestamp collision
                    sstore(add(keccak256(0x00, 0x40), 1), nextTimestamp) // startTime
                    sstore(s_currentRound.slot, nextRequestedRound)
                    sstore(s_isInProcess.slot, IN_PROGRESS)
                    mstore(0x00, nextTimestamp)
                    mstore(0x20, IN_PROGRESS)
                    log1(0x00, 0x40, 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762) // emit Status(uint256 curStartTime, uint256 curState)
                    return(0, 0)
                }
                // If we reach or pass the last round without finding any requested round,
                // mark as COMPLETED and set the current round to the last possible index.
                if iszero(lt(nextRequestedRound, requestCountMinusOne)) {
                    sstore(s_isInProcess.slot, COMPLETED) // q I don't think this is necessary
                    sstore(s_currentRound.slot, requestCountMinusOne)
                    return(0, 0)
                }
                nextRequestedRound := add(nextRequestedRound, 1)
            }
        }
        assembly ("memory-safe") {
            sstore(s_currentRound.slot, nextRequestedRound)
        }
    }
}
