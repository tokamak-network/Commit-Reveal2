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

    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256 newRound) {
        require(callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT, ExceedCallbackGasLimit());
        uint256 activatedOperatorsLength = s_activatedOperators.length;
        require(activatedOperatorsLength > 1, NotEnoughActivatedOperators());
        require(s_depositAmount[owner()] >= s_activationThreshold, LeaderLowDeposit());
        require(
            msg.value >= _calculateRequestPrice(callbackGasLimit, tx.gasprice, activatedOperatorsLength),
            InsufficientAmount()
        );
        unchecked {
            newRound = s_requestCount++;
        }
        s_roundBitmap.flipBit(newRound);
        //uint256 startTime = s_currentRound > s_lastfulfilledRound ? 0 : block.timestamp;
        uint256 startTime;
        if (s_isInProcess == COMPLETED) {
            s_currentRound = newRound;
            s_isInProcess = IN_PROGRESS;
            startTime = block.timestamp;
            emit IsInProcess(IN_PROGRESS);
        }
        s_requestInfo[newRound] = RequestInfo({
            consumer: msg.sender,
            startTime: startTime,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit
        });
        emit RandomNumberRequested(newRound, startTime, s_activatedOperators);
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
        return (gasPrice * (callbackGasLimit + (21119 * numOfOperators + 134334))) + s_flatFee
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
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(
            block.timestamp < startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod, TooLate()
        );
        s_merkleRoot = merkleRoot;
        s_merkleRootSubmittedTimestamp = block.timestamp;
        s_isSubmittedMerkleRoot[startTime] = true;
        emit MerkleRootSubmitted(startTime, merkleRoot);
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
                emit IsInProcess(IN_PROGRESS);
                emit RandomNumberRequested(nextRequestedRound, block.timestamp, s_activatedOperators);
                return;
            }
            unchecked {
                // If we reach or pass the last round without finding any requested round,
                // mark as COMPLETED and set the current round to the last possible index.
                if (nextRequestedRound++ >= requestCountMinusOne) {
                    // && requested = false
                    s_isInProcess = COMPLETED;
                    s_currentRound = requestCountMinusOne;
                    emit IsInProcess(COMPLETED);
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
        uint256 activatedOperatorsLength;
        bytes32 domainSeparator = _domainSeparatorV4();
        assembly ("memory-safe") {
            activatedOperatorsLength := sload(s_activatedOperators.slot)
            // ** check if all secrets are submitted
            if gt(activatedOperatorsLength, secrets.length) {
                mstore(0, 0xe0767fa4) // selector for InvalidSecretLength()
                revert(0x1c, 0x04)
            }
            // ** check if it is not too late
            if iszero(
                or(
                    lt(
                        timestamp(),
                        add(
                            add(
                                add(sload(s_merkleRootSubmittedTimestamp.slot), sload(s_offChainSubmissionPeriod.slot)),
                                mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorsLength)
                            ),
                            sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                        )
                    ),
                    lt(
                        timestamp(),
                        add(
                            add(
                                add(sload(s_requestedToSubmitCoTimestamp.slot), sload(s_onChainSubmissionPeriod.slot)),
                                mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorsLength)
                            ),
                            sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                        )
                    )
                )
            ) {
                mstore(0, 0xecdd1c29) // selector for TooLate()
                revert(0x1c, 0x04)
            }
            // ** initialize cos and cvs arrays memory
            let cos := mload(0x40)
            mstore(cos, activatedOperatorsLength)
            let activatedOperatorsLengthInBytes := shl(5, activatedOperatorsLength)
            let cvs := add(cos, add(0x20, activatedOperatorsLengthInBytes))
            mstore(0x40, cvs)
            mstore(cvs, activatedOperatorsLength)
            mstore(0x40, add(cvs, add(0x20, activatedOperatorsLengthInBytes))) // update the free memory pointer

            let cvsDataPtr := add(cvs, 0x20)
            // ** get cos and cvs
            for { let i := 0 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                mstore(0x00, calldataload(add(secrets.offset, shl(5, i))))
                let cosMemP := add(add(cos, 0x20), shl(5, i))
                mstore(cosMemP, keccak256(0x00, 0x20))
                mstore(add(cvsDataPtr, shl(5, i)), keccak256(cosMemP, 0x20))
            }

            // ** verify reveal order
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let rv := keccak256(add(cos, 0x20), activatedOperatorsLengthInBytes)
            let before := _diff(rv, mload(add(cvsDataPtr, shl(5, calldataload(revealOrders.offset)))))
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                let after :=
                    _diff(rv, mload(add(cvsDataPtr, shl(5, calldataload(add(revealOrders.offset, shl(5, i)))))))
                if lt(before, after) {
                    mstore(0, 0x24f1948e) // selector for RevealNotInDescendingOrder()
                    revert(0x1c, 0x04)
                }
                before := after
            }

            // ** Create Merkle Root and verify it
            let hashCount := sub(activatedOperatorsLength, 1) // unchecked sub, check outside of this function
            let fmp := mload(0x40)
            mstore(fmp, hashCount)
            let hashesDataPtr := add(fmp, 0x20)
            let cvsPos
            let hashPos
            for { let i } lt(i, hashCount) { i := add(i, 1) } {
                switch lt(cvsPos, activatedOperatorsLength)
                case 1 {
                    mstore(0x00, mload(add(cvsDataPtr, shl(5, cvsPos))))
                    cvsPos := add(cvsPos, 1)
                }
                default {
                    mstore(0x00, mload(add(hashesDataPtr, shl(5, hashPos))))
                    hashPos := add(hashPos, 1)
                }
                switch lt(cvsPos, activatedOperatorsLength)
                case 1 {
                    mstore(0x20, mload(add(cvsDataPtr, shl(5, cvsPos))))
                    cvsPos := add(cvsPos, 1)
                }
                default {
                    mstore(0x20, mload(add(hashesDataPtr, shl(5, hashPos))))
                    hashPos := add(hashPos, 1)
                }
                mstore(add(hashesDataPtr, shl(5, i)), keccak256(0x00, 0x40))
            }
            // mstore(0x40, add(hashesDataPtr, shl(5, hashCount))) // update the free memory pointer,
            // or Restore(keep) the free memory pointer
            if iszero(eq(mload(add(hashesDataPtr, shl(5, sub(hashCount, 1)))), sload(s_merkleRoot.slot))) {
                mstore(0, 0x624dc351) // selector for MerkleVerificationFailed()
                revert(0x1c, 0x04)
            }

            // ** verify signer
            mstore(0x20, s_requestInfo.slot)
            let round := sload(s_currentRound.slot)
            mstore(0x00, round)
            let currentRequestInfoSlot := keccak256(0x00, 0x40)
            mstore(fmp, MESSAGE_TYPEHASH_DIRECT) // typehash, overwrite the previous value, which is not used anymore
            mstore(add(fmp, 0x20), sload(add(currentRequestInfoSlot, 1))) // startTime
            mstore(add(fmp, 0x60), hex"1901")
            mstore(add(fmp, 0x62), domainSeparator)
            for { let i } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                // signature malleability prevention
                if gt(
                    calldataload(add(ss.offset, shl(5, i))),
                    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
                ) {
                    mstore(0, 0xbf4bf5b8) // selector for InvalidSignatureS()
                    revert(0x1c, 0x04)
                }
                mstore(add(fmp, 0x40), mload(add(cvsDataPtr, shl(5, i)))) // cv
                mstore(add(fmp, 0x82), keccak256(fmp, 0x60)) // structHash
                mstore(0x00, keccak256(add(fmp, 0x60), 0x42)) // digest hash
                mstore(0x20, and(calldataload(add(vs.offset, shl(5, i))), 0xff)) // v, is and necessary?
                mstore(0x40, calldataload(add(rs.offset, shl(5, i)))) // r
                mstore(0x60, calldataload(add(ss.offset, shl(5, i)))) // s
                let operatorAddress := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                if iszero(returndatasize()) {
                    mstore(0x00, 0x8baa579f) // selector for InvalidSignature()
                    revert(0x1c, 0x04)
                }
                mstore(0x20, s_activatedOperatorIndex1Based.slot)
                mstore(0x00, operatorAddress)
                if iszero(sload(keccak256(0x00, 0x40))) {
                    mstore(0x00, 0x1b256530) // selector for NotActivatedOperator()
                    revert(0x1c, 0x04)
                }
            }
            // mstore(0x60, 0) // Restore the zero slot
            // mstore(0x40, fmp) // Restore the free memory pointer

            // ** create random number
            calldatacopy(fmp, secrets.offset, activatedOperatorsLengthInBytes)
            let randomNumber := keccak256(fmp, activatedOperatorsLengthInBytes)
            let nextRound := add(round, 1)
            switch eq(nextRound, sload(s_requestCount.slot))
            case 1 {
                sstore(s_isInProcess.slot, COMPLETED)
                mstore(0x00, COMPLETED)
                log1(0x00, 0x20, 0x17e36cf3a793ac6f5c5a4f4902aae8748c5c29bf36f9f66870d1728c40bb562a) // emit IsInProcess(COMPLETED)
            }
            default {
                mstore(0x00, nextRound)
                mstore(0x20, s_requestInfo.slot)
                sstore(add(keccak256(0x00, 0x40), 1), timestamp())
                sstore(s_currentRound.slot, nextRound)
                mstore(fmp, nextRound) //round
                mstore(add(fmp, 0x20), timestamp()) // timestamp
                mstore(add(fmp, 0x40), 0x60) // offset
                mstore(add(fmp, 0x60), activatedOperatorsLength) // length

                mstore(0x00, s_activatedOperators.slot)
                let activatedOperatorsSlot := keccak256(0x00, 0x20)
                let startFmp := add(fmp, 0x80)
                for { let i } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                    mstore(add(startFmp, shl(5, i)), sload(add(activatedOperatorsSlot, i)))
                }
                log1(
                    fmp,
                    add(0x80, activatedOperatorsLengthInBytes),
                    0x2195ca2caa394fd192f7f17a47139d963938464c7ad99010b12ef0218c2f0838
                ) // emit RandomNumberRequested(round, timestamp, activatedOperators)
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
            )
            mstore(0x20, s_depositAmount.slot)
            let lastRevealerDepositSlot := keccak256(0x00, 0x40)
            sstore(lastRevealerDepositSlot, add(sload(lastRevealerDepositSlot), sload(add(currentRequestInfoSlot, 2))))

            mstore(0x00, 0x00fc98b8)
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
