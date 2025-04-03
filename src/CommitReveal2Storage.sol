// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitReveal2Storage {
    // * Type Declarations
    /**
     * @notice Represents a commitment message containing a timestamp and a commitment value (`cv`).
     * @dev
     *   - Used in EIP-712 typed data hashing (see `MESSAGE_TYPEHASH`) for operator signatures.
     *   - `timestamp` indicates when the commitment was made.
     *   - `cv` is a double hashed value of operator secret
     */
    struct Message {
        uint256 timestamp;
        bytes32 cv;
    }

    /**
     * @notice Stores the metadata for each random number request/round.
     * @dev
     *   - `consumer` is the address requesting randomness (receives the callback).
     *   - `startTime` is the time when this round effectively began (or will begin if queued).
     *   - `cost` is the total fee paid by the consumer for this request.
     *   - `callbackGasLimit` is how much gas the consumer allocated for the eventual callback.
     */
    struct RequestInfo {
        address consumer;
        uint256 startTime;
        uint256 cost;
        uint256 callbackGasLimit;
    }

    // * Errors

    error OperatorNotActivated();
    error ExceedCallbackGasLimit();
    error NotEnoughActivatedOperators(); // 0x77599fd9
    error InsufficientAmount(); // 0x5945ea56
    error NotActivatedOperator(); // 0x1b256530
    error MerkleVerificationFailed(); // 0x624dc351
    error InvalidSignatureS(); // 0xbf4bf5b8
    error InvalidSignature();
    error MerkleRootAlreadySubmitted(); // 0xa34402b2
    error AllSubmittedCv();
    error InvalidSignatureLength();
    error TooEarly();
    error L1FeeEstimationFailed(); // 0xb75f34bf
    error TooLate(); // 0xecdd1c29
    error InvalidCo();
    error InvalidIndex();
    error DuplicateIndices();
    error WrongRevealOrder(); // 0xe3ae7cc0
    error InvalidS();
    error InvalidRevealOrder();
    error InvalidSecretLength(); // 0xe0767fa4
    error ShouldNotBeZero();
    error NotConsumer();
    error SRequested();
    error InvalidRound();
    error AlreadyRefunded();
    error RandomNumGenerated();
    error AlreadySubmittedMerkleRoot();
    error AlreadyRequestedToSubmitCv();
    error CvNotRequested();
    error MerkleRootNotSubmitted();
    error NotHalted();
    error ZeroLength();
    error LeaderLowDeposit(); // 0xc0013a5a
    error CoNotRequested();
    error SNotRequested();
    error AlreadySubmittedS();
    error ETHTransferFailed(); // 0xb12d13eb
    error RevealNotInDescendingOrder(); // 0x24f1948e

    error CvNotSubmitted(uint256 index);

    // * Events
    event Round(uint256 startTime, uint256 state); // 0xe2af5431d45f111f112df909784bcdd0cf9a409671adeaf0964cc234a98297fe
    event MerkleRootSubmitted(uint256 startTime, bytes32 merkleRoot);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess); // 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a

    event RequestedToSubmitCv(uint256 startTime, uint256[] indices);
    event RequestedToSubmitCo(uint256 startTime, uint256[] indices);
    event CvSubmitted(uint256 startTime, bytes32 cv, uint256 index);
    event CoSubmitted(uint256 startTime, bytes32 co, uint256 index);
    event RequestedToSubmitSFromIndexK(uint256 startTime, uint256 index);
    event SSubmitted(uint256 startTime, bytes32 s, uint256 index);

    // * State Variables
    // ** public

    /**
     * @notice A fixed fee added on top of the gas cost for each request.
     * @dev
     *   - Must be included when the consumer pays for a random number request.
     *   - Covers operational overhead beyond the raw L2 and L1 fees.
     */
    uint256 public s_flatFee;

    /**
     * @notice The index of the round currently being processed, if `s_isInProcess` is IN_PROGRESS.
     * @dev
     *   - Increments when a new round starts.
     *   - Used to track which request is “active” for on-chain commit/reveal phases.
     */
    uint256 public s_currentRound;

    /**
     * @notice The total number of requests ever made (incremented each time `requestRandomNumber()` is called).
     * @dev
     *   - Each request is identified by a “round” index in [0..s_requestCount-1].
     *   - Used to ensure newly created round indices are unique and sequential.
     */
    uint256 public s_requestCount;

    /**
     * @notice Stores the latest submitted Merkle root for the current round.
     * @dev
     *   - Used to validate operator commitments in the chain of trust for reveal phases.
     *   - Updated by the leader node via `submitMerkleRoot()`.
     */
    bytes32 public s_merkleRoot;

    /**
     * @notice Tracks when the contract owner requested on-chain commit submissions (`Cv`).
     * @dev
     *   - Relevant to the deadline for calling `submitCv()` or failing the round (`failToSubmitCv()`).
     */
    uint256 public s_requestedToSubmitCvTimestamp;
    /**
     * @notice The time when the Merkle root was submitted on-chain.
     * @dev
     *   - Used to compute deadlines for subsequent phases, like “request or submit or fail” decisions.
     */
    uint256 public s_merkleRootSubmittedTimestamp;
    /**
     * @notice Tracks when the contract owner requested on-chain “Co” submissions (Reveal-1).
     * @dev
     *   - Relevant to the deadline for calling `submitCo()` or failing the round (`failToSubmitCo()`).
     */
    uint256 public s_requestedToSubmitCoTimestamp;
    /**
     * @notice The timestamp of the last S-submission request (Reveal-2) phase.
     * @dev
     *   - Used to enforce per-operator submission windows in `submitS()` or `failToSubmitS()`.
     */
    uint256 public s_previousSSubmitTimestamp;

    /**
     * @notice Maps each round (identified by its index) to its corresponding {RequestInfo}.
     * @dev
     *   - Stores essential data about who requested the randomness (consumer),
     *     when the round started, how much it cost, and the callback gas limit.
     *   - Updated when `requestRandomNumber()` is called.
     */
    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;

    /**
     * @notice An array of operator indices that must submit `Cv` on-chain for the current round,
     *         as requested by the contract owner. Stored when `requestToSubmitCv()` is called.
     */
    uint256[] public s_requestedToSubmitCvIndices;
    /**
     * @notice An array of operator indices that must submit `Co` (Reveal-1) on-chain for the current round,
     *         as requested by the contract owner. Populated by `requestToSubmitCo()`.
     */
    uint256[] public s_requestedToSubmitCoIndices;

    /**
     * @notice Tracks the reveal order index in `secrets` when `requestToSubmitS()` is called
     * @dev
     *   - Used in `submitS()` to verify if the current operator is next in line.
     */
    uint256 public s_requestedToSubmitSFromIndexK;

    /**
     * @notice The array of operator indices in strictly descending difference order (rv and Cvi).
     * @dev
     *   - Used in the final reveal phases to enforce the order of `S` submissions.
     */
    uint256[] public s_revealOrders;

    /**
     * @notice A packed bitmap mapping each round index to its “requested” status.
     * @dev
     *   - Each `uint248` key represents a 256-bit word in storage, where each bit indicates
     *     whether a round is requested (1) or not (0).
     *   - Managed with the `Bitmap` library (e.g., `flipBit()`).
     */
    mapping(uint248 wordPos => uint256) public s_roundBitmap;

    /**
     * @notice Tracks whether a Merkle root was submitted for the round identified by `timestamp`.
     * @dev
     *   - If `true`, indicates the leader node has called `submitMerkleRoot()` (or a similar function)
     *     for that round.
     *   - Used in verifying subsequent reveal phases can proceed.
     */
    mapping(uint256 timestamp => bool) public s_isSubmittedMerkleRoot;

    mapping(uint256 timestamp => uint256) public s_requestToSubmitCvBitmap;
    /**
     * @notice Stores a bitmap indicating which operators must submit `Co` (Reveal-1) for each round,
     *         keyed by that round’s `timestamp`.
     * @dev
     *   - If a bit is set, that operator has not yet submitted Co on-chain.
     *   - Cleared when an operator calls `submitCo()` successfully.
     */
    mapping(uint256 timestamp => uint256) public s_requestToSubmitCoBitmap;

    /**
     * @notice For each round (`timestamp`), stores an array of `Cv` commitments:
     *         - `s_cvs[timestamp][i]` is the hashed commitment (`Cv`) for operator `i`.
     */
    mapping(uint256 timestamp => bytes32[]) public s_cvs;

    /**
     * @notice For each round (`timestamp`), stores an array of final secrets (`S`):
     *         - `s_ss[timestamp][i]` is the revealed secret of operator `i`, if submitted on-chain.
     */
    mapping(uint256 timestamp => bytes32[]) public s_ss;

    // ** internal

    // uint256 internal s_fulfilledCount;

    /**
     * @notice The base duration (in seconds) for the off-chain submission phase before an on-chain action is required.
     * @dev
     *   - Used in combination with other timing values to compute the deadline for initiating commit or reveal phases.
     */
    uint256 internal s_offChainSubmissionPeriod;

    /**
     * @notice The time window (in seconds) the leader node has to decide whether to submit values or request submissions or fail the round
     *         after the off-chain period ends.
     * @dev
     *   - After `s_offChainSubmissionPeriod` elapses, the leader node can either submit values on-chain or request an on-chain submission or
     *     deem the process failed using a corresponding fail function.
     */
    uint256 internal s_requestOrSubmitOrFailDecisionPeriod;
    /**
     * @notice The duration (in seconds) allowed for on-chain submissions (e.g., `submitCv` or `submitCo`)
     *         after the decision phase starts.
     * @dev
     *   - If this period expires without the required on-chain submissions, the round can be failed, slashing the responsible party.
     */
    uint256 internal s_onChainSubmissionPeriod;
    /**
     * @notice The off-chain secret submission time allocated per operator.
     * @dev
     *   - For example, if 5 operators are involved, the total might be `s_offChainSubmissionPeriod
     *     + (5 * s_offChainSubmissionPeriodPerOperator)`.
     */
    uint256 internal s_offChainSubmissionPeriodPerOperator;

    /**
     * @notice The on-chain submission time allotted per operator for revealing secrets.
     * @dev
     *   - Similar to {s_offChainSubmissionPeriodPerOperator}, but for on-chain steps
     */
    uint256 internal s_onChainSubmissionPeriodPerOperator;

    // ** constant

    // uint256 internal constant MERKLEROOTSUB_RANDOMNUMGENERATE_GASUSED = 100000;
    uint256 internal constant MERKLEROOTSUB_CALLDATA_BYTES_SIZE = 68;
    // uint256 internal constant RANDOMNUMGENERATE_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    bytes32 internal constant MESSAGE_TYPEHASH = keccak256("Message(uint256 timestamp,bytes32 cv)");
    bytes32 internal constant MESSAGE_TYPEHASH_DIRECT =
        0x2c78ac8207d32e75916e1a710ea4ff41cec9726e3198a7a8fc85639fb274018a; // keccak256("Message(uint256 timestamp,bytes32 cv)");

    // *** functions gasUsed;
    uint256 internal constant FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITMERKLEROOTAFTERDISPUTE_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITCV_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITCO_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITS_GASUSED = 123;

    // *** functions calldata size;
    uint256 internal constant NO_CALLDATA_SIZE = 4;
}
