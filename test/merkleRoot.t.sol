// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2L2} from "./../src/CommitReveal2L2.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/Test.sol";

contract MerkleRootTest is Test {
    // ** Contracts
    function createMerkleRoot(
        bytes32[] memory leaves
    ) private pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function unchecked_inc(uint256 x) private pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    function _efficientKeccak256(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function test_merkleRoot() public pure {
        bytes32[] memory leaves = new bytes32[](2);
        leaves[
            0
        ] = hex"3edf919b45cf43b997461b1f2e409f47960e363ebf0a33d1d5a33f7ff094b3b3";
        leaves[
            1
        ] = hex"07190cfb67fa9d5fb57f4acfa9a494140181449f84d3a632b8e6f5d41e8f8ab0";

        console2.logBytes32(createMerkleRoot(leaves));
    }
}
