// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library CommitReveal2Storage {
    struct CvAndSigRS {
        bytes32 cv;
        SigRS rs;
    }

    struct SecretAndSigRS {
        bytes32 secret;
        SigRS rs;
    }

    struct SigRS {
        bytes32 r;
        bytes32 s;
    }
}

interface CommitReveal2 {
    // ** CommitReveal2 onlyOwner settings
    function setFees(uint256 activationThreshold, uint256 flatFee) external;
    function setL1FeeCoefficient(uint8 coefficient) external;
    function setPeriods(
        uint256 offChainSubmissionPeriod,
        uint256 requestOrSubmitOrFailDecisionPeriod,
        uint256 onChainSubmissionPeriod,
        uint256 offChainSubmissionPeriodPerOperator,
        uint256 onChainSubmissionPeriodPerOperator
    ) external;

    // ** CommitReveal2 for consumers
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
     * @param round The round to be refunded.
     */
    function refund(uint256 round) external;

    /**
     * @notice Requests a new random number from this contract.
     * @dev emit Status(uint256 curStartTime, uint256 curState), only if this request is to be processed right away. Otherwise there are other requests in process.
     * @param callbackGasLimit The gas limit for executing the eventual consumer callback.
     * @return newRound The round number of the newly requested round.
     */
    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256 newRound);

    // ** CommitReveal2
    /**
     * @notice Submits the Merkle root on-chain for the current round.
     * @dev onlyOwner(leaderNode) function, emit MerkleRootSubmitted(uint256 startTime, bytes32 merkleRoot)
     * @param merkleRoot The Merkle root which aggregates all required commitments. Each leaf is Cvi in activated operator index order.
     */
    function submitMerkleRoot(bytes32 merkleRoot) external;

    /**
     * @notice Finalizes the random number generation by using all the operators’ secrets for the current round.
     * @dev emit Status(uint256 curStartTime, uint256 curState) for operators, emit RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess) for consumers
     * @param secretSigRSs [(secret_0, (r,s)_0, ..., secret_n, (r,s)_n], when 0-n is the activated operator index.
     * @param packedVs, The packed 'v's of each signatures. eg. [v_1, ..., v_n] -> [28, 27, 27] -> 0x00000000000000000000000000000000000000000000000000000000001b1b1c, when 0-n is the activated operator index.
     * @param packedRevealOrders The specified index ordering for (R_v > C_vi ? Rv - C_vi : C_vi - Rv) in decending, when Rv = keccak256(C_o0, ..., C_on). eg. [2, 1, 3] -> 0x0000000000000000000000000000000000000000000000000000000000030102
     */
    function generateRandomNumber(
        CommitReveal2Storage.SecretAndSigRS[] memory secretSigRSs,
        uint256 packedVs, // packedVs
        uint256 packedRevealOrders
    ) external;

    // ** CommitReveal2 Dispute
    /**
     * @notice Finalizes the random number generation when some operators’ commitments (`Cv`) were submitted on-chain.
     * @dev Combines both off-chain and on-chain data to compute the result.
     *      Emits `Status` and `RandomNumberGenerated` events, similar to `generateRandomNumber()`.
     * @param allSecrets Secrets submitted for all operators, in activated operator index order.
     * @param sigRSsForAllCvsNotOnChain The [(r,s)_i, ...] signatures for all operators whose `C_vi` are not on-chain.
     *        Their `C_vi` values may have been submitted through `submitCv`, `requestToSubmitCo`.
     *        Use `getZeroBitIfSubmittedCvOnChainBitmap()` to check which `C_vi` values are on-chain.
     * @param packedVsForAllCvsNotOnChain The packed 'v' values for the above signatures.
     *        Example: [28, 27, 27] → 0x...00001b1b1c
     * @param packedRevealOrders The specified reveal order indices, packed as bytes into a uint256.
     *        Computed using (Rv > C_vi ? Rv - C_vi : C_vi - Rv) in descending order,
     *        where Rv = keccak256(C_o0, ..., C_on). Example: [2, 1, 3] → 0x...0000030102
     */
    function generateRandomNumberWhenSomeCvsAreOnChain(
        bytes32[] calldata allSecrets,
        CommitReveal2Storage.SigRS[] calldata sigRSsForAllCvsNotOnChain,
        uint256 packedVsForAllCvsNotOnChain,
        uint256 packedRevealOrders
    ) external;

    /**
     * @notice Requests on-chain submissions of commitments (`Cv`) from a subset of activated operators.
     * @dev Only callable by the leader node (owner). Emits RequestedToSubmitCv(uint256 startTime, uint256 packedIndices).
     *
     * `packedIndices` encodes operator indices from least-significant byte (rightmost) to most-significant (left).
     * Each byte represents a 0-based index in the activated operator list and must be in strictly ascending order.
     * For example:
     * - [1, 4, 7] → 0x...0000070401
     * - [0]       → 0x...00000000
     *
     * Submitting 0x...00 indicates a request for operator at index 0 to submit their `Cvi`.
     *
     * The function validates all indices are within bounds and sorted in ascending order (from right to left).
     * Upon request, the request timestamp is stored, re-requests are prevented, and internal tracking is initialized.
     *
     * @param packedIndicesAscendingFromLSB A packed uint256 containing the indices of the operators required to submit `Cv` on-chain.
     */
    function requestToSubmitCv(uint256 packedIndicesAscendingFromLSB) external;

    /**
     * @notice Requests on-chain submission of "C_oi" values (Reveal-1) from a subset of operators
     *         after the Merkle root has been submitted.
     * @dev onlyOwner(leaderNode) function. emit RequestedToSubmitCo(uint256 startTime, uint256 packedIndices);
     *
     * Why cvRSs and packedVs parameters are needed:
     * During the commit phase, some nodes broadcast C_vi off-chain with signatures, while others
     * submit C_vi on-chain via requestToSubmitCv function. For nodes that only broadcast off-chain,
     * there's no on-chain C_vi to verify C_vi == hash(C_oi) when they submit C_oi. Without this
     * verification, they could submit arbitrary values and break the protocol. Therefore, the leader
     * node must submit the off-chain C_vi values with signatures to prove authenticity.
     *
     * @param cvRSsForCvsNotOnChainAndReqToSubmitCo The [(C_vi, (r,s)_i), ...], i is the index of
     *        the operator who are required to submit their C_o onchain and their C_v is not on-chain.
     *        (The C_vi could have been submitted in SubmitCv function. There is
     *        getZeroBitIfSubmittedCvOnChainBitmap() function to check if the C_vi is on-chain.)
     * @param packedVsForCvsNotOnChainAndReqToSubmitCo The packed 'v'_i, i is the index of the operator
     *        who are required to submit their C_o onchain and their C_v is not on-chain. (The C_vi
     *        could have been submitted in SubmitCv function. There is getZeroBitIfSubmittedCvOnChainBitmap()
     *        function to check if the C_vi is on-chain.), e.g. [28, 27, 27] ->
     *        0x00000000000000000000000000000000000000000000000000000000001b1b1c
     * @param indicesLength The length of the packedIndicesFirstCvNotOnChainRestCvOnChain.
     *        e.g. [3, 4, 5, 0, 1, 2] -> 6
     * @param packedIndicesFirstCvNotOnChainRestCvOnChain The packed indices of the operator who are
     *        required to submit their C_o onchain. e.g. ([0, 1, 2, 3, 4, 5] needs to submit their C_oi.
     *        [3, 4, 5] operators' C_vi are not on chain and [0, 1, 2] operators' C_vi are on-chain
     *        possibly in SubmitCv function. There is getZeroBitIfSubmittedCvOnChainBitmap() function
     *        to check if the C_vi is on-chain.) -> [3, 4, 5, 0, 1, 2] ->
     *        0x0000000000000000000000000000000000000000000000000000020100050403
     */
    function requestToSubmitCo(
        CommitReveal2Storage.CvAndSigRS[] memory cvRSsForCvsNotOnChainAndReqToSubmitCo,
        uint256 packedVsForCvsNotOnChainAndReqToSubmitCo, // packedVsForCvsNotOnChainAndReqToSubmitCo,
        uint256 indicesLength,
        uint256 packedIndicesFirstCvNotOnChainRestCvOnChain
    ) external;

    /**
     * @notice Requests an on-chain reveal phase (`S`) for operators who failed to provide their secrets off-chain,
     *         while simultaneously uploading the off-chain secrets that the leader node already possesses.
     * @dev onlyOwner(leaderNode) function, emit RequestedToSubmitSFromIndexK(uint256 startTime, uint256 indexK)
     * @param allCos All C_oi must be submitted even if some operators submitted their Co in SubmitCo function, because the calldata is cheaper than `sstore` and `sload`.
     * @param secretsReceivedOffchainInRevealOrder The secrets that are received off-chain in revealOrders. [secret_k, ...], when k is the revealOrder[i]
     * @param packedVsForAllCvsNotOnChain The packed 'v's of the signatures for all operators' whose C_vi are not on-chain. The C_vi could have been submitted in SubmitCv, RequestToSubmitCo ... functions.(There is getZeroBitIfSubmittedCvOnChainBitmap() function to check if the C_vi is on-chain.). e.g. [28, 27, 27] -> 0x00000000000000000000000000000000000000000000000000000000001b1b1c
     * @param sigRSsForAllCvsNotOnChain The [(r,s)_i, ...] for all operators' whose C_vi are not on-chain. The C_vi could have been submitted in SubmitCv, RequestToSubmitCo ... functions.(There is getZeroBitIfSubmittedCvOnChainBitmap() function to check if the C_vi is on-chain.).
     * @param packedRevealOrders The specified index ordering for (R_v > C_vi ? Rv - C_vi : C_vi - Rv) in decending, when Rv = keccak256(C_o0, ..., C_on). eg. [2, 1, 3] -> 0x0000000000000000000000000000000000000000000000000000000000030102
     */
    function requestToSubmitS(
        bytes32[] memory allCos,
        bytes32[] memory secretsReceivedOffchainInRevealOrder,
        uint256 packedVsForAllCvsNotOnChain, // packedVsForAllCvsNotOnChain
        CommitReveal2Storage.SigRS[] memory sigRSsForAllCvsNotOnChain,
        uint256 packedRevealOrders
    ) external;

    /**
     * @notice Requested activated operator to submit their “C_vi” on-chain.
     * @dev emit CvSubmitted(uint256 startTime, bytes32 cv, uint256 index)
     * @param cv The Reveal-2 value (C_vi) from this operator.
     */
    function submitCv(bytes32 cv) external;

    /**
     * @notice Requested activated operator to submit their “C_oi” on-chain.
     * @dev emit CoSubmitted(uint256 startTime, bytes32 co, uint256 index)
     * @param co The Reveal-1 value (C_oi) from this operator, whose keccak-hash must match the existing on-chain Cv.
     */
    function submitCo(bytes32 co) external;

    /**
     * @notice Submit secrets (S) on-chain for the current round.
     * @dev Must submit in reveal order
     * @param s The final secret reveal (S) from the operator, which must:
     *          1) Match the on-chain `Cv` for this operator (double-hash check).
     *          2) Align with the reveal order: the contract verifies this operator is the next index
     *             in `s_revealOrders`. If they are last, the random number is finalized.
     */
    function submitS(bytes32 s) external;

    /**
     * @notice Fails the current round if some operators did not submit their required on-chain commitments (`C_vi`)
     *         within the allowed on-chain submission period.
     * @dev (`block.timestamp >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod`).
     *      If at least 2 operators remain active, the round is “restarted” by resetting its startTime to the current block.timestamp
     *      and emit Status(uint256 curStartTime, uint256 curState), Status(new block.timestamp, uint256 IN_PROCESS).
     *      Otherwise, the contract transitions to `HALTED` state (no further progression is possible), and emit Status(uint256 curStartTime, uint256 curState), Status(curStartTime, uint256 HALTED).
     *      emit DeActivated(address operator), for operator who didn't submit their C_vi
     */
    function failToSubmitCv() external;

    /**
     * @notice Halts the round if the leader (owner) neither requested commits (`Cv`) nor submitted a Merkle root
     *         within the designated period.
     * @dev `block.timestamp >= startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod`. emit Status(curStartTime, uint256 HALTED)
     */
    function failToRequestSubmitCvOrSubmitMerkleRoot() external;

    /**
     * @notice Fails the current round if some operators did not submit their C_oi, within the deadline.
     * @dev `block.timestamp >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod`.
     *      If at least 2 operators remain active, the round is “restarted” by resetting its startTime to the current block.timestamp
     *      and emit Status(uint256 curStartTime, uint256 curState), Status(new block.timestamp, uint256 IN_PROCESS).
     *      Otherwise, the contract transitions to `HALTED` state (no further progression is possible), and emit Status(uint256 curStartTime, uint256 curState), Status(curStartTime, uint256 HALTED).
     */
    function failToSubmitCo() external;

    /**
     * @notice Halts the round if the leader (owner) fails to submit the Merkle root after a dispute
     *         within the required period.
     * @dev block.timestamp >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod. emit Status(curStartTime, uint256 HALTED)
     */
    function failToSubmitMerkleRootAfterDispute() external;

    /**
     * @notice Fails the current round if an operator fails to submit its secret by the on-chain deadline.
     * @dev block.timestamp >= s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator.
     *
     *   6) If more than one operator remains, resets the round’s `startTime` to `block.timestamp`
     *       If at least 2 operators remain active, the round is “restarted” by resetting its startTime to the current block.timestamp
     *      and emit Status(uint256 curStartTime, uint256 curState), Status(new block.timestamp, uint256 IN_PROCESS).
     *      Otherwise, the contract transitions to `HALTED` state (no further progression is possible), and emit Status(uint256 curStartTime, uint256 curState), Status(curStartTime, uint256 HALTED).
     */
    function failToSubmitS() external;

    /**
     * @notice Halts the round if the leader node (owner) fails to request the final secret submissions
     *         or to generate the random number before the required deadline.
     * @dev Checks two possible deadlines based on whether there was a `Co` submission request:
     *       - If some operators were requested to submit C_oi on-chain, we require:
     *           `block.timestamp >= (s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
     *             + (s_onChainSubmissionPeriodPerOperator * s_activatedOperators.length)
     *             + s_requestOrSubmitOrFailDecisionPeriod)`.
     *       - Otherwise, we require:
     *           `block.timestamp >= (s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
     *             + (s_offChainSubmissionPeriodPerOperator * s_activatedOperators.length)
     *             + s_requestOrSubmitOrFailDecisionPeriod)`.
     *      emit Status(curStartTime, uint256 HALTED)
     */
    function failToRequestSorGenerateRandomNumber() external;

    // ** CommitReveal2 Dispute onlyOwner
    /**
     * @notice Resumes the protocol if it is currently halted, typically due to
     *         an unresolved leader node failure. This allows the leader node to
     *         inject new deposits if necessary and activate a pending or next
     *         requested round. A resume function effectively indicates the leader node is back online and
     *         ready to continue serving random number requests.
     * @dev
     *   1) Requires at least two activated operators (`s_activatedOperators.length > 1`).
     *   2) The owner can optionally send ETH to replenish its deposit (`s_depositAmount[owner()]`),
     *      which must remain >= `s_activationThreshold`.
     *   3) Scans for up to 10 times through the bitmap of requested rounds, seeking the
     *      next available requested round:
     *        - If found, that round is started by setting `s_currentRound` to it,
     *          updating the start time to `block.timestamp`, and marking the state as `IN_PROGRESS`.
     *          emit Status(new block.timestamp, uint256 IN_PROGRESS)
     *        - If none are found by the time we exceed `requestCountMinusOne`, we mark
     *          the state as `COMPLETED` and set `s_currentRound` to the last round index.
     */
    function resume() external payable;

    // ** CommitReveal2 for operators
    function activate() external;
    function claimSlashReward() external;
    function deactivate() external;
    function deposit() external payable;
    function depositAndActivate() external payable;
    function withdraw() external;

    /**
     * @notice Returns the start time of the current round.
     * @dev Reads from the `startTime` field in the request info mapping using the current round index.
     * @return The UNIX timestamp representing the start time of the current round.
     */
    function getCurStartTime() external view returns (uint256);

    /**
     * @notice Returns the bitmap tracking which operators have submitted their `Cv` values on-chain.
     * @dev If no `requestToSubmitXX()` has been made in the current round, returns 0xffffffff (all bits set).
     *      Otherwise, returns the current value of `s_zeroBitIfSubmittedCvBitmap`, which tracks Cv submission status.
     *      The least-significant bit (LSB) corresponds to operator index 0, the next bit to index 1, and so on.
     *      A bit value of 0 means the operator has submitted their `Cv` value on-chain.
     * @return A uint256 bitmap representing submission status of requested `Cv` values.
     */
    function getZeroBitIfSubmittedCvOnChainBitmap() external view returns (uint256);

    // ** Ownable contract
    function cancelOwnershipHandover() external payable;
    function completeOwnershipHandover(address pendingOwner) external payable;
    function requestOwnershipHandover() external payable;
    function renounceOwnership() external payable;
    function transferOwnership(address newOwner) external payable;

    // ***************************
    // **** view functions *******
    // ***************************

    // *** Owner Related ***
    // ** Ownable
    function owner() external view returns (address result);
    function ownershipHandoverExpiresAt(address pendingOwner) external view returns (uint256 result);

    // ** CommitReveal2
    // * EIP712
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
    // * For Consumers
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        external
        view
        returns (uint256);
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256);

    // * For Operators
    function MAX_ACTIVATED_OPERATORS() external view returns (uint256);
    function getActivatedOperators() external view returns (address[] memory);
    function getActivatedOperatorsLength() external view returns (uint256);
    function getDepositPlusSlashReward(address operator) external view returns (uint256);
    function s_activatedOperatorIndex1Based(address operator) external view returns (uint256);
    function s_activationThreshold() external view returns (uint256);
    function s_currentRound() external view returns (uint256);
    function s_cvs(uint256) external view returns (bytes32);
    function s_depositAmount(address operator) external view returns (uint256);
    function s_flatFee() external view returns (uint256);
    function s_isInProcess() external view returns (uint256);
    function s_l1FeeCoefficient() external view returns (uint8);
    function s_merkleRoot() external view returns (bytes32);
    function s_merkleRootSubmittedTimestamp(uint256 startTime) external view returns (uint256);
    function s_packedRevealOrders() external view returns (uint256);
    function s_previousSSubmitTimestamp(uint256 startTime) external view returns (uint256);
    function s_requestCount() external view returns (uint256);
    function s_requestInfo(uint256 round)
        external
        view
        returns (address consumer, uint256 startTime, uint256 cost, uint256 callbackGasLimit);
    function s_requestedToSubmitCoLength() external view returns (uint256);
    function s_requestedToSubmitCoPackedIndices() external view returns (uint256);
    function s_requestedToSubmitCoTimestamp(uint256 startTime) external view returns (uint256);
    function s_requestedToSubmitCvLength() external view returns (uint256);
    function s_requestedToSubmitCvPackedIndices() external view returns (uint256);
    function s_requestedToSubmitCvTimestamp(uint256 startTime) external view returns (uint256);
    function s_requestedToSubmitSFromIndexK() external view returns (uint256);
    function s_roundBitmap(uint248 wordPos) external view returns (uint256);
    function s_secrets(uint256) external view returns (bytes32);
    function s_slashRewardPerOperatorPaidX8(address) external view returns (uint256);
    function s_slashRewardPerOperatorX8() external view returns (uint256);
    function s_zeroBitIfSubmittedCoBitmap() external view returns (uint256);
    function s_zeroBitIfSubmittedCvBitmap() external view returns (uint256);
}
