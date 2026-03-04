// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {CommitReveal2WithLeaderSelection} from "../../src/CommitReveal2WithLeaderSelection.sol";
import {ConsumerExample} from "../../src/ConsumerExample.sol";

/**
 * @title ResumeDeactivationBugTest
 * @notice Tests for the bug in resume() where forward-iterating over s_activatedOperators
 *         while calling _deactivate (swap-and-pop) causes array out-of-bounds errors
 *         when multiple operators need to be deactivated.
 *
 * Bug scenario (with old forward-iteration code):
 *   - 6 activated operators at indices [0..5], operators[3,4,5] didn't reveal
 *   - Loop caches original length = 6
 *   - i=3: deactivate op3. _deactivate swaps op3 with op5, pops. Array length = 5
 *   - i=4: deactivate op4. _deactivate pops op4. Array length = 4
 *   - i=5: s_activatedOperators[5] => OUT OF BOUNDS! Array only has 4 elements.
 *
 * Fix: Iterate backwards so _deactivate's swap-and-pop never affects unvisited indices.
 */
contract ResumeDeactivationBugTest is Test {
    CommitReveal2WithLeaderSelection public commitReveal2;
    ConsumerExample public consumerExample;

    address constant LEADER = address(0xBcd4042DE499D14e55001CcbB24a551F3b954096);
    address constant GOVERNANCE = address(0xdead);

    uint256 constant ACTIVATION_THRESHOLD = 0.01 ether;
    uint256 constant FLAT_FEE = 0.001 ether;
    uint256 constant MAX_GAS_PRICE = 15 gwei;

    // Timing parameters
    uint256 constant OFF_CHAIN_SUBMISSION_PERIOD = 40;
    uint256 constant REQUEST_OR_SUBMIT_OR_FAIL_DECISION_PERIOD = 30;
    uint256 constant ON_CHAIN_SUBMISSION_PERIOD = 60;
    uint256 constant OFF_CHAIN_SUBMISSION_PERIOD_PER_OPERATOR = 20;
    uint256 constant ON_CHAIN_SUBMISSION_PERIOD_PER_OPERATOR = 30;

    // Leader selection timing (hardcoded in constructor: 60s commit, 60s reveal)
    uint256 constant COMMIT_DURATION = 60;
    uint256 constant REVEAL_DURATION = 60;

    address[] public operators;
    uint256[] public operatorKeys;
    uint256 public numOperators;

    function setUp() public {
        vm.deal(LEADER, 10000 ether);
        vm.deal(GOVERNANCE, 1 ether);
    }

    /// @dev Deploy contracts and set up a given number of operators
    function _setupWithOperators(uint256 count) internal {
        numOperators = count;

        // Deploy CommitReveal2WithLeaderSelection as LEADER
        vm.startPrank(LEADER);
        commitReveal2 = new CommitReveal2WithLeaderSelection{value: ACTIVATION_THRESHOLD}(
            ACTIVATION_THRESHOLD,
            FLAT_FEE,
            "Commit Reveal2",
            "1",
            OFF_CHAIN_SUBMISSION_PERIOD,
            REQUEST_OR_SUBMIT_OR_FAIL_DECISION_PERIOD,
            ON_CHAIN_SUBMISSION_PERIOD,
            OFF_CHAIN_SUBMISSION_PERIOD_PER_OPERATOR,
            ON_CHAIN_SUBMISSION_PERIOD_PER_OPERATOR,
            MAX_GAS_PRICE,
            GOVERNANCE
        );
        vm.stopPrank();

        // Deploy ConsumerExample
        consumerExample = new ConsumerExample(address(commitReveal2));

        // Create and fund operators
        for (uint256 i = 0; i < count; i++) {
            (address addr, uint256 key) = makeAddrAndKey(string(abi.encodePacked("op", i)));
            operators.push(addr);
            operatorKeys.push(key);
            vm.deal(addr, 10000 ether);
        }

        // Activate all operators
        for (uint256 i = 0; i < count; i++) {
            vm.prank(operators[i]);
            commitReveal2.depositAndActivate{value: ACTIVATION_THRESHOLD}();
        }

        assertEq(commitReveal2.getActivatedOperatorsLength(), count);
    }

    /// @dev Advance time
    function _mine(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
        vm.roll(block.number + 1);
    }

    /// @dev Get the contract into HALTED state
    function _getIntoHaltedState() internal {
        vm.txGasPrice(10 gwei);
        uint256 requestFee = commitReveal2.estimateRequestPrice(90000, tx.gasprice);
        vm.deal(address(this), requestFee);
        consumerExample.requestRandomNumber{value: requestFee}();

        _mine(OFF_CHAIN_SUBMISSION_PERIOD + REQUEST_OR_SUBMIT_OR_FAIL_DECISION_PERIOD);
        commitReveal2.failToRequestSubmitCvOrSubmitMerkleRoot();

        assertEq(commitReveal2.s_isInProcess(), 3, "Should be HALTED");
    }

    /// @dev Have specified operators commit and reveal; the rest do not participate
    /// @param revealingIndices Array of indices into the `operators` array for operators that commit+reveal
    function _commitAndReveal(uint256[] memory revealingIndices) internal {
        // Build commit values
        uint256[] memory secrets = new uint256[](revealingIndices.length);
        uint256[] memory revealValues = new uint256[](revealingIndices.length);
        uint256[] memory cvs = new uint256[](revealingIndices.length);

        for (uint256 i = 0; i < revealingIndices.length; i++) {
            secrets[i] = 1000 + revealingIndices[i];
            revealValues[i] = uint256(keccak256(abi.encodePacked(secrets[i])));
            cvs[i] = uint256(keccak256(abi.encodePacked(revealValues[i])));
        }

        // Commit phase
        for (uint256 i = 0; i < revealingIndices.length; i++) {
            vm.prank(operators[revealingIndices[i]]);
            commitReveal2.commit(cvs[i]);
        }

        // Wait for commit phase to end
        _mine(COMMIT_DURATION);

        // Reveal phase
        for (uint256 i = 0; i < revealingIndices.length; i++) {
            vm.prank(operators[revealingIndices[i]]);
            commitReveal2.reveal(revealValues[i]);
        }

        // Wait for reveal phase to end
        _mine(REVEAL_DURATION);

        assertTrue(block.timestamp >= commitReveal2.s_leaderSelectionTime(), "Past leader selection time");
    }

    /// @dev Call resume and verify basic invariants
    function _callResume() internal {
        address caller = makeAddr("resumeCaller");
        vm.deal(caller, 10 ether);
        vm.prank(caller);
        commitReveal2.resume{value: ACTIVATION_THRESHOLD}();
    }

    // =========================================================================
    //                              TEST CASES
    // =========================================================================

    /**
     * @notice Core bug test: 3 out of 6 operators didn't reveal.
     *
     * With the OLD forward-iteration code, this would revert:
     *   - Cached length = 6
     *   - Deactivate at i=3: array shrinks to 5
     *   - Deactivate at i=4: array shrinks to 4
     *   - Access s_activatedOperators[5] at i=5 => OUT OF BOUNDS
     *
     * After fix (backward iteration): works correctly.
     * Final state: 6 - 3(non-revealers) - 1(new leader) = 2 operators remain.
     */
    function test_resume_multipleDeactivations_3of6() public {
        _setupWithOperators(6);
        _getIntoHaltedState();

        // Only operators[0], [1], [2] reveal; operators[3], [4], [5] do NOT
        uint256[] memory revealers = new uint256[](3);
        revealers[0] = 0;
        revealers[1] = 1;
        revealers[2] = 2;
        _commitAndReveal(revealers);

        _callResume();

        // Verify non-revealers are deactivated
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[3]), 0, "Op3 deactivated");
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[4]), 0, "Op4 deactivated");
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[5]), 0, "Op5 deactivated");

        // New owner should be one of the revealers
        address newOwner = commitReveal2.owner();
        assertTrue(
            newOwner == operators[0] || newOwner == operators[1] || newOwner == operators[2],
            "New owner from revealers"
        );
    }

    /**
     * @notice 4 out of 7 operators didn't reveal — more severe case.
     *
     * Forward iteration would fail even earlier:
     *   - After 3 deactivations, array length is 4 but loop tries index 4,5,6
     *
     * After fix: 7 - 4 - 1(leader) = 2 operators remain.
     */
    function test_resume_multipleDeactivations_4of7() public {
        _setupWithOperators(7);
        _getIntoHaltedState();

        // Only operators[0], [1], [2] reveal; [3..6] do NOT
        uint256[] memory revealers = new uint256[](3);
        revealers[0] = 0;
        revealers[1] = 1;
        revealers[2] = 2;
        _commitAndReveal(revealers);

        _callResume();

        // Verify all non-revealers deactivated
        for (uint256 i = 3; i < 7; i++) {
            assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[i]), 0);
        }
    }

    /**
     * @notice All operators reveal — no deactivations needed (happy path).
     */
    function test_resume_allRevealed_noDeactivations() public {
        _setupWithOperators(5);
        _getIntoHaltedState();

        uint256[] memory revealers = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            revealers[i] = i;
        }
        _commitAndReveal(revealers);

        _callResume();

        // New owner is one of the operators
        address newOwner = commitReveal2.owner();
        bool isOp = false;
        for (uint256 i = 0; i < 5; i++) {
            if (newOwner == operators[i]) {
                isOp = true;
                break;
            }
        }
        assertTrue(isOp, "New owner from operators");
    }

    /**
     * @notice Only 1 operator didn't reveal — minimal deactivation.
     * 5 operators - 1 non-revealer - 1 leader = 3 remain.
     */
    function test_resume_oneNonRevealer() public {
        _setupWithOperators(5);
        _getIntoHaltedState();

        // operators[0..3] reveal, operator[4] does NOT
        uint256[] memory revealers = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            revealers[i] = i;
        }
        _commitAndReveal(revealers);

        _callResume();

        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[4]), 0, "Op4 deactivated");
    }

    /**
     * @notice First operators in array didn't reveal.
     *
     * operators[0], [1] do NOT reveal; [2..5] DO reveal.
     * 6 - 2 - 1(leader) = 3 remain.
     *
     * This tests the backward iteration when early indices are removed
     * (with forward iteration, the swap-and-pop would move later operators
     * into early positions, corrupting the index-reveal mapping).
     */
    function test_resume_firstOperatorsDidNotReveal() public {
        _setupWithOperators(6);
        _getIntoHaltedState();

        // operators[2..5] reveal; [0],[1] do NOT
        uint256[] memory revealers = new uint256[](4);
        revealers[0] = 2;
        revealers[1] = 3;
        revealers[2] = 4;
        revealers[3] = 5;
        _commitAndReveal(revealers);

        _callResume();

        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[0]), 0, "Op0 deactivated");
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[1]), 0, "Op1 deactivated");

        address newOwner = commitReveal2.owner();
        assertTrue(
            newOwner == operators[2] || newOwner == operators[3]
                || newOwner == operators[4] || newOwner == operators[5],
            "New owner from revealers"
        );
    }

    /**
     * @notice Alternating pattern: operators at even indices don't reveal.
     *
     * 7 operators. [0], [2], [4], [6] do NOT reveal (4 non-revealers).
     * [1], [3], [5] DO reveal.
     * 7 - 4 - 1(leader) = 2 remain.
     *
     * This is the worst case for forward iteration: scattered deactivations
     * cause maximum index corruption.
     */
    function test_resume_alternatingNonRevealers() public {
        _setupWithOperators(7);
        _getIntoHaltedState();

        // Only operators[1], [3], [5] reveal
        uint256[] memory revealers = new uint256[](3);
        revealers[0] = 1;
        revealers[1] = 3;
        revealers[2] = 5;
        _commitAndReveal(revealers);

        _callResume();

        // Even-indexed operators deactivated
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[0]), 0, "Op0 deactivated");
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[2]), 0, "Op2 deactivated");
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[4]), 0, "Op4 deactivated");
        assertEq(commitReveal2.s_activatedOperatorIndex1Based(operators[6]), 0, "Op6 deactivated");

        address newOwner = commitReveal2.owner();
        assertTrue(
            newOwner == operators[1] || newOwner == operators[3] || newOwner == operators[5],
            "New owner from revealers"
        );
    }

    /**
     * @notice Stress test with maximum operators (32), half don't reveal.
     *
     * 32 operators. 16 don't reveal. 32 - 16 - 1(leader) = 15 remain.
     * With forward iteration this would be completely broken.
     */
    function test_resume_largeScale_halfDidNotReveal() public {
        _setupWithOperators(32);
        _getIntoHaltedState();

        // Even-indexed operators reveal (16 out of 32)
        uint256[] memory revealers = new uint256[](16);
        for (uint256 i = 0; i < 16; i++) {
            revealers[i] = i * 2; // 0, 2, 4, 6, ..., 30
        }
        _commitAndReveal(revealers);

        _callResume();

        // Odd-indexed operators should be deactivated
        for (uint256 i = 0; i < 16; i++) {
            assertEq(
                commitReveal2.s_activatedOperatorIndex1Based(operators[i * 2 + 1]),
                0,
                "Odd operator should be deactivated"
            );
        }
    }
}
