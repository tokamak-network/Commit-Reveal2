// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";

contract CommitReveal2TestSolidity is CommitReveal2 {
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

    function getMessageHash(uint256 timestamp, bytes32 cv) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: timestamp, cv: cv}))));
    }

    function generateRandomNumber() external {
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

        // ** initialize cos and cvs arrays memory
        //bytes32[] memory cos = new bytes32[](activatedOperatorsLength);
        //bytes32[] memory cvs = new bytes32[](activatedOperatorsLength);

        //for { let i := 0 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
        //cos[i] = keccak256(abi.encodePacked(secrets[i]));
        //cvs[i] = keccak256(abi.encodePacked(cos[i]));
        //}

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

        // ** verify signer
        // uint256 round = s_currentRound;
        // RequestInfo storage requestInfo = s_requestInfo[round];
        // uint256 startTimestamp = requestInfo.startTime;
        // for (uint256 i; i < activatedOperatorsLength; i = _unchecked_inc(i)) {
        //     // signature malleability prevention
        //     require(ss[i] <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, InvalidSignatureS());
        //     require(
        //         s_activatedOperatorIndex1Based[ecrecover(
        //             _hashTypedDataV4(
        //                 keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: startTimestamp, cv: cvs[i]})))
        //             ),
        //             vs[i],
        //             rs[i],
        //             ss[i]
        //         )] > 0,
        //         InvalidSignature()
        //     );
        // }

        // ** create random number
        // uint256 randomNumber = uint256(keccak256(abi.encodePacked(secrets)));
        // uint256 nextRound = _unchecked_inc(round);
        // unchecked {
        //     if (nextRound == s_requestCount) {
        //         s_isInProcess = COMPLETED;
        //         emit IsInProcess(COMPLETED);
        //     } else {
        //         s_requestInfo[nextRound].startTime = block.timestamp;
        //         s_currentRound = nextRound;
        //     }
        // }
        // // reward the last revealer
        // s_depositAmount[s_activatedOperators[revealOrders[activatedOperatorsLength - 1]]] += requestInfo.cost;
        // emit RandomNumberGenerated(
        //     round,
        //     randomNumber,
        //     _call(
        //         requestInfo.consumer,
        //         abi.encodeWithSelector(ConsumerBase.rawFulfillRandomNumber.selector, round, randomNumber),
        //         requestInfo.callbackGasLimit
        //     )
        // );
    }

    function diff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}

contract CreateMerkleRootSolidity is CommitReveal2 {
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

    function createMR(bytes32[] memory leaves) external pure returns (bytes32) {
        return createMerkleRoot(leaves);
    }

    function unchecked_dec(uint256 i) private pure returns (uint256) {
        unchecked {
            return i - 1;
        }
    }

    function createMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = unchecked_dec(leavesLen);
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = _unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function _efficientKeccak256(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

contract CreateMerkleRootInlineAssembly is CommitReveal2 {
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

    function createMR(bytes32[] memory leaves) external pure returns (bytes32) {
        return _createMerkleRoot(leaves);
    }

    /**
     * @notice Constructs a Merkle tree from an array of leaves and returns its root.
     * @dev Uses inline assembly to iteratively combine leaves or intermediate hashes:
     *      - Each loop merges two values (either from `leaves` or from the newly produced `hashes`)
     *        and stores the keccak256 hash back into `hashes`.
     *      - The final element in `hashes` is returned as the Merkle root.
     * @param leaves The array of leaves to be combined into a Merkle tree (length must be > 1).
     * @return r The computed Merkle root.
     */
    function _createMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32 r) {
        assembly ("memory-safe") {
            let leavesLen := mload(leaves)
            let hashCount := sub(leavesLen, 1) // unchecked sub, check outside of this function
            let hashes := mload(0x40)
            mstore(hashes, hashCount)
            let hashesDataPtr := add(hashes, 0x20)
            let leavesDataPtr := add(leaves, 0x20)
            let leafPos
            let hashPos
            for { let i } lt(i, hashCount) { i := add(i, 1) } {
                switch lt(leafPos, leavesLen)
                case 1 {
                    mstore(0x00, mload(add(leavesDataPtr, shl(5, leafPos))))
                    leafPos := add(leafPos, 1)
                }
                default {
                    mstore(0x00, mload(add(hashesDataPtr, shl(5, hashPos))))
                    hashPos := add(hashPos, 1)
                }
                switch lt(leafPos, leavesLen)
                case 1 {
                    mstore(0x20, mload(add(leavesDataPtr, shl(5, leafPos))))
                    leafPos := add(leafPos, 1)
                }
                default {
                    mstore(0x20, mload(add(hashesDataPtr, shl(5, hashPos))))
                    hashPos := add(hashPos, 1)
                }
                mstore(add(hashesDataPtr, shl(5, i)), keccak256(0x00, 0x40))
            }
            mstore(0x40, add(hashesDataPtr, shl(5, hashCount))) // update the free memory pointer
            r := mload(add(hashesDataPtr, shl(5, sub(hashCount, 1))))
        }
    }
}
