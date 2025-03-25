// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title CommitReveal2
/// @author
///   - Justin (Euisin) Gee <Tokamak Network>
/// @notice This contract provides on-chain commit-reveal logic built for Tokamak Network.
/// @dev Implements a multi-phase commit-reveal flow and integrates with the following:
///   - EIP712 for typed data hashing
///   - Optimism L1 Fees for fee calculation on Optimism based L2
///   - OperatorManager for managing operator deposits and slash mechanics
/// @custom:company Tokamak Network
interface CommitReveal2ForDocs {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error ActivatedOperatorsLimitReached();
    error AlreadyActivated();
    error AlreadyInitialized();
    error AlreadyRefunded();
    error AlreadyRequestedToSubmitCv();
    error AlreadySubmittedMerkleRoot();
    error AlreadySubmittedS();
    error CoNotRequested();
    error CvNotRequested();
    error CvNotSubmitted(uint256 index);
    error ETHTransferFailed();
    error ExceedCallbackGasLimit();
    error InProcess();
    error InsufficientAmount();
    error InvalidCo();
    error InvalidL1FeeCoefficient(uint8 coefficient);
    error InvalidRevealOrder();
    error InvalidRound();
    error InvalidS();
    error InvalidSecretLength();
    error InvalidShortString();
    error InvalidSignature();
    error InvalidSignatureLength();
    error InvalidSignatureS();
    error LeaderLowDeposit();
    error LessThanActivationThreshold();
    error MerkleRootNotSubmitted();
    error MerkleVerificationFailed();
    error NewOwnerIsZeroAddress();
    error NoHandoverRequest();
    error NotActivatedOperator();
    error NotConsumer();
    error NotEnoughActivatedOperators();
    error NotHalted();
    error OnlyActivatedOperatorCanClaim();
    error OperatorNotActivated();
    error OwnerCannotActivate();
    error RevealNotInDescendingOrder();
    error SNotRequested();
    error ShouldNotBeZero();
    error StringTooLong(string str);
    error TooEarly();
    error TooLate();
    error TransferFailed();
    error Unauthorized();
    error ZeroLength();

    event Activated(address operator);
    event CoSubmitted(uint256 timestamp, bytes32 co, uint256 index);
    event CvSubmitted(uint256 timestamp, bytes32 cv, uint256 index);
    event DeActivated(address operator);
    event EIP712DomainChanged();
    event IsInProcess(uint256 isInProcess);
    event L1FeeCalculationSet(uint8 coefficient);
    event MerkleRootSubmitted(uint256 timestamp, bytes32 merkleRoot);
    event OwnershipHandoverCanceled(address indexed pendingOwner);
    event OwnershipHandoverRequested(address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess);
    event RandomNumberRequested(uint256 round, uint256 timestamp);
    event RequestedToSubmitCo(uint256 timestamp, uint256[] indices);
    event RequestedToSubmitCv(uint256 timestamp, uint256[] indices);
    event RequestedToSubmitSFromIndexK(uint256 timestamp, uint256 index);
    event SSubmitted(uint256 timestamp, bytes32 s, uint256 index);

    /**
     * @notice Activates an operator, allowing them to participate in the protocol (e.g., commit/reveal^2 phases).
     * @dev
     *   - Must not be called while `s_isInProcess == IN_PROGRESS` (protected by {notInProcess}).
     *   - The owner (leader node) cannot activate as an operator (reverts with {OwnerCannotActivate}).
     *   - Requires the caller to have a deposit (`s_depositAmount[msg.sender]`) >= `s_activationThreshold`.
     *   - Ensures the operator is not already active (`s_activatedOperatorIndex1Based[msg.sender] == 0`).
     *   - Adds the operator’s address to `s_activatedOperators` and sets their 1-based index.
     *   - Enforces `s_activatedOperators.length <= s_maxActivatedOperators`.
     *   - Initializes the operator’s slash reward offset with `s_slashRewardPerOperatorPaid[msg.sender] = s_slashRewardPerOperator`.
     *   - Emits {Activated} upon success.
     */
    function activate() external;
    function cancelOwnershipHandover() external payable;

    /**
     * @notice Allows an already-activated operator to claim any slash reward accrued so far.
     * @dev
     *   - Requires the caller to be an active operator (reverts with {OnlyActivatedOperatorCanClaim} if not).
     *   - Calculates the operator’s unclaimed slash reward by taking the difference
     *     `s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender]`.
     *   - Resets `s_slashRewardPerOperatorPaid[msg.sender]` to the current global slash reward level
     *     so the operator cannot claim the same reward again.
     *   - Transfers the computed amount of ETH to the caller via a low-level `call`.
     *     If the transfer fails, reverts with {TransferFailed}.
     */
    function claimSlashReward() external;
    function completeOwnershipHandover(address pendingOwner) external payable;

    /**
     * @notice Allows an operator to voluntarily deactivate (leave) the system, provided it is not in process.
     * @dev
     *   - Protected by {notInProcess}, ensuring no active round is in progress.
     *   - Looks up the caller's 1-based index in `s_activatedOperators`, then calls {_deactivate(...)}.
     *   - Once deactivated, the operator can choose to withdraw their deposit (and slash rewards) by calling {withdraw()}.
     */
    function deactivate() external;

    /**
     * @notice Allows any address (owner or operator) to deposit ETH into their own account balance.
     * @dev
     *   - Increments `s_depositAmount[msg.sender]` by `msg.value`.
     *   - For operators to reach `s_activationThreshold`.
     *   - The deposited amount may later be withdrawn if the operator deactivates or if the owner so chooses.
     */
    function deposit() external payable;

    /**
     * @notice A convenience function to both deposit ETH and immediately activate as an operator in one call.
     * @dev
     *   - Simply calls {deposit()} to increase the caller’s `s_depositAmount[msg.sender]`,
     *     then calls {activate()} to attempt activation.
     *   - If the deposit plus any existing balance is >= `s_activationThreshold`,
     *     and there is still room under `s_maxActivatedOperators`, the caller becomes an active operator.
     */
    function depositAndActivate() external payable;
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    /**
     * @notice Estimates the fee required to request a random number based on a chosen gas price
     *         and callback gas limit, allowing you to specify a custom number of operators.
     * @dev This variant is useful for “what if” scenarios (e.g. simulating additional
     *      operators in the future). As the operator count grows, so does the on-chain submission
     *      overhead and, consequently, the request fee.
     * @param callbackGasLimit The amount of gas required to execute the consumer's callback.
     * @param gasPrice The gas price used to calculate the request fee.
     * @param numOfOperators The assumed number of operators used in the cost calculation.
     * @return estimatedFee The total fee (in wei) required to cover the entire request process, plus the flat fee allocated to reward the operators.
     */
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        external
        view
        returns (uint256);

    /**
     * @notice Estimates the fee required to request a random number based on a chosen gas price
     *         and the specified callback gas limit.
     * @dev The transaction cost for generating the final random number increases proportionally
     *      with the number of activated operators. The fee covers on-chain operations in
     *      a multi-stage process.
     * @param callbackGasLimit The amount of gas required to execute the consumer's callback.
     * @param gasPrice The gas price used to calculate the request fee.
     * @return estimatedFee The total fee (in wei) required to cover the entire request process, plus the flat fee allocated to reward the operators.
     */
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256);

    /**
     * @notice Halts the round if the leader node (owner) fails to request the final secret submissions (S)
     *         or to generate the random number before the required deadline.
     * @dev
     *   1) Ensures that the Merkle root was submitted (`s_isSubmittedMerkleRoot[startTime] == true`). Otherwise,
     *      reverts with {MerkleRootNotSubmitted}.
     *   2) Checks two possible deadlines based on whether there was a `Co` submission request:
     *       - If `s_requestToSubmitCoBitmap[startTime] > 0`, we require:
     *           `block.timestamp >= (s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
     *             + (s_onChainSubmissionPeriodPerOperator * s_activatedOperators.length)
     *             + s_requestOrSubmitOrFailDecisionPeriod)`.
     *       - Otherwise, we require:
     *           `block.timestamp >= (s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
     *             + (s_offChainSubmissionPeriodPerOperator * s_activatedOperators.length)
     *             + s_requestOrSubmitOrFailDecisionPeriod)`.
     *      If neither deadline has passed, reverts with {TooEarly}.
     *   3) Slashes the leader node’s (owner’s) deposit by `s_activationThreshold`, minus a gas fee refund
     *      (`tx.gasprice * FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED`) credited to the caller:
     *      - Deducts from `s_depositAmount[owner]`.
     *      - Adds `returnGasFee` to `s_depositAmount[msg.sender]`.
     *      - Distributes the remainder (`activationThreshold - returnGasFee`) among all activated operators
     *        via an update to `s_slashRewardPerOperator`.
     *   4) Sets {s_isInProcess} to {HALTED} and emits {IsInProcess}(HALTED). This indicates no further
     *      progression for the current round until the leader node resumes the protocol.
     */
    function failToRequestSOrGenerateRandomNumber() external;

    /**
     * @notice Halts the round if the leader (owner) neither requested commits (`Cv`) nor submitted a Merkle root
     *         within the designated off-chain period.
     * @dev
     *   1) Verifies that no on-chain commit submission request was made (`s_cvs[startTime].length == 0`)
     *      and that no Merkle root was submitted (`!s_isSubmittedMerkleRoot[startTime]`).
     *      - If either of these conditions is false, it reverts with {AlreadyRequestedToSubmitCv}
     *        or {AlreadySubmittedMerkleRoot}, respectively.
     *   2) Requires the current time to be at least
     *      `startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`.
     *      - If too early, it reverts with {TooEarly}.
     *   3) Slashes the leader’s deposit by `s_activationThreshold` and refunds the caller’s gas
     *      via `(tx.gasprice * FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED)`.
     *   4) Distributes the slashed remainder among all currently activated operators by increasing
     *      `s_slashRewardPerOperator` and adjusting `s_slashRewardPerOperatorPaid[owner()]`.
     *   5) Sets `s_isInProcess` to `HALTED` and emits an {IsInProcess} event to reflect that no further
     *      progress can be made in this round.
     */
    function failToRequestSubmitCvOrSubmitMerkleRoot() external;

    /**
     * @notice Fails the current round if some operators did not submit their “Co” (Reveal-1) within the on-chain deadline.
     * @dev
     *   1) Ensures the submission window has ended:
     *      `block.timestamp >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod`.
     *      If not, reverts with {TooEarly}.
     *   2) Checks that `s_requestToSubmitCoBitmap[startTime]` is non-zero, indicating Co was requested.
     *      If zero, reverts with {CoNotRequested}.
     *   3) Iterates over each operator in `s_requestedToSubmitCoIndices` to identify those whose bit in
     *      `requestToSubmitCoBitmap` is still set (i.e., they have not submitted).
     *      For each non-submitter:
     *       - Deactivates the operator via `_deactivate()`.
     *       - Updates their deposit by subtracting the `activationThreshold`, then adding in any
     *         previously accrued slash reward (`accumulatedReward`) to ensure correctness.
     *   4) Refunds the caller’s gas cost via `tx.gasprice * FAILTOSUBMITCO_GASUSED`.
     *   5) Updates the global slash reward (`s_slashRewardPerOperator`) to distribute part of the
     *      newly slashed deposit (minus the refunded gas) among the remaining active operators plus
     *      the leader node.
     *   6) If at least two operators remain active, resets the round’s start time to the current
     *      block timestamp and emits {RandomNumberRequested}, effectively “restarting” the round.
     *      Otherwise, sets `s_isInProcess` to {HALTED} and emits {IsInProcess}(HALTED).
     */
    function failToSubmitCo() external;

    /**
     * @notice Fails the current round if some operators did not submit their required on-chain commitments (`Cv`)
     *         within the allowed on-chain submission period.
     * @dev
     *   1) Checks if `Cv` submission was requested:
     *      - If no `Cv` array exists (`s_cvsArray.length == 0`), reverts with `CvNotRequested()`.
     *      - Ensures we are past the submission deadline (`block.timestamp >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod`).
     *   2) Iterates over all requested operator indices, identifies those which did not submit (their slot in `s_cvs[startTime]` is still zero).
     *   3) For each non-submitter:
     *       - Deactivates the operator and slashes their deposit by `s_activationThreshold`.
     *       - Credits the difference in slash rewards (`accumulatedReward`) to their deposit to avoid double slashing.
     *   4) Returns a gas fee to `msg.sender` for calling the function.
     *      - This is computed as `tx.gasprice * FAILTOSUBMITCV_GASUSED`.
     *   5) Updates the global `s_slashRewardPerOperator` value by distributing part of the slashed amount, minus the refunded gas fee,
     *      among remaining active operators plus the leader node (owner).
     *   6) If at least 2 operators remain active, the round is “restarted” by resetting its startTime to the current block.timestamp
     *      and re-emitting {RandomNumberRequested}.
     *      Otherwise, the contract transitions to `HALTED` state (no further progression is possible), and emits {IsInProcess}(HALTED).
     */
    function failToSubmitCv() external;

    /**
     * @notice Halts the round if the leader (owner) fails to submit the Merkle root after a dispute
     *         within the required on-chain submission period.
     * @dev
     *  1) Checks we are past the on-chain submission period for disputes:
     *     `s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`.
     *     Otherwise reverts with {TooEarly}.
     *  2) Requires that there was indeed a commit phase (`s_cvs[startTime].length > 0`) and that
     *     no Merkle root was submitted (`!s_isSubmittedMerkleRoot[startTime]`).
     *  3) Slashes the leader’s deposit by `s_activationThreshold`, refunds the caller’s gas,
     *     and distributes the remainder as an update to `s_slashRewardPerOperator`.
     *  4) Sets {s_isInProcess} to {HALTED}—signifying the leader node is effectively “down” in this
     *     protocol round—which blocks further progression of this round.
     *     Later, the leader node can call a resume function to reinitiate the protocol, if desired.
     *  5) Emits {IsInProcess}(HALTED).
     */
    function failToSubmitMerkleRootAfterDispute() external;

    /**
     * @notice Fails the current round if an operator fails to submit its final secret (`S`) by the on-chain deadline.
     * @dev
     *   1) Checks whether `S` submission was requested (`s_ss[startTime]` must be allocated).
     *      If not, reverts with {SNotRequested}.
     *   2) Ensures the on-chain submission window has passed:
     *      `block.timestamp >= s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator`.
     *      If not, reverts with {TooEarly}.
     *   3) Credits a gas refund to `msg.sender`: `tx.gasprice * FAILTOSUBMITS_GASUSED`.
     *   4) Identifies the operator who was supposed to submit next
     *      (`s_revealOrders[s_requestedToSubmitSFromIndexK]`) and slashes his deposit by
     *      `s_activationThreshold`, minus any previously accrued slash reward, then deactivates them.
     *   5) Updates the global slash reward (`s_slashRewardPerOperator`) to distribute the slashed amount,
     *      minus the refunded gas, among the remaining active operators plus the leader node.
     *   6) If more than one operator remains, resets the round’s `startTime` to `block.timestamp`
     *      and emits {RandomNumberRequested} to retry this round. Otherwise, sets {s_isInProcess} to {HALTED}
     *      and emits {IsInProcess}(HALTED).
     */
    function failToSubmitS() external;

    /**
     * @notice Finalizes the random number generation by using all the operators’ secrets.
     * @dev
     *  1) Ensures there are enough secrets to cover the number of activated operators.
     *     If `secrets.length < activatedOperatorsLength`, the call reverts with `InvalidSecretLength()`.
     *  2) Enforces a deadline check, ensuring the function is called prior to either of two possible
     *     expiry times:
     *       a) `s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod + (s_offChainSubmissionPeriodPerOperator * activatedOperatorsLength) + s_requestOrSubmitOrFailDecisionPeriod`
     *       b) `s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod + (s_offChainSubmissionPeriodPerOperator * activatedOperatorsLength) + s_requestOrSubmitOrFailDecisionPeriod`
     *     If both have elapsed, reverts with `TooLate()`.
     *  3) construct arrays:
     *       - `cos[i] = keccak256(secrets[i])`
     *       - `cvs[i] = keccak256(cos[i])`
     *  4) Verifies that `cvs` follow the provided reveal ordering (`revealOrders`) in **descending** order
     *     by comparing `diff(rv, cvs[revealOrders[i]])`, where `rv = keccak256(concatenate(cos))`.
     *     If any entry is out of order, reverts with `RevealNotInDescendingOrder()`.
     *  5) Builds a Merkle tree of `cvs` to confirm the computed root matches `s_merkleRoot`.
     *     If mismatched, reverts with `MerkleVerificationFailed()`.
     *  6) Checks each operator’s signature to guarantee the authenticity of their `cv`.
     *     If a signature is malleable or from an unactivated operator, it reverts.
     *  7) Aggregates `secrets` to produce the final random number (`randomNumber`).
     *  8) Moves on to the next round if it exists; otherwise marks `s_isInProcess` as `COMPLETED`.
     *  9) Adds the entire request cost (`requestInfo.cost`) to the deposit of the “last revealer”
     * 10) Emits a {RandomNumberGenerated} event and executes the consumer’s callback.
     *
     * @param secrets The individual secrets from each operator, used to derive the final randomness.
     * @param vs The `v` components of each operator’s ECDSA signature.
     * @param rs The `r` components of each operator’s ECDSA signature.
     * @param ss The `s` components of each operator’s ECDSA signature.
     * @param revealOrders The specified index ordering for `cvs` in descending difference from `rv`.
     *                     This enforces a particular reveal sequence on-chain.
     */
    function generateRandomNumber(
        bytes32[] memory secrets,
        uint8[] memory vs,
        bytes32[] memory rs,
        bytes32[] memory ss,
        uint256[] memory revealOrders
    ) external;

    /**
     * @notice Returns the array of currently activated operators.
     * @return An array of operator addresses, each of whom has called `activate()` and not yet been deactivated.
     */
    function getActivatedOperators() external view returns (address[] memory);

    /**
     * @notice Returns the current length of the `s_activatedOperators` array.
     * @dev Equivalent to `s_activatedOperators.length`.
     * @return The number of currently activated operators.
     */
    function getActivatedOperatorsLength() external view returns (uint256);

    /**
     * @notice Computes the total balance of `operator`, including any unclaimed slash rewards, if they are active or the owner.
     * @dev
     *   - If `operator` is not the owner and not currently active, returns only `s_depositAmount[operator]`.
     *   - Otherwise, returns the sum of `s_depositAmount[operator]` plus
     *     `(s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator])`.
     *   - Useful for testing the operator’s effective total.
     * @param operator The address to query.
     * @return The deposit plus unclaimed slash rewards of the `operator`.
     */
    function getDepositPlusSlashReward(address operator) external view returns (uint256);

    /**
     * @notice Computes the EIP-712 typed data hash of a `(timestamp, cv)` pair.
     * @dev Simply wraps `_hashTypedDataV4` with the given parameters to produce the final digest used for operator signatures.
     * @param timestamp The timestamp included in the typed data struct.
     * @param cv The commitment value (Cv) tied to this timestamp.
     * @return The resulting EIP-712 hash digest.
     */
    function getMessageHash(uint256 timestamp, bytes32 cv) external view returns (bytes32);
    function owner() external view returns (address result);
    function ownershipHandoverExpiresAt(address pendingOwner) external view returns (uint256 result);

    /**
     * @notice Allows the consumer to reclaim the cost of a specific round if it has not
     *         been fulfilled (i.e., no random number has been generated) and the system
     *         is not currently in process (`notInProcess`).
     * @dev
     *   1) Validates the `round` identifier: must be less than `s_requestCount` and greater
     *      or equal to `s_currentRound`. If out of range, reverts with {InvalidRound}.
     *   2) Ensures the caller is the same consumer who initiated that round’s request.
     *   3) Clears the request’s cost (setting it to 0) and flips its bitmap bit from 1 to 0,
     *      indicating it is no longer an active request.
     *   4) Issues an ETH refund for the previously paid cost.
     *      - If the transfer fails, reverts with `ETHTransferFailed()`.
     *
     * @param round The round ID whose cost is to be refunded.
     */
    function refund(uint256 round) external;
    function renounceOwnership() external payable;
    function requestOwnershipHandover() external payable;

    /**
     * @notice Requests a new random number from this contract.
     * @dev
     *    1) Enforces the following requirements:
     *       - `callbackGasLimit` <= `MAX_CALLBACK_GAS_LIMIT`.
     *       - There must be more than one activated operator.
     *       - The leader (owner) must have a deposit >= `s_activationThreshold`.
     *       - `msg.value` >= fee returned by `_calculateRequestPrice()`.
     *    2) Increments the request count to create a new round ID (`newRound`) and flips the bit
     *       in `s_roundBitmap` to mark the round as requested.
     *    3) If no round is currently in progress (`s_isInProcess == COMPLETED`), this request
     *       immediately starts a new round, sets `s_isInProcess = IN_PROGRESS`, and records
     *       the `startTime` as the current block timestamp. Emits {IsInProcess} with the `IN_PROGRESS` status.
     *    4) Otherwise, if a round is in progress, the newly requested round remains queued
     *       (with a `startTime` of 0) until the active round is completed or halted.
     *    5) Stores the request details (caller’s address, cost paid, callback gas limit, and start time)
     *       in `s_requestInfo[newRound]`.
     *    6) Emits {RandomNumberRequested} with the new round ID, its `startTime`, and the list
     *       of currently activated operators.
     *
     * @param callbackGasLimit The gas limit for executing the eventual consumer callback.
     * @return newRound The ID of the newly requested round.
     */
    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256 newRound);

    /**
     * @notice Requests on-chain submission of “Co” values (Reveal-1) from a subset of operators
     *         after the Merkle root has been submitted.
     * @dev
     *   1) Restricted to the contract owner.
     *   2) Requires `s_isSubmittedMerkleRoot[startTime] == true`, indicating the Merkle root for this round was submitted.
     *   3) Must be called before the deadline:
     *      `s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`.
     *   4) If `s_cvsArray` for this round is empty (meaning there was no request to submit Cv on-chain),
     *      a new array is initialized to accommodate all activated operators.
     *   5) Conceptually splits the `indices` array into two groups:
     *       - `indices[0..cvs.length - 1]`: Operators who previously did not submit `Cv` on-chain
     *         (they submitted it off-chain and were not requested on-chain). These now need to submit `Cv` on-chain,
     *         which is validated via ECDSA signatures.
     *       - `indices[cvs.length..end]`: Operators who have already submitted a `Cv` on-chain
     *         (via `submitCv()`). Here, we only check that their existing `Cv` is non-zero
     *         (this behavior may change in future updates).
     *   6) Constructs a bitmask, `requestToSubmitCoBitmap`, for the operators who must provide “Co”.
     *   7) Validates each ECDSA signature from operators in the first group to ensure:
     *      - Non-malleable `s` component (`s <= 0x7F...B20A0`).
     *      - The recovered signer’s index matches `index + 1`.
     *   8) Updates `s_cvsArray[index] = cv` for these first-group operators to store their newly submitted on-chain commitments.
     *   9) Records request metadata (including the bitmask) in `s_requestToSubmitCoBitmap[startTime]`
     *      and sets `s_requestedToSubmitCoTimestamp` to the current block time.
     *   10) Emits {RequestedToSubmitCo}, logging the round’s `startTime` and all operator indices involved.
     *
     * @param indices The operator indices (in `s_activatedOperators`) required to submit Co values.
     *                The first `cvs.length` elements refer to operators who have not submitted on-chain `Cv`,
     *                while the remaining elements refer to those who already submitted `Cv` on-chain.
     * @param cvs The Co commitments for operators in the first group (i.e., `indices[0..cvs.length - 1]`).
     * @param vs The `v` parts of each ECDSA signature, only for `indices[0..cvs.length - 1]`.
     * @param rs The `r` parts of each signature, only for `indices[0..cvs.length - 1]`.
     * @param ss The `s` parts of each signature, only for `indices[0..cvs.length - 1]`.
     */
    function requestToSubmitCo(
        uint256[] memory indices,
        bytes32[] memory cvs,
        uint8[] memory vs,
        bytes32[] memory rs,
        bytes32[] memory ss
    ) external;

    /**
     * @notice Requests on-chain submissions of commitments (`Cv`) from a subset of operators.
     * @dev
     *  1) Restricted to the contract owner (leader node).
     *  2) Enforces a non-empty `indices` array (reverts with `ZeroLength()` otherwise).
     *  3) Must be called before the deadline: `startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`.
     *     If the current block time exceeds that, reverts with `TooLate()`.
     *  4) Initializes a new array in `s_cvs[startTime]` with size equal to the total number of activated operators.
     *  5) Records which operator indices are requested to submit and the timestamp of the request.
     *  6) Emits a {RequestedToSubmitCv} event containing the round’s `startTime` and the requested operator indices.
     *
     * @param indices The indices of the operators (in `s_activatedOperators`) who are required to submit `Cv`.
     */
    function requestToSubmitCv(uint256[] memory indices) external;

    /**
     * @notice Requests an on-chain reveal phase (`S`) for operators who failed to provide their secrets off-chain,
     *         while simultaneously uploading the off-chain secrets that the leader node already possesses.
     * @dev
     *  1) Two subsets of operators exist according to `revealOrders`:
     *       - Group A: The first `k` operators in `revealOrders` (indices `[0..k-1]`), whose secrets the leader node
     *         successfully received off-chain. These are immediately uploaded via the `secrets` array.
     *       - Group B: The remaining operators (`[k..end]` in `revealOrders`), who must later submit secrets on-chain
     *         themselves (e.g., via `submitS()`), because the leader node did not get their secrets off-chain.
     *    Here, `k = secrets.length`.
     *
     *  2) Must be called before one of the following deadlines:
     *       (a) `s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
     *           + (s_offChainSubmissionPeriodPerOperator * operatorsLength)
     *           + s_requestOrSubmitOrFailDecisionPeriod`, or
     *       (b) `s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
     *           + (s_offChainSubmissionPeriodPerOperator * operatorsLength)
     *           + s_requestOrSubmitOrFailDecisionPeriod`.
     *
     *  3) Allocates `s_cvs[startTime]` (if empty) to store each operator’s commitment (`cv`), and
     *     `s_ss[startTime]` to store the final secrets on-chain.
     *
     *  4) The `cos` array (Reveal-1 values) is indexed in ascending activated operator order (`cos[0]` -> operator 0, etc.).
     *     We process it in reverse operator index internally to align with the descending order of `signatures`.
     *     - If an operator’s `Cv` was never placed on-chain, we validate it now using an ECDSA signature from
     *       `signatures` (sorted in descending operator index). Each signature must:
     *         * pass the malleability check (`s <= 0x7F...`),
     *         * recover the correct operator index + 1.
     *     - If the operator’s `Cv` is known on-chain, we simply verify it matches.
     *
     *  5) We build a “distance” array from `rv = keccak256(abi.encodePacked(cos))` and Cvi. The array `revealOrders`
     *     must list operator indices in strictly descending distance from `rv`; otherwise reverts
     *     with {RevealNotInDescendingOrder}.
     *
     *  6) Of the operators in `revealOrders`, the first `k = secrets.length` operators are Group A
     *     (with secrets in `secrets`). For each, we verify `_efficientTwoKeccak256(secret) == cv`
     *     and store it in `s_ss[startTime]`. The remaining operators (`[k..end]`) are Group B,
     *     who will reveal on-chain later in submitS() function.
     *
     *  7) Sets `s_requestedToSubmitSFromIndexK = secrets.length` and emits {RequestedToSubmitSFromIndexK},
     *     signifying how many secrets from Group A were just uploaded. Group B can individually call
     *     on-chain submissions (like `submitS()`) to finalize their secrets in reveal order.
     *
     *  8) Updates `s_previousSSubmitTimestamp`, denoting the start time of this final S-submission phase.
     *
     * @param cos          The Reveal-1 array in ascending activated operator index order (`cos[i]` corresponds
     *                     to operator i). Used to compute both `rv` (via `keccak256`) and each
     *                     operator’s commitment (`cv`).
     * @param secrets      The off-chain secrets for Group A operators, who submitted their secrets off-chain properly, provided by the leader node. Must be
     *                     arranged in the same order as `revealOrders`. In other words, `secrets[i]` is
     *                     the secret for `revealOrders[i]`.
     * @param signatures   ECDSA signatures in descending operator index order, required only for operators
     *                     who have not placed a `cv` on-chain. (Some operators may have already submitted their Cv on-chain in submitCv() and submitCo() functions.)
     * @param revealOrders The operator indices in a strictly descending distance from each `Cvi` relative to `rv`.
     *                     The first `k` elements (where `k = secrets.length`) belong to Group A, whose secrets
     *                     are uploaded here. The remaining elements denote Group B, who will later submit
     *                     secrets on-chain.
     */
    function requestToSubmitS(
        bytes32[] memory cos,
        bytes32[] memory secrets,
        Signature[] memory signatures,
        uint256[] memory revealOrders
    ) external;

    /**
     * @notice Resumes the protocol if it is currently halted, typically due to
     *         an unresolved leader node failure. This allows the leader node to
     *         inject new deposits if necessary and activate a pending or next
     *         requested round.
     * @dev
     *   1) Restricted to the contract owner. Must be called when `s_isInProcess == HALTED`.
     *   2) Requires at least two activated operators (`s_activatedOperators.length > 1`).
     *   3) The owner can optionally send ETH to replenish its deposit (`s_depositAmount[owner()]`),
     *      which must remain >= `s_activationThreshold`.
     *   4) Scans for up to 10 times through the bitmap of requested rounds, seeking the
     *      next available requested round:
     *        - If found, that round is started by setting `s_currentRound` to it,
     *          updating the start time to `block.timestamp`, and marking the system as `IN_PROGRESS`.
     *          Emits {IsInProcess}(IN_PROGRESS) and re-emits {RandomNumberRequested}.
     *        - If none are found by the time we exceed `requestCountMinusOne`, we mark
     *          the system as `COMPLETED` and set `s_currentRound` to the last round index.
     *          Emits {IsInProcess}(COMPLETED).
     *   5) If the loop ends early with a found round, the function returns immediately.
     *
     * A resume operation effectively indicates the leader node is back online and
     * ready to continue serving random number requests.
     */
    function resume() external payable;

    /**
     * @notice Maps each operator to an index (1-based) in the `s_activatedOperators` array.
     * @dev
     *   - `0` means the operator is not active.
     *   - A non-zero value indicates the position of the operator in `s_activatedOperators`.
     *   - This index is 1-based, so subtract 1 when accessing the array.
     */
    function s_activatedOperatorIndex1Based(address operator) external view returns (uint256);

    /**
     * @notice The minimum amount of ETH an operator (other than the leader) must deposit to become active.
     * @dev Operators must have `>= s_activationThreshold` in `s_depositAmount[operator]` to call `activate()`.
     */
    function s_activationThreshold() external view returns (uint256);
    function s_currentRound() external view returns (uint256);
    function s_cvs(uint256 timestamp, uint256) external view returns (bytes32);

    /**
     * @notice Tracks each operator’s current deposit balance, including any ETH they have deposited or earned.
     *         The deposit can be used to meet `s_activationThreshold` or to pay slashing penalties.
     * @dev Keys are operator addresses, values are deposit amounts in wei.
     */
    function s_depositAmount(address operator) external view returns (uint256);
    function s_flatFee() external view returns (uint256);
    function s_isInProcess() external view returns (uint256);
    function s_isSubmittedMerkleRoot(uint256 timestamp) external view returns (bool);
    function s_l1FeeCoefficient() external view returns (uint8);

    /**
     * @notice The maximum number of operators that can be simultaneously active.
     * @dev Enforced when an operator calls `activate()`, ensuring `s_activatedOperators.length <= s_maxActivatedOperators`.
     */
    function s_maxActivatedOperators() external view returns (uint256);
    function s_merkleRoot() external view returns (bytes32);
    function s_merkleRootSubmittedTimestamp() external view returns (uint256);
    function s_previousSSubmitTimestamp() external view returns (uint256);
    function s_requestCount() external view returns (uint256);
    function s_requestInfo(uint256 round)
        external
        view
        returns (address consumer, uint256 startTime, uint256 cost, uint256 callbackGasLimit);
    function s_requestToSubmitCoBitmap(uint256 timestamp) external view returns (uint256);
    function s_requestedToSubmitCoIndices(uint256) external view returns (uint256);
    function s_requestedToSubmitCoTimestamp() external view returns (uint256);
    function s_requestedToSubmitCvIndices(uint256) external view returns (uint256);
    function s_requestedToSubmitCvTimestamp() external view returns (uint256);
    function s_requestedToSubmitSFromIndexK() external view returns (uint256);
    function s_revealOrders(uint256) external view returns (uint256);
    function s_roundBitmap(uint248 wordPos) external view returns (uint256);

    /**
     * @notice Records how much slash reward is allocated per operator at the global level.
     * @dev
     *   - Each time an operator is slashed, a portion of its deposit is distributed to
     *     other operators (and the leader node if included).
     *   - `s_slashRewardPerOperatorPaid[operator]` tracks how much of this total an operator has already claimed.
     */
    function s_slashRewardPerOperator() external view returns (uint256);

    /**
     * @notice Maps an operator to the amount of global slash reward they have already received.
     * @dev
     *   - This prevents double-counting of slash rewards when an operator withdraws or claims.
     *   - If `s_slashRewardPerOperator` is increased, each operator can claim the difference
     *     between the new global reward and what they have already been paid.
     */
    function s_slashRewardPerOperatorPaid(address) external view returns (uint256);
    function s_ss(uint256 timestamp, uint256) external view returns (bytes32);
    function setL1FeeCoefficient(uint8 coefficient) external;

    /**
     * @notice Allows an activated operator to submit its “Co” (Reveal-1) on-chain within the specified submission period.
     * @dev
     *   1) Checks that the current time is before the deadline: `s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod`.
     *      If missed, reverts with {TooLate}.
     *   2) Looks up the caller’s operator index. They must have been requested to submit Co (Reveal-1).
     *   3) Verifies that `s_cvs[startTime][activatedOperatorIndex]` matches `keccak256(abi.encodePacked(co))`.
     *      If not, reverts with {InvalidCo}.
     *   4) Clears the corresponding bit in `s_requestToSubmitCoBitmap[startTime]` to indicate the operator has submitted.
     *   5) Emits {CoSubmitted}, providing the round’s `startTime`, the submitted Co, and the operator’s index.
     *
     * @param co The Reveal-1 value (Co) from this operator, whose keccak-hash must match the existing on-chain Cv.
     */
    function submitCo(bytes32 co) external;

    /**
     * @notice Submits an on-chain commitment (`Cv`) for the current round, as requested by the owner.
     * @dev
     *  1) Must be called before the deadline: `s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod`.
     *     If this deadline is exceeded, reverts with `TooLate()`.
     *  2) Identifies the caller’s operator index (`activatedOperatorIndex`) and records the submitted commitment
     *     into `s_cvs[startTime][activatedOperatorIndex]`.
     *  3) Emits a {CvSubmitted} event which includes the `startTime`, the submitted commitment, and the operator’s index.
     *
     * The caller’s need to be an activated operator
     * with an assigned index (`s_activatedOperatorIndex1Based[msg.sender]`).
     *
     * @param cv The operator’s commitment (commonly a hashed value) to be stored on-chain.
     */
    function submitCv(bytes32 cv) external;

    /**
     * @notice Submits the Merkle root on-chain for the current round.
     * @dev
     *  1) This action is restricted to the contract owner (leader node).
     *  2) Must occur before the deadline: `startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`.
     *     - If the deadline is passed, it reverts with `TooLate()`.
     *  3) The submitted Merkle root is recorded in `s_merkleRoot` and flagged as submitted by
     *     setting `s_isSubmittedMerkleRoot[startTime] = true`.
     *  4) Emits a {MerkleRootSubmitted} event with the `startTime` of the request and the newly
     *     submitted Merkle root.
     *
     * @param merkleRoot The Merkle root which aggregates all required commitments (e.g. hashed operator data).
     */
    function submitMerkleRoot(bytes32 merkleRoot) external;

    /**
     * @notice Submits the Merkle root after a commit phase dispute has occurred.
     * @dev
     *  1) Restricted to the contract owner.
     *  2) Must be called before the dispute resolution deadline:
     *     `s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`.
     *     Otherwise, reverts with {TooLate}.
     *  3) Records the Merkle root in `s_merkleRoot`, updates the submission timestamp, and flags
     *     the round's `startTime` as having a submitted Merkle root.
     *  4) Emits {MerkleRootSubmitted}.
     *
     * @param merkleRoot The Merkle root computed from committed values after dispute resolution.
     */
    function submitMerkleRootAfterDispute(bytes32 merkleRoot) external;

    /**
     * @notice Finalizes an operator’s second reveal (S) on-chain for the current round.
     * @dev
     *   - Must be called by an activated operator within the per-operator submission window:
     *     `block.timestamp < s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator`.
     *   - Checks that the submitted secret matches the on-chain commitment (`Cv`) via `_efficientTwoKeccak256(s)`.
     *   - Requires this operator to be next in the predetermined reveal order (`s_revealOrders`),
     *     otherwise reverts with {InvalidRevealOrder}.
     *   - If this operator is the final one in the reveal order, the contract:
     *       1) Computes the random number for the current round (hashing all revealed secrets).
     *       2) Rewards this last revealer with the entire request cost.
     *       3) Proceeds to either the next round (if any remain) or marks the contract as {COMPLETED}.
     *       4) Invokes the consumer’s callback function with the generated random number.
     *
     * @param s The final secret reveal (S) from the operator, which must:
     *          1) Match the on-chain `Cv` for this operator (double-hash check).
     *          2) Align with the reveal order: the contract verifies this operator is the next index
     *             in `s_revealOrders`. If they are last, the random number is finalized.
     */
    function submitS(bytes32 s) external;
    function transferOwnership(address newOwner) external payable;

    /**
     * @notice Allows an operator or the owner to withdraw their total deposit (and slash rewards)
     *         when not currently in process.
     * @dev
     *   - Protected by {notInProcess}, so no active round can be ongoing.
     *   - If the caller is an activated operator:
     *       1) The caller is first deactivated by calling {_deactivate(...)}.
     *       2) Their withdrawable amount includes their `s_depositAmount[msg.sender]` plus any unclaimed
     *          slash rewards (`s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender]`).
     *   - If the caller is the owner (leader node), not an operator, they can still withdraw
     *     their deposit plus any accrued slash reward.
     *   - Otherwise, if the caller is neither the owner nor an active operator, they just withdraw
     *     their deposit without any slash reward.
     *   - Resets the caller’s deposit to `0` and transfers the calculated `amount` via low-level `call()`.
     *     If the call fails, reverts with `ETHTransferFailed()`.
     *   - Updates `s_slashRewardPerOperatorPaid[msg.sender]` to the current global slash reward
     *     to prevent re-claiming the same reward.
     */
    function withdraw() external;
}
