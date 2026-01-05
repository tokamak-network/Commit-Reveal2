// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FailLogics} from "./FailLogics.sol";

contract LeaderSelection is FailLogics {
    uint256[] public s_cvsForLeaderSelection;
    uint256[] public s_revealForLeaderSelection;
    uint256 public s_revealStartTimeForLeaderSelection;
    uint256 public s_leaderSelectionTime;
    uint256 public s_commitDurationForLeaderSelection;
    uint256 public s_revealDurationForLeaderSelection;

    error CommitPhaseOver();
    error InvalidCommitValue();
    error AlreadyCommitted();
    error InvalidRevealValue();
    error RevealPhaseNotStarted();
    error RevealPhaseOver();
    error AlreadyRevealed();
    error NotCommitted();

    constructor(
        uint256 commitDurationForLeaderSelection_,
        uint256 revealDurationForLeaderSelection_,
        string memory name,
        string memory version
    ) FailLogics(name, version) {
        s_commitDurationForLeaderSelection = commitDurationForLeaderSelection_;
        s_revealDurationForLeaderSelection = revealDurationForLeaderSelection_;
    }

    function commit(uint256 cv) external {
        uint256 activatedOperatorIndex;
        uint256 activatedOperatorLength;
        if (cv == 0) {
            revert InvalidCommitValue();
        }
        assembly ("memory-safe") {
            let m := mload(0x40)
            if iszero(eq(sload(s_isInProcess.slot), HALTED)) {
                mstore(0, 0x78b19eb2) // selector for NotHalted()
                revert(0x1c, 0x04)
            }
            activatedOperatorLength := sload(s_activatedOperators.slot)
            if lt(activatedOperatorLength, 2) {
                mstore(0, 0x77599fd9) // selector for NotEnoughActivatedOperators()
                revert(0x1c, 0x04)
            }
            mstore(0x00, caller())
            mstore(0x20, s_activatedOperatorIndex1Based.slot)
            activatedOperatorIndex := sub(sload(keccak256(0x00, 0x40)), 1) // overflows when s_activatedOperatorIndex1Based is 0
            if gt(activatedOperatorIndex, MAX_OPERATOR_INDEX) {
                mstore(0, 0x1b256530) // NotActivatedOperator()
                revert(0x1c, 0x04)
            }
        }
        if (s_cvsForLeaderSelection.length == 0) {
            s_cvsForLeaderSelection = new uint256[](activatedOperatorLength);
            s_revealStartTimeForLeaderSelection = block.timestamp + s_commitDurationForLeaderSelection;
        }
        if (block.timestamp >= s_revealStartTimeForLeaderSelection) revert CommitPhaseOver();
        if (s_cvsForLeaderSelection[activatedOperatorIndex] != 0) revert AlreadyCommitted();
        s_cvsForLeaderSelection[activatedOperatorIndex] = cv;
    }

    function reveal(uint256 revealValue) external {
        uint256 activatedOperatorIndex;
        uint256 activatedOperatorLength;
        if (revealValue == 0) {
            revert InvalidRevealValue();
        }
        assembly ("memory-safe") {
            let m := mload(0x40)
            if iszero(eq(sload(s_isInProcess.slot), HALTED)) {
                mstore(0, 0x78b19eb2) // selector for NotHalted()
                revert(0x1c, 0x04)
            }
            activatedOperatorLength := sload(s_activatedOperators.slot)
            if lt(activatedOperatorLength, 2) {
                mstore(0, 0x77599fd9) // selector for NotEnoughActivatedOperators()
                revert(0x1c, 0x04)
            }
            mstore(0x00, caller())
            mstore(0x20, s_activatedOperatorIndex1Based.slot)
            activatedOperatorIndex := sub(sload(keccak256(0x00, 0x40)), 1) // overflows when s_activatedOperatorIndex1Based is 0
            if gt(activatedOperatorIndex, MAX_OPERATOR_INDEX) {
                mstore(0, 0x1b256530) // NotActivatedOperator()
                revert(0x1c, 0x04)
            }
        }
        if (s_revealForLeaderSelection.length == 0) {
            s_revealForLeaderSelection = new uint256[](activatedOperatorLength);
            s_leaderSelectionTime = s_revealStartTimeForLeaderSelection + s_revealDurationForLeaderSelection;
        }
        if (s_cvsForLeaderSelection[activatedOperatorIndex] == 0) revert NotCommitted();
        if (block.timestamp < s_revealStartTimeForLeaderSelection) revert RevealPhaseNotStarted();
        if (block.timestamp >= s_leaderSelectionTime) revert RevealPhaseOver();
        if (s_revealForLeaderSelection[activatedOperatorIndex] != 0) revert AlreadyRevealed();
        s_revealForLeaderSelection[activatedOperatorIndex] = revealValue;
    }
}
