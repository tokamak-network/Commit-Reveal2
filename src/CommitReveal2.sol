// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {CommitReveal2Storage} from "./CommitReveal2Storage.sol";
import {Sort} from "./Sort.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Bitmap} from "./libraries/Bitmap.sol";
import {OperatorManager} from "./OperatorManager.sol";
import {console2} from "forge-std/Test.sol";

/// @title CommitReveal2
/// @author
///   - Justin (Euisin) Gee <Tokamak Network>
/// @notice This contract provides on-chain commit-reveal logic built for Tokamak Network.
/// @dev Implements a multi-phase commit-reveal flow and integrates with the following:
///   - EIP712 for typed data hashing
///   - Optimism L1 Fees for fee calculation on Optimism based L2
///   - OperatorManager for managing operator deposits and slash mechanics
/// @custom:company Tokamak Network
contract CommitReveal2 is EIP712, OptimismL1Fees, CommitReveal2Storage, OperatorManager {
    /**
     * @notice Associates the Bitmap library with a storage mapping from `uint248` to `uint256`.
     * @dev This allows efficient bitwise operations on round states packed into 256-bit words,
     *      where each `uint248` key corresponds to one “word” holding state for up to 256 rounds.
     */
    using Bitmap for mapping(uint248 => uint256);

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
    ) payable EIP712(name, version) {
        require(msg.value >= activationThreshold);
        s_depositAmount[msg.sender] = msg.value;
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_maxActivatedOperators = maxActivatedOperators;
        s_offChainSubmissionPeriod = offChainSubmissionPeriod;
        s_requestOrSubmitOrFailDecisionPeriod = requestOrSubmitOrFailDecisionPeriod;
        s_onChainSubmissionPeriod = onChainSubmissionPeriod;
        s_offChainSubmissionPeriodPerOperator = offChainSubmissionPeriodPerOperator;
        s_onChainSubmissionPeriodPerOperator = onChainSubmissionPeriodPerOperator;
        s_isInProcess = COMPLETED;
    }

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
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, gasPrice, s_activatedOperators.length);
    }

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
        returns (uint256)
    {
        return _calculateRequestPrice(callbackGasLimit, gasPrice, numOfOperators);
    }

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
    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256 newRound) {
        require(callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT, ExceedCallbackGasLimit());
        uint256 activatedOperatorsLength = s_activatedOperators.length;
        require(activatedOperatorsLength > 1, NotEnoughActivatedOperators());
        require(s_depositAmount[owner()] >= s_activationThreshold, LeaderLowDeposit());
        require(
            msg.value >= _calculateRequestPrice(callbackGasLimit, tx.gasprice, activatedOperatorsLength),
            InsufficientAmount()
        );
        unchecked {
            newRound = s_requestCount++;
        }
        s_roundBitmap.flipBit(newRound);
        //uint256 startTime = s_currentRound > s_lastfulfilledRound ? 0 : block.timestamp;
        uint256 startTime;
        if (s_isInProcess == COMPLETED) {
            s_currentRound = newRound;
            s_isInProcess = IN_PROGRESS;
            startTime = block.timestamp;
            emit IsInProcess(IN_PROGRESS);
        }
        s_requestInfo[newRound] = RequestInfo({
            consumer: msg.sender,
            startTime: startTime,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit
        });
        emit RandomNumberRequested(newRound, startTime, s_activatedOperators);
    }

    /**
     * @notice Calculates the total fee required for requesting a random number, factoring in:
     *         1. L2 execution costs (based on the callback gas limit and the number of operators).
     *         2. A flat fee (s_flatFee).
     *         3. L1 data costs for sending required transaction calldata.
     * @dev
     *      - The internal gas usage estimation is derived from two operations:
     *        (i) "submitMerkleRoot" (~47,216 L2 gas).
     *        (ii) "generateRandomNumber" (~21,119 × numOfOperators + 134,334 L2 gas).
     *      - The final fee also includes `_getL1CostWeiForcalldataSize2(...)` to account for the
     *        cost of posting data to the L1 chain.
     * @param callbackGasLimit The gas required by the consumer’s callback execution.
     * @param gasPrice The L2 gas price to be used for cost estimation.
     * @param numOfOperators The number of active operators factored into the total gas cost.
     * @return totalPrice The calculated total fee (in wei) needed to cover the request.
     */
    function _calculateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        internal
        view
        virtual
        returns (uint256)
    {
        // submitRoot l2GasUsed = 47216
        // generateRandomNumber l2GasUsed = 21118.97⋅N + 87117.53
        return (gasPrice * (callbackGasLimit + (21119 * numOfOperators + 134334))) + s_flatFee
            + _getL1CostWeiForcalldataSize2(MERKLEROOTSUB_CALLDATA_BYTES_SIZE, 292 + (128 * numOfOperators));
    }

    /**
     * @notice Computes the total L1 cost (in wei) for two separate calldata payload sizes.
     * @dev This is a helper function that sums the cost of submitting data of two different lengths
     *      to L1. Each call to `_getL1CostWeiForCalldataSize(...)` accounts for the overhead of
     *      RLP-encoding and L1 gas price adjustments in Optimism.
     * @param calldataSizeBytes1 The size (in bytes) of the first calldata payload.
     * @param calldataSizeBytes2 The size (in bytes) of the second calldata payload.
     * @return l1Cost The total cost (in wei) for posting both payloads to L1.
     */
    function _getL1CostWeiForcalldataSize2(uint256 calldataSizeBytes1, uint256 calldataSizeBytes2)
        private
        view
        returns (uint256)
    {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
        return _getL1CostWeiForCalldataSize(calldataSizeBytes1) + _getL1CostWeiForCalldataSize(calldataSizeBytes2);
    }

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
    function requestToSubmitCv(uint256[] calldata indices) external onlyOwner {
        require(indices.length > 0, ZeroLength());
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(
            block.timestamp < startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod, TooLate()
        );
        s_cvs[startTime] = new bytes32[](s_activatedOperators.length);
        s_requestedToSubmitCvIndices = indices;
        s_requestedToSubmitCvTimestamp = block.timestamp;
        emit RequestedToSubmitCv(startTime, indices);
    }

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
    function submitCv(bytes32 cv) external {
        require(cv != 0x00, ShouldNotBeZero());
        require(block.timestamp < s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        s_cvs[startTime][activatedOperatorIndex] = cv;
        emit CvSubmitted(startTime, cv, activatedOperatorIndex);
    }

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
    function failToSubmitCv() external {
        // ** check if it's time to submit merkle root or to fail this round
        uint256 round = s_currentRound;
        bytes32[] storage s_cvsArray = s_cvs[s_requestInfo[round].startTime];
        require(s_cvsArray.length > 0, CvNotRequested());
        require(block.timestamp >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod, TooEarly());
        // ** who didn't submi CV even though requested
        uint256 requestedToSubmitCVLength = s_requestedToSubmitCvIndices.length;
        uint256 didntSubmitCVLength; // ** count of operators who didn't submit CV
        address[] memory addressToDeactivates = new address[](requestedToSubmitCVLength);
        for (uint256 i; i < requestedToSubmitCVLength; i = _unchecked_inc(i)) {
            uint256 index = s_requestedToSubmitCvIndices[i];
            if (s_cvsArray[index] == 0) {
                // ** slash deposit and deactivate
                unchecked {
                    addressToDeactivates[didntSubmitCVLength++] = s_activatedOperators[index];
                }
            }
        }

        // ** return gas fee
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCV_GASUSED; // + L1Gas
        s_depositAmount[msg.sender] += returnGasFee;

        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator = slashRewardPerOperator
            + (activationThreshold * didntSubmitCVLength - returnGasFee)
                / (s_activatedOperators.length - didntSubmitCVLength + 1); // 1 for owner
        // ** update global slash reward
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        for (uint256 i; i < didntSubmitCVLength; i = _unchecked_inc(i)) {
            // *** update each slash reward
            address operator = addressToDeactivates[i];
            uint256 accumulatedReward = slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator];
            s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;

            // *** update deposit amount
            s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + accumulatedReward;
            _deactivate(s_activatedOperatorIndex1Based[operator] - 1, operator);
        }

        // ** restart or end this round
        if (s_activatedOperators.length > 1) {
            s_requestInfo[round].startTime = block.timestamp;
            emit RandomNumberRequested(round, block.timestamp, s_activatedOperators);
        } else {
            s_isInProcess = HALTED;
            emit IsInProcess(HALTED);
        }
    }

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
    function submitMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(
            block.timestamp < startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod, TooLate()
        );
        s_merkleRoot = merkleRoot;
        s_merkleRootSubmittedTimestamp = block.timestamp;
        s_isSubmittedMerkleRoot[startTime] = true;
        emit MerkleRootSubmitted(startTime, merkleRoot);
    }

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
    function failToRequestSubmitCvOrSubmitMerkleRoot() external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** Not requested to submit cv
        require(s_cvs[startTime].length == 0, AlreadyRequestedToSubmitCv());
        // ** MerkleRoot Not Submitted
        require(!s_isSubmittedMerkleRoot[startTime], AlreadySubmittedMerkleRoot());
        require(
            block.timestamp >= startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooEarly()
        );
        // ** slash the leadernode(owner)'s deposit
        uint256 activationThreshold = s_activationThreshold;
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED; // + L1Gas
        address owner = owner();
        unchecked {
            s_depositAmount[owner] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        // ** Distribute remainder among operators
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[owner] += delta;

        // Halt the round
        s_isInProcess = HALTED;
        emit IsInProcess(HALTED);
    }

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
    function submitMerkleRootAfterDispute(bytes32 merkleRoot) external onlyOwner {
        require(
            block.timestamp
                < s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooLate()
        );
        s_merkleRoot = merkleRoot;
        s_merkleRootSubmittedTimestamp = block.timestamp;
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        s_isSubmittedMerkleRoot[startTime] = true;
        emit MerkleRootSubmitted(startTime, merkleRoot);
    }

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
    function failToSubmitMerkleRootAfterDispute() external {
        uint256 round = s_currentRound;
        require(
            block.timestamp
                >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooEarly()
        );
        uint256 startTime = s_requestInfo[round].startTime;
        require(s_cvs[startTime].length > 0, CvNotRequested());
        require(!s_isSubmittedMerkleRoot[startTime], AlreadySubmittedMerkleRoot());

        // ** slash the leadernode(owner)'s deposit
        uint256 activationThreshold = s_activationThreshold;
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITMERKLEROOTAFTERDISPUTE_GASUSED; // + L1Gas
        address owner = owner();
        unchecked {
            s_depositAmount[owner] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[owner] += delta;

        s_isInProcess = HALTED;
        emit IsInProcess(HALTED);
    }

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
    function refund(uint256 round) external notInProcess {
        require(round < s_requestCount, InvalidRound());
        require(round >= s_currentRound, InvalidRound());
        RequestInfo storage requestInfo = s_requestInfo[round];
        require(requestInfo.consumer == msg.sender, NotConsumer());
        s_roundBitmap.flipBit(round); // 1 -> 0

        // ** refund
        uint256 cost = requestInfo.cost;
        require(cost > 0, AlreadyRefunded());
        requestInfo.cost = 0;
        assembly ("memory-safe") {
            // Transfer the ETH and check if it succeeded or not.
            if iszero(call(gas(), caller(), cost, 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

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
    function resume() external payable onlyOwner {
        require(s_isInProcess == HALTED, NotHalted());
        require(s_activatedOperators.length > 1, NotEnoughActivatedOperators());
        address owner = owner();
        if (msg.value > 0) s_depositAmount[owner] += msg.value;
        require(s_depositAmount[owner] >= s_activationThreshold, LeaderLowDeposit());
        uint256 nextRequestedRound = s_currentRound;
        bool requested;
        uint256 requestCountMinusOne = s_requestCount - 1;
        for (uint256 i; i < 10; i++) {
            (nextRequestedRound, requested) = s_roundBitmap.nextRequestedRound(nextRequestedRound);
            if (requested) {
                // Start this requested round
                s_currentRound = nextRequestedRound;
                s_requestInfo[nextRequestedRound].startTime = block.timestamp;
                s_isInProcess = IN_PROGRESS;
                emit IsInProcess(IN_PROGRESS);
                emit RandomNumberRequested(nextRequestedRound, block.timestamp, s_activatedOperators);
                return;
            }
            unchecked {
                // If we reach or pass the last round without finding any requested round,
                // mark as COMPLETED and set the current round to the last possible index.
                if (nextRequestedRound++ >= requestCountMinusOne) {
                    // && requested = false
                    s_isInProcess = COMPLETED;
                    s_currentRound = requestCountMinusOne;
                    emit IsInProcess(COMPLETED);
                    return;
                }
            }
        }
        s_currentRound = nextRequestedRound;
    }

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
        uint256[] calldata indices,
        bytes32[] calldata cvs,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external onlyOwner {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(s_isSubmittedMerkleRoot[startTime], MerkleRootNotSubmitted());
        require(
            block.timestamp
                < s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooLate()
        );
        uint256 cvsLength = cvs.length;
        bytes32[] storage s_cvsArray = s_cvs[startTime];
        if (s_cvsArray.length == 0) {
            s_cvs[startTime] = new bytes32[](s_activatedOperators.length);
        }
        uint256 requestToSubmitCoBitmap;
        // Operators who did not previously submit Cv on-chain
        for (uint256 i; i < cvsLength; i = _unchecked_inc(i)) {
            uint256 index = indices[i];
            requestToSubmitCoBitmap ^= 1 << index;
            require(ss[i] <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, InvalidSignatureS());
            require(
                index + 1
                    == s_activatedOperatorIndex1Based[ecrecover(
                        _hashTypedDataV4(
                            keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: startTime, cv: cvs[i]})))
                        ),
                        vs[i],
                        rs[i],
                        ss[i]
                    )],
                InvalidSignature()
            );
            s_cvsArray[index] = cvs[i];
        }
        // Operators who already submitted Cv on-chain, simply confirm it exists
        uint256 indicesLength = indices.length;
        for (uint256 i = cvsLength; i < indicesLength; i = _unchecked_inc(i)) {
            uint256 index = indices[i];
            requestToSubmitCoBitmap ^= 1 << index;
            require(s_cvsArray[index] > 0, CvNotSubmitted(indices[i]));
        }
        s_requestedToSubmitCoIndices = indices;
        s_requestToSubmitCoBitmap[startTime] = requestToSubmitCoBitmap;
        s_requestedToSubmitCoTimestamp = block.timestamp;
        // ** Not Complete
        emit RequestedToSubmitCo(startTime, indices);
    }

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
    function submitCo(bytes32 co) external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** Ensure we're within the on-chain submission period.
        require(block.timestamp < s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        // ** Confirm the newly revealed `co` hashes to the on-chain Cv.
        require(s_cvs[startTime][activatedOperatorIndex] == keccak256(abi.encodePacked(co)), InvalidCo());
        // ** Clear the operator’s bit from the bitmap to mark successful submission.
        assembly ("memory-safe") {
            mstore(0, startTime)
            mstore(0x20, s_requestToSubmitCoBitmap.slot)
            let slot := keccak256(0, 0x40)
            sstore(slot, and(sload(slot), not(shl(activatedOperatorIndex, 1))))
        }
        emit CoSubmitted(startTime, co, activatedOperatorIndex);
    }

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
    function failToSubmitCo() external {
        // ** check if it's time to fail this round
        uint256 round = s_currentRound;
        uint256 startTime = s_requestInfo[round].startTime;
        // Must be after Co submission deadline.
        require(block.timestamp >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod, TooEarly());
        uint256 requestToSubmitCoBitmap = s_requestToSubmitCoBitmap[startTime];
        require(requestToSubmitCoBitmap > 0, CoNotRequested());
        // Identify non-submitting operators.
        uint256 requestedToSubmitCoLength = s_requestedToSubmitCoIndices.length;
        uint256 didntSubmitCoLength; // ** count of operators who didn't submit Co
        address[] memory addressToDeactivates = new address[](requestedToSubmitCoLength);
        for (uint256 i; i < requestedToSubmitCoLength; i = _unchecked_inc(i)) {
            uint256 index = s_requestedToSubmitCoIndices[i];
            // ** Check if bit is still set, meaning no Co submitted for this operator.
            if (requestToSubmitCoBitmap & 1 << index > 0) {
                unchecked {
                    addressToDeactivates[didntSubmitCoLength++] = s_activatedOperators[index];
                }
            }
        }
        // Refund caller's gas fee for triggering the fail.
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCO_GASUSED;
        s_depositAmount[msg.sender] += returnGasFee;

        // Update slash rewards.
        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator = slashRewardPerOperator
            + (activationThreshold * didntSubmitCoLength - returnGasFee)
                / (s_activatedOperators.length - didntSubmitCoLength + 1); // 1 for owner
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        // Slash each non-submitting operator.
        for (uint256 i; i < didntSubmitCoLength; i = _unchecked_inc(i)) {
            // *** update each slash reward
            address operator = addressToDeactivates[i];
            uint256 accumulatedReward = slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator];
            s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;
            // Subtract threshold, add any accumulated slash reward already owed
            s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + accumulatedReward;
            _deactivate(s_activatedOperatorIndex1Based[operator] - 1, operator);
        }

        // Restart round if enough operators remain.
        if (s_activatedOperators.length > 1) {
            s_requestInfo[round].startTime = block.timestamp;
            emit RandomNumberRequested(round, block.timestamp, s_activatedOperators);
        } else {
            // Otherwise halt the round
            s_isInProcess = HALTED;
            emit IsInProcess(HALTED);
        }
    }

    struct TempStackVariables {
        // to avoid stack too deep error
        uint256 startTime;
        uint256 operatorsLength;
        uint256 secretsLength;
    }

    struct RVICV {
        // to avoid stack too deep error
        uint256 rv;
        uint256 i;
        bytes32 cv;
    }

    struct Signature {
        // to avoid stack too deep error
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

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
        bytes32[] calldata cos, // all cos
        bytes32[] calldata secrets, // already received off-chain
        Signature[] calldata signatures, // used struct to avoid stack too deep error, who didn't submit cv onchain, index descending order
        uint256[] calldata revealOrders
    ) external onlyOwner {
        // Prepare struct variables to avoid stack too deep error.
        TempStackVariables memory tempStackVariables = TempStackVariables({
            startTime: s_requestInfo[s_currentRound].startTime,
            operatorsLength: s_activatedOperators.length,
            secretsLength: secrets.length
        });
        // Deadline checks
        require(
            (
                block.timestamp
                    < s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
                        + (s_offChainSubmissionPeriodPerOperator * tempStackVariables.operatorsLength)
                        + s_requestOrSubmitOrFailDecisionPeriod
            )
                || (
                    block.timestamp
                        < s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
                            + (s_offChainSubmissionPeriodPerOperator * tempStackVariables.operatorsLength)
                            + s_requestOrSubmitOrFailDecisionPeriod
                ),
            TooLate()
        );
        // Initialize arrays for commitments (`cvs`) if not initialized and secrets (`ss`)
        s_ss[tempStackVariables.startTime] = new bytes32[](tempStackVariables.operatorsLength);
        bytes32[] storage s_cvsArray = s_cvs[tempStackVariables.startTime];
        if (s_cvsArray.length == 0) {
            s_cvs[tempStackVariables.startTime] = new bytes32[](tempStackVariables.operatorsLength);
        }
        {
            // to avoid stack too deep error
            RVICV memory rvicv;
            rvicv.rv = uint256(keccak256(abi.encodePacked(cos)));
            uint256[] memory diffs = new uint256[](tempStackVariables.operatorsLength);
            do {
                unchecked {
                    rvicv.cv = _efficientOneKeccak256(cos[--tempStackVariables.operatorsLength]);
                    diffs[tempStackVariables.operatorsLength] = _diff(rvicv.rv, uint256(rvicv.cv));
                    if (s_cvsArray[tempStackVariables.operatorsLength] > 0) {
                        require(s_cvsArray[tempStackVariables.operatorsLength] == rvicv.cv, InvalidCo());
                    } else {
                        // If cv was not on-chain, require a signature
                        require(
                            signatures[rvicv.i].s <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                            InvalidSignatureS()
                        );
                        require(
                            s_activatedOperatorIndex1Based[ecrecover(
                                _hashTypedDataV4(
                                    keccak256(
                                        abi.encode(
                                            MESSAGE_TYPEHASH,
                                            Message({timestamp: tempStackVariables.startTime, cv: rvicv.cv})
                                        )
                                    )
                                ),
                                signatures[rvicv.i].v,
                                signatures[rvicv.i].r,
                                signatures[rvicv.i++].s
                            )] == tempStackVariables.operatorsLength + 1,
                            InvalidSignature()
                        );
                        s_cvsArray[tempStackVariables.operatorsLength] = rvicv.cv;
                    }
                }
            } while (tempStackVariables.operatorsLength > 0);
            // Ensure revealOrders is strictly descending by diffs
            uint256 before = diffs[revealOrders[0]];
            uint256 activatedOperatorLength = cos.length;
            for (rvicv.i = 1; rvicv.i < activatedOperatorLength; rvicv.i = _unchecked_inc(rvicv.i)) {
                uint256 curr = diffs[revealOrders[rvicv.i]];
                require(before >= curr, RevealNotInDescendingOrder());
                before = curr;
            }
        }
        // Set revealOrders for next step
        s_revealOrders = revealOrders;

        s_requestedToSubmitSFromIndexK = tempStackVariables.secretsLength;
        emit RequestedToSubmitSFromIndexK(tempStackVariables.startTime, tempStackVariables.secretsLength);
        bytes32[] storage s_ssArray = s_ss[tempStackVariables.startTime];
        // The secrets are in reveal order.
        while (tempStackVariables.secretsLength > 0) {
            unchecked {
                uint256 activatedOperatorIndex = revealOrders[--tempStackVariables.secretsLength];
                bytes32 secret = secrets[tempStackVariables.secretsLength];
                require(s_cvsArray[activatedOperatorIndex] == _efficientTwoKeccak256(secret), InvalidS());
                s_ssArray[activatedOperatorIndex] = secret;
            }
        }
        // Record timestamp for on-chain S-submissions
        s_previousSSubmitTimestamp = block.timestamp;
    }

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
    function submitS(bytes32 s) external {
        // ** Retrieve current round and its request info.
        uint256 round = s_currentRound;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTime = requestInfo.startTime;

        // ** Check per-operator submission deadline.
        require(block.timestamp < s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator, TooLate());

        // ** Identify the caller’s operator index and validate the secret.
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        require(s_cvs[startTime][activatedOperatorIndex] == _efficientTwoKeccak256(s), InvalidS());

        // ** Ensure this operator is next in the reveal order.
        unchecked {
            require(s_revealOrders[s_requestedToSubmitSFromIndexK++] == activatedOperatorIndex, InvalidRevealOrder());
        }

        // ** Record the operator’s final secret on-chain and emit an event.
        emit SSubmitted(startTime, s, activatedOperatorIndex);
        s_ss[startTime][activatedOperatorIndex] = s;

        // ** If this operator is last in the reveal order, finalize the random number process for this round.
        if (activatedOperatorIndex == s_revealOrders[s_revealOrders.length - 1]) {
            // ** create random number
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(s_ss[startTime])));
            uint256 nextRound = _unchecked_inc(round);
            // ** Move to the next round or mark as completed.
            if (nextRound == s_requestCount) {
                s_isInProcess = COMPLETED;
                emit IsInProcess(COMPLETED);
            } else {
                s_requestInfo[nextRound].startTime = block.timestamp;
                s_currentRound = nextRound;
            }
            // ** Reward this last revealer.
            s_depositAmount[s_activatedOperators[activatedOperatorIndex]] += requestInfo.cost;
            // ** Notify and callback.
            emit RandomNumberGenerated(
                round,
                randomNumber,
                _call(
                    requestInfo.consumer,
                    abi.encodeWithSelector(ConsumerBase.rawFulfillRandomNumber.selector, round, randomNumber),
                    requestInfo.callbackGasLimit
                )
            );
        }
    }

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
    function failToSubmitS() external {
        // ** Ensure S was requested
        bytes32[] storage s_ssArray = s_ss[s_requestInfo[s_currentRound].startTime];
        require(s_ssArray.length > 0, SNotRequested());
        // ** check if it's time to fail this round
        require(block.timestamp >= s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator, TooEarly());

        // ** Refund gas to the caller
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITS_GASUSED;
        s_depositAmount[msg.sender] += returnGasFee;

        // ** Update slash rewards
        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator =
            slashRewardPerOperator + (activationThreshold - returnGasFee) / (s_activatedOperators.length); // 1 for owner
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        // ** s_revealOrders[s_requestedToSubmitSFromIndexK] is the index of the operator who didn't submit S
        uint256 indexToSlash = s_revealOrders[s_requestedToSubmitSFromIndexK];
        address operator = s_activatedOperators[indexToSlash];
        // ** update deposit amount
        s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + slashRewardPerOperator
            - s_slashRewardPerOperatorPaid[operator];
        s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;
        // ** deactivate
        _deactivate(indexToSlash, operator);

        // ** restart or end this round
        if (s_activatedOperators.length > 1) {
            s_requestInfo[s_currentRound].startTime = block.timestamp;
            emit RandomNumberRequested(s_currentRound, block.timestamp, s_activatedOperators);
        } else {
            s_isInProcess = HALTED;
            emit IsInProcess(HALTED);
        }
    }

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
    function failToRequestSOrGenerateRandomNumber() external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** MerkleRoot Submitted
        require(s_isSubmittedMerkleRoot[startTime], MerkleRootNotSubmitted());
        if (s_requestToSubmitCoBitmap[startTime] > 0) {
            require(
                block.timestamp
                    >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
                        + (s_onChainSubmissionPeriodPerOperator * s_activatedOperators.length)
                        + s_requestOrSubmitOrFailDecisionPeriod,
                TooEarly()
            );
        } else {
            require(
                block.timestamp
                    >= s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
                        + (s_offChainSubmissionPeriodPerOperator * s_activatedOperators.length)
                        + s_requestOrSubmitOrFailDecisionPeriod,
                TooEarly()
            );
        }
        // ** slash the leadernode(owner)'s deposit
        uint256 activationThreshold = s_activationThreshold;
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED; // + L1Gas
        address owner = owner();
        unchecked {
            s_depositAmount[owner] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[owner] += delta;

        s_isInProcess = HALTED;
        emit IsInProcess(HALTED);
    }

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
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint256[] calldata revealOrders
    ) external {
        uint256 activatedOperatorsLength;
        assembly ("memory-safe") {
            activatedOperatorsLength := sload(s_activatedOperators.slot)
            // ** check if all secrets are submitted
            if gt(activatedOperatorsLength, secrets.length) {
                mstore(0, 0xe0767fa4) // selector for InvalidSecretLength()
                revert(0x1c, 0x04)
            }
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
            if iszero(
                or(
                    lt(
                        timestamp(),
                        add(
                            add(
                                add(sload(s_merkleRootSubmittedTimestamp.slot), sload(s_offChainSubmissionPeriod.slot)),
                                mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorsLength)
                            ),
                            sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                        )
                    ),
                    lt(
                        timestamp(),
                        add(
                            add(
                                add(sload(s_requestedToSubmitCoTimestamp.slot), sload(s_onChainSubmissionPeriod.slot)),
                                mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorsLength)
                            ),
                            sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                        )
                    )
                )
            ) {
                mstore(0, 0xecdd1c29) // selector for TooLate()
                revert(0x1c, 0x04)
            }
        }

        bytes32[] memory cos = new bytes32[](activatedOperatorsLength);
        bytes32[] memory cvs = new bytes32[](activatedOperatorsLength);
        assembly ("memory-safe") {
            let cvsDataPtr := add(cvs, 0x20)
            for { let i := 0 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                //cos[i] = keccak256(abi.encodePacked(secrets[i]));
                //cvs[i] = keccak256(abi.encodePacked(cos[i]));
                mstore(0x00, calldataload(add(secrets.offset, shl(5, i))))
                let cosMemP := add(add(cos, 0x20), shl(5, i))
                mstore(cosMemP, keccak256(0x00, 0x20))
                mstore(add(cvsDataPtr, shl(5, i)), keccak256(cosMemP, 0x20))
            }

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
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let rv := keccak256(add(cos, 0x20), shl(5, activatedOperatorsLength))
            let before := _diff(rv, mload(add(cvsDataPtr, shl(5, calldataload(revealOrders.offset)))))
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                let after :=
                    _diff(rv, mload(add(cvsDataPtr, shl(5, calldataload(add(revealOrders.offset, shl(5, i)))))))
                if lt(before, after) {
                    mstore(0, 0x24f1948e) // selector for RevealNotInDescendingOrder()
                    revert(0x1c, 0x04)
                }
                before := after
            }

            // ** Create Merkle Root and verify it
            let hashCount := sub(activatedOperatorsLength, 1) // unchecked sub, check outside of this function
            let hashes := mload(0x40)
            mstore(hashes, hashCount)
            let hashesDataPtr := add(hashes, 0x20)
            let cvsPos
            let hashPos
            for { let i } lt(i, hashCount) { i := add(i, 1) } {
                switch lt(cvsPos, activatedOperatorsLength)
                case 1 {
                    mstore(0x00, mload(add(cvsDataPtr, shl(5, cvsPos))))
                    cvsPos := add(cvsPos, 1)
                }
                default {
                    mstore(0x00, mload(add(hashesDataPtr, shl(5, hashPos))))
                    hashPos := add(hashPos, 1)
                }
                switch lt(cvsPos, activatedOperatorsLength)
                case 1 {
                    mstore(0x20, mload(add(cvsDataPtr, shl(5, cvsPos))))
                    cvsPos := add(cvsPos, 1)
                }
                default {
                    mstore(0x20, mload(add(hashesDataPtr, shl(5, hashPos))))
                    hashPos := add(hashPos, 1)
                }
                mstore(add(hashesDataPtr, shl(5, i)), keccak256(0x00, 0x40))
            }
            // mstore(0x40, add(hashesDataPtr, shl(5, hashCount))) // update the free memory pointer,
            // or Restore(keep) the free memory pointer
            if iszero(eq(mload(add(hashesDataPtr, shl(5, sub(hashCount, 1)))), sload(s_merkleRoot.slot))) {
                mstore(0, 0x624dc351) // selector for MerkleVerificationFailed()
                revert(0x1c, 0x04)
            }
        }

        // ** verify signer
        uint256 round = s_currentRound;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTimestamp = requestInfo.startTime;
        for (uint256 i; i < activatedOperatorsLength; i = _unchecked_inc(i)) {
            // signature malleability prevention
            require(ss[i] <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, InvalidSignatureS());
            require(
                s_activatedOperatorIndex1Based[ecrecover(
                    _hashTypedDataV4(
                        keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: startTimestamp, cv: cvs[i]})))
                    ),
                    vs[i],
                    rs[i],
                    ss[i]
                )] > 0,
                InvalidSignature()
            );
        }

        // ** create random number
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(secrets)));
        uint256 nextRound = _unchecked_inc(round);
        unchecked {
            if (nextRound == s_requestCount) {
                s_isInProcess = COMPLETED;
                emit IsInProcess(COMPLETED);
            } else {
                s_requestInfo[nextRound].startTime = block.timestamp;
                s_currentRound = nextRound;
            }
        }
        // reward the last revealer
        s_depositAmount[s_activatedOperators[revealOrders[activatedOperatorsLength - 1]]] += requestInfo.cost;
        emit RandomNumberGenerated(
            round,
            randomNumber,
            _call(
                requestInfo.consumer,
                abi.encodeWithSelector(ConsumerBase.rawFulfillRandomNumber.selector, round, randomNumber),
                requestInfo.callbackGasLimit
            )
        );
    }

    /**
     * @notice Computes the EIP-712 typed data hash of a `(timestamp, cv)` pair.
     * @dev Simply wraps `_hashTypedDataV4` with the given parameters to produce the final digest used for operator signatures.
     * @param timestamp The timestamp included in the typed data struct.
     * @param cv The commitment value (Cv) tied to this timestamp.
     * @return The resulting EIP-712 hash digest.
     */
    function getMessageHash(uint256 timestamp, bytes32 cv) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: timestamp, cv: cv}))));
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

    function _efficientKeccak256(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _efficientOneKeccak256(bytes32 a) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            value := keccak256(0x00, 0x20)
        }
    }

    function _efficientTwoKeccak256(bytes32 a) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x00, keccak256(0x00, 0x20))
            value := keccak256(0x00, 0x20)
        }
    }

    function _unchecked_inc(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function _diff(uint256 a, uint256 b) private pure returns (uint256 c) {
        assembly ("memory-safe") {
            switch gt(a, b)
            case true { c := sub(a, b) }
            default { c := sub(b, a) }
        }
    }

    /// ** deposit and withdraw

    function _call(address target, bytes memory data, uint256 callbackGasLimit) private returns (bool success) {
        assembly ("memory-safe") {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) { revert(0, 0) }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) { return(0, 0) }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := call(callbackGasLimit, target, 0, add(data, 0x20), mload(data), 0, 0)
        }
    }
}
