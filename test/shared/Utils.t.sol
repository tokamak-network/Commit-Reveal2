// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2Hybrid} from "./../../src/CommitReveal2Hybrid.sol";

contract Utils {
    string public name = "Commit Reveal2";
    string public version = "1";
    bytes32 public nameHash = keccak256(bytes(name));
    bytes32 public versionHash = keccak256(bytes(version));

    uint256 s_requestTestNum = 21;
    uint256 public s_activationThreshold = 0.01 ether;
    uint256 public s_requestFee = 0.001 ether;
    uint256 public s_maxOperators = 10;

    function isNotFirstRound(uint256 round) public pure returns (bool) {
        return round != 0;
    }

    function getAverage(uint256[] memory data) public pure returns (uint256) {
        uint256 sum;
        for (uint256 i; i < data.length; i++) {
            sum += data[i];
        }
        return sum / data.length;
    }

    function getHashTypedDataV4(
        address verifier,
        uint256 round,
        bytes32 cv
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    hex"19_01",
                    keccak256(
                        abi.encode(
                            keccak256(
                                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                            ),
                            nameHash,
                            versionHash,
                            block.chainid,
                            verifier
                        )
                    ),
                    keccak256(
                        abi.encode(
                            keccak256("Message(uint256 round,bytes32 cv)"),
                            CommitReveal2Hybrid.Message({round: round, cv: cv})
                        )
                    )
                )
            );
    }

    function getMerkleRoot(
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

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }
}
