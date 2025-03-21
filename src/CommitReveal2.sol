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
        assembly ("memory-safe") {
            activatedOperatorsLength := sload(s_activatedOperators.slot)
            // ** check if all secrets are submitted
            if gt(activatedOperatorsLength, secrets.length) {
                mstore(0, 0xe0767fa4) // selector for InvalidSecretLength()
                revert(0x1c, 0x04)
            }
            // ** check if it is not too late
            // require(
            //     (block.timestamp <
            //         s_merkleRootSubmittedTimestamp +
            //             s_offChainSubmissionPeriod +
            //             (s_offChainSubmissionPeriodPerOperator *
            //                 activatedOperatorsLength) +
            //             s_requestOrSubmitOrFailDecisionPeriod) ||
            //         (block.timestamp <
            //             s_requestedToSubmitCoTimestamp +
            //                 s_onChainSubmissionPeriod +
            //                 (s_offChainSubmissionPeriodPerOperator *
            //                     activatedOperatorsLength) +
            //                 s_requestOrSubmitOrFailDecisionPeriod),
            //     TooLate()
            // );
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
        }

        bytes32[] memory cos = new bytes32[](activatedOperatorsLength);
        bytes32[] memory cvs = new bytes32[](activatedOperatorsLength);
        assembly ("memory-safe") {
            let cvsDataPtr := add(cvs, 0x20)
            for { let i := 0 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                //cos[i] = keccak256(abi.encodePacked(secrets[i]));
                //cvs[i] = keccak256(abi.encodePacked(cos[i]));
                mstore(0x00, calldataload(add(secrets.offset, shl(5, i))))
                let cosMemP := add(add(cos, 0x20), shl(5, i))
                mstore(cosMemP, keccak256(0x00, 0x20))
                mstore(add(cvsDataPtr, shl(5, i)), keccak256(cosMemP, 0x20))
            }

            // ** verify reveal order
            /**
             * uint256 rv = uint256(keccak256(abi.encodePacked(cos)));
             * for (uint256 i = 1; i < secretsLength; i = _unchecked_inc(i)) {
             * require(
             *    diff(rv, cvs[revealOrders[i - 1]]) >
             *        diff(rv, cvs[revealOrders[i]]),
             *    RevealNotInAscendingOrder()
             * );
             *
             * uint256 before = diff(rv, cvs[revealOrders[0]]);
             * for (uint256 i = 1; i < secretsLength; i = _unchecked_inc(i)) {
             *  uint256 after = diff(rv, cvs[revealOrders[i]]);
             *  require(before >= after, RevealNotInAscendingOrder());
             *  before = after;
             * }
             *
             */
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let rv := keccak256(add(cos, 0x20), shl(5, activatedOperatorsLength))
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
            let hashes := mload(0x40)
            mstore(hashes, hashCount)
            let hashesDataPtr := add(hashes, 0x20)
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
        }

        // ** verify signer
        uint256 round = s_currentRound;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTimestamp = requestInfo.startTime;
        for (uint256 i; i < activatedOperatorsLength; i = _unchecked_inc(i)) {
            // signature malleability prevention
            require(ss[i] <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, InvalidSignatureS());
            require(
                s_activatedOperatorIndex1Based[ecrecover(
                    _hashTypedDataV4(
                        keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: startTimestamp, cv: cvs[i]})))
                    ),
                    vs[i],
                    rs[i],
                    ss[i]
                )] > 0,
                InvalidSignature()
            );
        }

        // ** create random number
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(secrets)));
        uint256 nextRound = _unchecked_inc(round);
        unchecked {
            if (nextRound == s_requestCount) {
                s_isInProcess = COMPLETED;
                emit IsInProcess(COMPLETED);
            } else {
                s_requestInfo[nextRound].startTime = block.timestamp;
                s_currentRound = nextRound;
            }
        }
        // reward the last revealer
        s_depositAmount[s_activatedOperators[revealOrders[activatedOperatorsLength - 1]]] += requestInfo.cost;
        emit RandomNumberGenerated(
            round,
            randomNumber,
            _call(
                requestInfo.consumer,
                abi.encodeWithSelector(ConsumerBase.rawFulfillRandomNumber.selector, round, randomNumber),
                requestInfo.callbackGasLimit
            )
        );
    }
}
