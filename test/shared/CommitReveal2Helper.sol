// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {CommitReveal2Storage} from "./../../src/CommitReveal2.sol";
import {console2} from "forge-std/Test.sol";
import {Bitmap} from "../../src/libraries/Bitmap.sol";

contract CommitReveal2Helper {
    uint256 private s_nonce;
    bytes32 public s_nameHash;
    bytes32 public s_versionHash;
    address s_commitReveal2Address;

    function _createMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function _efficientKeccak256(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _generateSCoCv() internal returns (bytes32 s, bytes32 co, bytes32 cv) {
        s = keccak256(abi.encodePacked(s_nonce++));
        co = keccak256(abi.encodePacked(s));
        cv = keccak256(abi.encodePacked(co));
    }

    function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _nextRequestedRound(uint256 word, uint8 bitPos, uint256 round)
        internal
        pure
        returns (uint256 next, bool requested)
    {
        unchecked {
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = word & mask;

            // if there are no requested rounds to the left of the current round, return leftmost in the word
            requested = masked != 0;
            next = requested ? round + Bitmap.leastSignificantBit(masked) - bitPos : round + type(uint8).max - bitPos;
        }
    }

    function consoleDepositsAndSlashRewardAccumulated(
        CommitReveal2 commitReveal2,
        address[10] memory operators,
        address leaderNode,
        address extraAddress
    ) internal view {
        uint256 sum;
        // *** Deposit + SlashReward
        for (uint256 i = 0; i < operators.length; i++) {
            sum += commitReveal2.getDepositPlusSlashReward(operators[i]);
        }
        sum += commitReveal2.getDepositPlusSlashReward(leaderNode);
        sum += commitReveal2.getDepositPlusSlashReward(extraAddress);

        // *** accumulated request fees
        uint256 nextRequestedRound = commitReveal2.s_currentRound();
        bool requested;
        uint256 requestCount = commitReveal2.s_requestCount();
        uint256 lastfulfilledRound = commitReveal2.s_lastfulfilledRound();
        for (uint256 i; i < 10; i++) {
            uint248 wordPos = uint248(nextRequestedRound >> 8);
            uint8 bitPos;
            assembly ("memory-safe") {
                bitPos := and(nextRequestedRound, 0xff)
            }
            uint256 word = commitReveal2.s_roundBitmap(wordPos);
            (nextRequestedRound, requested) = _nextRequestedRound(word, bitPos, nextRequestedRound);
            if (requested) {
                if (nextRequestedRound == lastfulfilledRound) {
                    break;
                }
                (,, uint256 cost,) = commitReveal2.s_requestInfo(nextRequestedRound);
                sum += cost;
            }
            if (++nextRequestedRound >= requestCount) {
                break;
            }
        }

        console2.log("get all depositPlusSlashReward and contract balance and compare");
        console2.log(sum);
        console2.log(address(commitReveal2).balance);
        console2.log("difference");
        console2.log(_diff(sum, address(commitReveal2).balance));
        console2.log("--------------------");
    }

    function consoleDeposits(CommitReveal2 commitReveal2, address[10] memory operators, address leaderNode)
        internal
        view
    {
        for (uint256 i = 0; i < operators.length; i++) {
            console2.log(commitReveal2.s_depositAmount(operators[i]));
        }
        console2.log(commitReveal2.s_depositAmount(leaderNode));
        console2.log("--------------------");
    }

    function consoleSlashRewardAccumulated(
        CommitReveal2 commitReveal2,
        address[10] memory operators,
        address leaderNode
    ) internal view {
        uint256 globalSlashRewardPerOperator = commitReveal2.s_slashRewardPerOperator();
        for (uint256 i = 0; i < operators.length; i++) {
            console2.log(globalSlashRewardPerOperator - commitReveal2.s_slashRewardPerOperatorPaid(operators[i]));
        }
        console2.log(globalSlashRewardPerOperator - commitReveal2.s_slashRewardPerOperatorPaid(leaderNode));
        console2.log("--------------------");
    }

    function _getTypedDataHash(uint256 timestamp, bytes32 cv) internal view returns (bytes32 typedDataHash) {
        typedDataHash = keccak256(
            abi.encodePacked(
                hex"1901",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        s_nameHash,
                        s_versionHash,
                        block.chainid,
                        s_commitReveal2Address
                    )
                ),
                keccak256(
                    abi.encode(
                        keccak256("Message(uint256 timestamp,bytes32 cv)"),
                        CommitReveal2Storage.Message({timestamp: timestamp, cv: cv})
                    )
                )
            )
        );
    }
}
