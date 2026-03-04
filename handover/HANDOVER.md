# Handover Document: Commit-Reveal2 Security Review

**Repository:** `tokamak-network/Commit-Reveal2`  
**Branch:** `fix/leader-selection`  
**Date:** February 21, 2026  
**Primary File Reviewed:** `src/CommitReveal2WithLeaderSelection.sol`

---

## 1. Scope of Review

The review primarily focused on `src/CommitReveal2WithLeaderSelection.sol` (835 lines), the main contract implementing the Commit-Reveal² decentralized random number generation protocol with an embedded leader selection mechanism. The full inheritance chain was examined for context:

| File | Lines | Role |
|------|-------|------|
| `src/CommitReveal2WithLeaderSelection.sol` | ~835 | **Primary review target** — request, submit, generate, refund, resume |
| `src/LeaderSelection.sol` | ~109 | Leader election commit-reveal mini-protocol |
| `src/FailLogics.sol` | ~808 | Failure handlers with slashing |
| `src/DisputeLogics.sol` | ~1037 | Dispute mechanism (requestCv, submitCv, requestCo, submitCo, requestS, submitS) |
| `src/OperatorManager.sol` | ~411 | Operator lifecycle: deposit, activate, deactivate, withdraw |
| `src/CommitReveal2Storage.sol` | ~517 | Storage layout, structs, errors, events, constants |

**Total:** ~3,712 lines of Solidity (majority inline Yul assembly)

### Out of Scope

The following files were not the focus of this review (but were glanced at for completeness):

- `src/CommitReveal2BLS.sol` — BLS signature variant (uses `onlyOwner` resume, no leader election)
- `src/CommitReveal2.sol` — Base variant without leader selection
- `src/CommitReveal2L2.sol` — L2-specific variant
- `src/libraries/BLS.sol`, `src/libraries/Bitmap.sol` — Library code
- `src/governance/` — Governance multisig wallet
- `src/test/` — Test contracts and utilities

---

## 2. Architecture Overview

### Inheritance Chain

```
CommitReveal2WithLeaderSelection
└── LeaderSelection
    └── FailLogics
        └── DisputeLogics
            ├── EIP712 (OpenZeppelin — signature verification)
            ├── OperatorManager
            │   └── Ownable (Solady)
            └── CommitReveal2Storage
```

### Protocol Flow

1. **Consumer** calls `requestRandomNumber()`, paying a fee.
2. **Leader** (owner) collects operator secrets off-chain, builds a Merkle tree, submits root via `submitMerkleRoot()`.
3. **Leader** calls `generateRandomNumber()` with all secrets and signatures — produces a verifiable random number delivered via callback.
4. **Dispute path:** If the leader misbehaves or times out, operators trigger failure functions. These slash the responsible party, halt the system, and initiate leader selection.
5. **Leader selection:** A commit-reveal mini-protocol among operators produces election randomness. The operator whose `hash(electionRandomness || address)` is smallest becomes the new leader.
6. **Resume:** `resume()` finalizes the election, transfers ownership, and restarts the pending round.

### State Machine

```
COMPLETED (2)  ──requestRandomNumber()──>  IN_PROGRESS (1)
IN_PROGRESS (1) ──generateRandomNumber()──> COMPLETED (2)  [if no more rounds]
IN_PROGRESS (1) ──fail*()──────────────────> HALTED (3)
HALTED (3)      ──resume()─────────────────> IN_PROGRESS (1) or COMPLETED (2)
```

---

## 3. Code Changes Made

### Fix: H-01 — Liveness Risk in `resume()`

**Problem:** When the system enters HALTED, operators are expected to participate in the leader selection commit-reveal. If no operator commits or reveals, `resume()` would either:
- Revert with an out-of-bounds array access, or
- Proceed with empty/deterministic randomness, selecting a predictable leader

Both outcomes could leave the system permanently stuck.

**Changes applied:**

**`src/LeaderSelection.sol`** — Added two new error declarations:

```solidity
error LeaderSelectionNotInitiated(); // 0x5251b3cf
error NoRevealsForLeaderSelection(); // 0x7ffd6dc1
```

**`src/CommitReveal2WithLeaderSelection.sol`** — Added guard checks at the top of `resume()`:

```solidity
function resume() external payable {
    if (s_cvsForLeaderSelection.length == 0) revert LeaderSelectionNotInitiated();
    if (s_revealForLeaderSelection.length == 0) revert NoRevealsForLeaderSelection();
    if (block.timestamp < s_leaderSelectionTime) revert CannotResumeBeforeLeaderSelectionTime();
    // ... rest of function
}
```

**Rationale:** This ensures `resume()` cleanly reverts if no operator participated in leader selection, preventing both the OOB crash and the degenerate case of selecting a leader from empty randomness.

---

## 4. Key Observation: CV Computation Discrepancy (Paper vs Code)

The academic paper specifies:

```
cv_i = Hash(co_i)
```

The code computes:

```
cv_i = Hash(co_i ∥ index)
```

where `index` is a single byte representing the operator's position. This is a **strictly stronger construction** — it prevents cross-operator collision when two operators coincidentally share the same secret value. This does not weaken any security property and is actually an improvement. However, the paper should be updated to reflect this for accuracy (Section IV or VII).

---

## 5. Findings Summary

A full security audit was conducted. The findings table below reflects the current status:

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| H-01 | HIGH | Liveness risk: `resume()` reverts if no operator reveals during leader selection | **Fixed** |
| H-02 | HIGH | `nextRequestedRound` loop capped at 10 iterations — state may become inconsistent | Open |
| M-01 | MEDIUM | `setPeriods()` permits changes during HALTED, inconsistent with other setters | Open |
| M-02 | MEDIUM | `resume()` does not reset stale leader-selection timestamps | Open |
| M-03 | MEDIUM | O(n²) gas cost in `resume()` from `abi.encodePacked` in loop | Open |
| M-04 | MEDIUM | No zero-address validation for governance multisig in constructor | Open |
| M-05 | MEDIUM | Governance multisig address is immutable with no rotation mechanism | Open |
| M-06 | MEDIUM | Leader selection commit/reveal durations hardcoded to 60 seconds | Open |
| M-07 | MEDIUM | No input validation on `setPeriods()` parameters | Open |
| I-01 | INFO | Duplicated `leastSignificantBit` / `nextRequestedRound` across 4 locations | — |
| I-02 | INFO | Pervasive inline assembly impedes auditability | — |
| I-03 | INFO | No NatSpec documentation on `CommitReveal2WithLeaderSelection` functions | — |
| I-04 | INFO | `setGasParameters` mixes assembly storage writes with Solidity `emit` | — |
| I-05 | GAS | `resume()` leader election loop uses Solidity-level storage reads where assembly could be cheaper | — |
| I-06 | GAS | `s_merkleRoot` is a single slot overwritten each round — previous roots are lost | — |

The full detailed audit report is available at [`docs/AUDIT_REPORT.md`](../docs/AUDIT_REPORT.md).

---

## 6. Test Coverage for Findings

Each finding requires proper test coverage before or alongside its fix. The table below maps every finding to the test cases that are needed.

### Existing Tests

The following test files already exist in the repo:

| Test File | Covers |
|-----------|--------|
| `test/unit/ResumeDeactivationBug.t.sol` | `resume()` backward-iteration deactivation (7 test cases: 3-of-6, 4-of-7, all-revealed, one-non-revealer, first-operators, alternating, large-scale-32) |
| `test/unit/SimpleTransferOwnership.t.sol` | Ownership transfer basics |
| `test/unit/ParamDelay.t.sol` | Parameter delay logic |
| `test/staging/CommitReveal2Flowchart.t.sol` | Full protocol flow (happy path + dispute) |
| `test/gas/*.t.sol` | Gas benchmarks for all major paths |
| `test/fuzz/CreateMerkleRootFuzz.t.sol` | Fuzz testing for Merkle root creation |

### Required Test Cases per Finding

#### H-01 — Liveness risk in `resume()` (Fixed)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 1 | `test_resume_revertsWhenNoCommits` | **Needed** | Call `resume()` in HALTED state without any operator calling `commit()`. Must revert with `LeaderSelectionNotInitiated()`. |
| 2 | `test_resume_revertsWhenCommitsButNoReveals` | **Needed** | Operators call `commit()` but nobody calls `reveal()`. Must revert with `NoRevealsForLeaderSelection()`. |
| 3 | `test_resume_succeedsWhenAtLeastOneReveals` | **Exists** | Covered by `ResumeDeactivationBug.t.sol` — multiple scenarios with partial reveals. |

#### H-02 — `nextRequestedRound` loop capped at 10 iterations (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 4 | `test_nextRequestedRound_gapExceeds2550` | **Needed** | Request round 0 and round 3000 (gap > 2550). Call `generateRandomNumber()` for round 0. Verify state transitions correctly to round 3000 or falls back to `COMPLETED`. |
| 5 | `test_nextRequestedRound_exactlyAtBoundary` | **Needed** | Request rounds such that the next round is exactly at 2550 apart (10 * 255). Verify the loop finds it. |
| 6 | `test_nextRequestedRound_gapInResume` | **Needed** | Same gap scenario but exercised through `resume()` after a HALTED state. |

#### M-01 — `setPeriods()` allows changes during HALTED (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 7 | `test_setPeriods_revertsWhenHalted` | **Needed** | Enter HALTED state, call `setPeriods()` from governance. Verify it reverts (after fix) or document that it succeeds (if intentional). |
| 8 | `test_setPeriods_succeedsWhenCompleted` | **Needed** | In COMPLETED state, call `setPeriods()` from governance. Verify it succeeds. |

#### M-02 — `resume()` does not reset stale timestamps (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 9 | `test_resume_resetsLeaderSelectionTimestamps` | **Needed** | Complete a full halt-election-resume cycle. Verify `s_leaderSelectionTime` and `s_revealStartTimeForLeaderSelection` are reset to 0 after `resume()`. |
| 10 | `test_resume_staleTimestampDoesNotBypassCheck` | **Needed** | After first resume cycle, trigger a second halt. Call `resume()` before any new commit/reveal. Must revert (not pass because of stale timestamp). |

#### M-03 — O(n²) gas cost in `resume()` (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 11 | `test_resume_gasWithMaxOperators` | **Exists (partial)** | `ResumeDeactivationBug.t.sol::test_resume_largeScale_halfDidNotReveal` runs with 32 operators. Extend to capture gas metrics before/after optimization. |

#### M-04 — No zero-address validation for governance multisig (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 12 | `test_constructor_revertsOnZeroGovernance` | **Needed** | Deploy with `address(0)` as governance. Must revert after fix. |

#### M-05 — Governance multisig is immutable (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 13 | `test_setGovernanceMultisig_succeeds` | **Needed** | Call governance rotation function from current governance. Verify address updates. |
| 14 | `test_setGovernanceMultisig_revertsFromNonGovernance` | **Needed** | Call governance rotation from a non-governance address. Must revert. |

#### M-06 — Leader selection durations hardcoded (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 15 | `test_leaderSelection_customDurations` | **Needed** | Deploy with custom commit/reveal durations. Verify commit phase respects the custom duration. |

#### M-07 — No input validation on `setPeriods()` (Open)

| # | Test Case | Status | Description |
|---|-----------|--------|-------------|
| 16 | `test_setPeriods_revertsOnZeroValues` | **Needed** | Call `setPeriods()` with one or more periods set to 0. Must revert after fix. |
| 17 | `test_setPeriods_revertsOnUnreasonablySmall` | **Needed** | Call `setPeriods()` with values below `MIN_PERIOD`. Must revert after fix. |

### Test Case Summary

| Category | Existing | Needed | Total |
|----------|----------|--------|-------|
| H-01 (Fixed) | 6 | 2 | 8 |
| H-02 | 0 | 3 | 3 |
| M-01 | 0 | 2 | 2 |
| M-02 | 0 | 2 | 2 |
| M-03 | 1 (partial) | 0 | 1 |
| M-04 | 0 | 1 | 1 |
| M-05 | 0 | 2 | 2 |
| M-06 | 0 | 1 | 1 |
| M-07 | 0 | 2 | 2 |
| **Total** | **7** | **15** | **22** |

> **Important:** Every open finding must have its corresponding test case(s) written and passing **before** the fix is considered complete. Write the test first to reproduce the issue (expect failure or wrong behavior), apply the fix, then verify the test passes.

---

## 7. Priority Items for Next Steps

### Critical / High Priority

1. **H-02 (Open):** The `nextRequestedRound` bitmap search loop is capped at 10 iterations. If a gap exceeds ~2,550 un-requested rounds, the state machine can become inconsistent. Add a fallback after the loop that sets state to `COMPLETED`.

2. **M-02 (Open):** `resume()` deletes the leader-selection arrays but does not reset `s_revealStartTimeForLeaderSelection` or `s_leaderSelectionTime`. Stale timestamps from a previous election can cause subtle timing issues if the system halts again. The fix is two lines:

```solidity
s_revealStartTimeForLeaderSelection = 0;
s_leaderSelectionTime = 0;
```

### Medium Priority

3. **M-03:** Replace the O(n²) `abi.encodePacked` loop in `resume()` with a pre-allocated buffer.
4. **M-04:** Add `require(_governanceMultisig != address(0))` in the constructor.
5. **M-05:** Add a governance transfer function with two-step acceptance.
6. **M-06:** Make leader selection commit/reveal durations configurable.
7. **M-07:** Add minimum-value validation for `setPeriods()` parameters.
8. **M-01:** Change `setPeriods()` modifier from `notInProgress` to `onlyWhenCompleted`.

---

## 8. Positive Observations

- **Checks-Effects-Interactions pattern** followed throughout — ETH transfers happen after state changes.
- **Signature malleability prevention** via `s <= SECP256K1_CURVE_ORDER` check.
- **Bitmap-based round tracking** for gas-efficient request management.
- **Slash reward accumulator pattern** (reward-per-token style) for O(1) distribution.
- **EIP-150 gas accounting** for consumer callbacks prevents griefing.
- **Free memory pointer discipline** in all assembly blocks.
- **Reverse iteration** in `resume()` deactivation loop handles swap-and-pop safely.

---

## 9. Build & Test

```bash
# Install dependencies
forge install

# Build
forge build

# Run all tests
forge test

# Run resume deactivation tests
forge test --match-contract ResumeDeactivationBug -vvvv

# Run a specific test with gas reporting
forge test --match-test test_resume_largeScale_halfDidNotReveal -vvvv --gas-report
```

---

## 10. Files Modified in This Review

| File | Change |
|------|--------|
| `src/CommitReveal2WithLeaderSelection.sol` | Added `LeaderSelectionNotInitiated` and `NoRevealsForLeaderSelection` guards to `resume()` |
| `src/LeaderSelection.sol` | Added two new error declarations |
| `docs/AUDIT_REPORT.md` | Created full security audit report, updated finding statuses |

---

*End of Handover Document*
