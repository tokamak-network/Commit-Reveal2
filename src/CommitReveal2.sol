// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Dispute, ConsumerBase} from "./Dispute.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {Bitmap} from "./libraries/Bitmap.sol";

contract CommitReveal2 is Dispute, OptimismL1Fees {
    using Bitmap for mapping(uint248 => uint256);

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
    ) payable Dispute(name, version) {
        require(msg.value >= activationThreshold);
        s_depositAmount[msg.sender] = msg.value;
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_maxActivatedOperators = maxActivatedOperators;
        s_offChainSubmissionPeriod = offChainSubmissionPeriod;
        s_requestOrSubmitOrFailDecisionPeriod = requestOrSubmitOrFailDecisionPeriod;
        s_onChainSubmissionPeriod = onChainSubmissionPeriod;
        s_offChainSubmissionPeriodPerOperator = offChainSubmissionPeriodPerOperator;
        s_onChainSubmissionPeriodPerOperator = onChainSubmissionPeriodPerOperator;
        s_isInProcess = COMPLETED;
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

    function requestRandomNumber(uint32 callbackGasLimit) external payable virtual returns (uint256 newRound) {
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
            mstore(0x00, 0xf1c7a58b) // selector for "getL1FeeUpperBound(uint256 _unsignedTxSize) external view returns (uint256)"
            mstore(0x20, add(MERKLEROOTSUB_CALLDATA_BYTES_SIZE, L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE))
            if iszero(staticcall(gas(), OVM_GASPRICEORACLE_ADDR, 0x1c, 0x24, 0x40, 0x20)) {
                mstore(0, 0xb75f34bf) // selector for L1FeeEstimationFailed()
                revert(0x1c, 0x04)
            }
            // l2GasUsed := add(
            //     mul(gasprice(), add(callbackGasLimit, add(mul(21119, activatedOperatorsLength), 134334))),
            //     sload(s_flatFee.slot)
            // )
            // L1GasFee := div(mul(sload(s_l1FeeCoefficient.slot), add(mload(0x20), mload(0x40))), 100)
            mstore(0x20, add(add(292, mul(128, activatedOperatorsLength)), L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE))
            if iszero(staticcall(gas(), OVM_GASPRICEORACLE_ADDR, 0x1c, 0x24, 0x20, 0x20)) {
                mstore(0, 0xb75f34bf) // selector for L1FeeEstimationFailed()
                revert(0x1c, 0x04)
            }
            if lt(
                callvalue(),
                add(
                    add(
                        mul(gasprice(), add(callbackGasLimit, add(mul(21119, activatedOperatorsLength), 134334))),
                        sload(s_flatFee.slot)
                    ),
                    div(mul(sload(s_l1FeeCoefficient.slot), add(mload(0x20), mload(0x40))), 100)
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
        return (gasPrice * (callbackGasLimit + (211 * numOfOperators + 1344))) + s_flatFee
            + _getL1CostWeiForcalldataSize2(MERKLEROOTSUB_CALLDATA_BYTES_SIZE, 292 + (128 * numOfOperators));
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
            mstore(0x20, s_isSubmittedMerkleRoot.slot)
            sstore(keccak256(0x00, 0x40), 1)
            sstore(s_merkleRoot.slot, merkleRoot)
            sstore(s_merkleRootSubmittedTimestamp.slot, timestamp())
            mstore(0x20, merkleRoot)
            log1(0x00, 0x40, 0xb3a8f3e59050d3f97f1bf1b668c8216c654869aa24e3e03cd8891dc68b7db097) // emit MerkleRootSubmitted(uint256 startTime, bytes32 merkleRoot)
        }
    }

    function refund(uint256 round) external notInProcess {
        require(round < s_requestCount, InvalidRound());
        require(round >= s_currentRound, InvalidRound());
        RequestInfo storage requestInfo = s_requestInfo[round];
        require(requestInfo.consumer == msg.sender, NotConsumer());
        s_roundBitmap.flipBit(round); // 1 -> 0

        // ** refund
        uint256 cost = requestInfo.cost;
        require(cost > 0, AlreadyRefunded());
        requestInfo.cost = 0;
        assembly ("memory-safe") {
            // Transfer the ETH and check if it succeeded or not.
            if iszero(call(gas(), caller(), cost, 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    function resume() external payable onlyOwner {
        require(s_isInProcess == HALTED, NotHalted());
        require(s_activatedOperators.length > 1, NotEnoughActivatedOperators());
        address owner = owner();
        if (msg.value > 0) s_depositAmount[owner] += msg.value;
        require(s_depositAmount[owner] >= s_activationThreshold, LeaderLowDeposit());
        uint256 nextRequestedRound = s_currentRound;
        bool requested;
        uint256 requestCountMinusOne = s_requestCount - 1;
        for (uint256 i; i < 10; i++) {
            (nextRequestedRound, requested) = s_roundBitmap.nextRequestedRound(nextRequestedRound);
            if (requested) {
                // Start this requested round
                s_currentRound = nextRequestedRound;
                s_requestInfo[nextRequestedRound].startTime = block.timestamp;
                s_isInProcess = IN_PROGRESS;
                emit Round(block.timestamp, IN_PROGRESS);
                return;
            }
            unchecked {
                // If we reach or pass the last round without finding any requested round,
                // mark as COMPLETED and set the current round to the last possible index.
                if (nextRequestedRound++ >= requestCountMinusOne) {
                    // && requested = false
                    s_isInProcess = COMPLETED; // q I don't think this is necessary
                    s_currentRound = requestCountMinusOne;
                    return;
                }
            }
        }
        s_currentRound = nextRequestedRound;
    }

    function generateRandomNumber(
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint256[] calldata revealOrders
    ) external {
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
            if iszero(extcodesize(consumer)) { return(0, 0) }
            // sload(add(currentRequestInfoSlot, 3)) == consumer
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            mstore(0x60, call(callbackGasLimit, consumer, 0, 0x1c, 0x44, 0, 0))
            log1(0x20, 0x60, 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a) // emit RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess
        }
    }
}
