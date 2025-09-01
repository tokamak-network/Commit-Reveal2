// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract CreateMerkleRootSolidity {
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

    function _unchecked_inc(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function _efficientKeccak256(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

contract CreateMerkleRootInlineAssembly {
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
            let leavesLenInBytes := shl(5, mload(leaves))
            let hashCountInBytes := sub(leavesLenInBytes, 0x20) // unchecked sub, check outside of this function
            let hashes := mload(0x40)
            mstore(hashes, hashCountInBytes)
            let hashDataPtr := add(hashes, 0x20)
            let leafDataPtr := add(leaves, 0x20)
            let leafPosInBytes
            let hashPosInBytes
            for { let i } lt(i, hashCountInBytes) { i := add(i, 0x20) } {
                switch lt(leafPosInBytes, leavesLenInBytes)
                case 1 {
                    mstore(0x00, mload(add(leafDataPtr, leafPosInBytes)))
                    leafPosInBytes := add(leafPosInBytes, 0x20)
                }
                default {
                    mstore(0x00, mload(add(hashDataPtr, hashPosInBytes)))
                    hashPosInBytes := add(hashPosInBytes, 0x20)
                }
                switch lt(leafPosInBytes, leavesLenInBytes)
                case 1 {
                    mstore(0x20, mload(add(leafDataPtr, leafPosInBytes)))
                    leafPosInBytes := add(leafPosInBytes, 0x20)
                }
                default {
                    mstore(0x20, mload(add(hashDataPtr, hashPosInBytes)))
                    hashPosInBytes := add(hashPosInBytes, 0x20)
                }
                mstore(add(hashDataPtr, i), keccak256(0x00, 0x40))
            }
            mstore(0x40, add(hashDataPtr, hashCountInBytes)) // update the free memory pointer
            r := mload(add(hashDataPtr, sub(hashCountInBytes, 0x20)))
        }
    }
}
