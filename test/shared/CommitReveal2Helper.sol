// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2Storage} from "./../../src/CommitReveal2.sol";
import {Vm} from "forge-std/Test.sol";

contract CommitReveal2Helper {
    uint256 private s_nonce;
    bytes32 public s_nameHash;
    bytes32 public s_versionHash;
    address s_commitReveal2Address;

    function _createMerkleRoot(
        bytes32[] memory leaves
    ) internal pure returns (bytes32) {
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

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
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

    function _generateSCoCv()
        internal
        returns (bytes32 s, bytes32 co, bytes32 cv)
    {
        s = keccak256(abi.encodePacked(s_nonce++));
        co = keccak256(abi.encodePacked(s));
        cv = keccak256(abi.encodePacked(co));
    }

    function _getEachPhaseStartOffset(
        uint256[11] memory phaseDuration
    ) internal pure returns (uint256[11] memory) {
        uint256[11] memory eachPhaseStartOffset;
        eachPhaseStartOffset[0] = 0;
        for (uint256 i = 1; i < 11; i++) {
            eachPhaseStartOffset[i] =
                eachPhaseStartOffset[i - 1] +
                phaseDuration[i - 1];
        }
        return eachPhaseStartOffset;
    }

    function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _getTypedDataHash(
        uint256 timestamp,
        bytes32 cv
    ) internal view returns (bytes32 typedDataHash) {
        typedDataHash = keccak256(
            abi.encodePacked(
                hex"19_01",
                keccak256(
                    abi.encode(
                        keccak256(
                            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                        ),
                        s_nameHash,
                        s_versionHash,
                        block.chainid,
                        s_commitReveal2Address
                    )
                ),
                keccak256(
                    abi.encode(
                        keccak256("Message(uint256 timestamp,bytes32 cv)"),
                        CommitReveal2Storage.Message({
                            timestamp: timestamp,
                            cv: cv
                        })
                    )
                )
            )
        );
    }
}
