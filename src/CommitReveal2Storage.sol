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

    struct SigRS {
        bytes32 r;
        bytes32 s;
    }

    struct SecretAndSigRS {
        bytes32 secret;
        SigRS rs;
    }

    struct CvAndSigRS {
        bytes32 cv;
        SigRS rs;
    }

    // * Errors
    error ExceedCallbackGasLimit(); // 0x1cf7ab79
    error NotEnoughActivatedOperators(); // 0x77599fd9
    error InsufficientAmount(); // 0x5945ea56
    error NotActivatedOperator(); // 0x1b256530
    error MerkleVerificationFailed(); // 0x624dc351
    error InvalidSignatureS(); // 0xbf4bf5b8
    error InvalidSignature(); // 0x8baa579f
    error MerkleRootAlreadySubmitted(); // 0xa34402b2
    error AllSubmittedCv(); // 0x7d39a81b
    error TooEarly(); // 0x085de625
    error L1FeeEstimationFailed(); // 0xb75f34bf
    error TooLate(); // 0xecdd1c29
    error InvalidCo();
    error LengthExceedsMax(); // 0x12466af8
    error SignatureAndIndexDoNotMatch(); // 0x980c4296
    error InvalidIndex(); // 0x63df8171
    error DuplicateIndices(); // 0x7a69f8d3
    error WrongRevealOrder(); // 0xe3ae7cc0
    error InvalidS();
    error AllCvsNotSubmitted(); // 0xad029eb9
    error InvalidSecretLength(); // 0xe0767fa4
    error ShouldNotBeZero();
    error NotConsumer(); // 0x8c7dc13d
    error SRequested();
    error InvalidRound(); // 0xa2b52a54
    error AlreadyRefunded(); // 0xa85e6f1a
    error RandomNumGenerated();
    error AlreadySubmittedMerkleRoot();
    error AlreadyRequestedToSubmitS(); // 0x0d934196
    error AlreadyRequestedToSubmitCv(); // 0x899a05f2
    error AlreadyRequestedToSubmitCo(); // 0x13efcda2
    error CvNotRequested(); // 0xd3e6c959
    error MerkleRootNotSubmitted(); // 0x8e56b845
    error NotHalted(); // 0x78b19eb2
    error MerkleRootIsSubmitted(); // 0x22b9d231
    error AllCosNotSubmitted(); // 0x15467973
    error AllSubmittedCo();
    error ZeroLength(); // 0xbf557497
    error LeaderLowDeposit(); // 0xc0013a5a
    error CoNotRequested(); // 0x11974969
    error SNotRequested(); // 0x2d37f8d3
    error AlreadySubmittedS();
    error CvNotEqualDoubleHashS(); // 0x5bcc2334
    error ETHTransferFailed(); // 0xb12d13eb
    error RevealNotInDescendingOrder(); // 0x24f1948e
    error CvNotSubmitted(); // 0x03798920
    error CvNotEqualHashCo(); // 0x67b3c693

    // * Events
    event Status(uint256 curStartTime, uint256 curState); // 0x31a1adb447f9b6b89f24bf104f0b7a06975ad9f35670dbfaf7ce29190ec54762
    event MerkleRootSubmitted(uint256 startTime, bytes32 merkleRoot);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess); // 0x539d5cf812477a02d010f73c1704ff94bd28cfca386609a6b494561f64ee7f0a

    //event RequestedToSubmitCv(uint256 startTime, uint256[] indices);
    event RequestedToSubmitCv(uint256 startTime, uint256 packedIndices); // 0x18d0e75c02ebf9429b0b69ace609256eb9c9e12d5c9301a2d4a04fd7599b5cfc
    event RequestedToSubmitCo(uint256 startTime, uint256 packedIndices); // 0xa3be0347f45bfc2dee4a4ba1d73c735d156d2c7f4c8134c13f48659942996846
    event CvSubmitted(uint256 startTime, bytes32 cv, uint256 index);
    event CoSubmitted(uint256 startTime, bytes32 co, uint256 index); // 0x881e94fac6a4a0f5fbeeb59a652c0f4179a070b4e73db759ec4ef38e080eb4a8
    event RequestedToSubmitSFromIndexK(uint256 startTime, uint256 indexK); // 0x6f5c0fbf1eb0f90db5f97e1e5b4c0bc94060698d6f59c07e07695ddea198b778
    event SSubmitted(uint256 startTime, bytes32 s, uint256 index); // 0x1f2f0bf333e80ee899084dda13e87c0b04096ba331a8d993487a116d166947ec

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
    mapping(uint256 startTime => uint256) public s_requestedToSubmitCvTimestamp;
    uint256 public s_requestedToSubmitCvLength;
    uint256 public s_requestedToSubmitCvPackedIndices;
    uint256 public s_zeroBitIfSubmittedCvBitmap;
    bytes32[32] public s_cvs;

    mapping(uint256 startTime => uint256) public s_merkleRootSubmittedTimestamp;
    bytes32 public s_merkleRoot;

    mapping(uint256 startTime => uint256) public s_requestedToSubmitCoTimestamp;
    uint256 public s_requestedToSubmitCoLength;
    uint256 public s_requestedToSubmitCoPackedIndices;
    uint256 public s_zeroBitIfSubmittedCoBitmap;

    mapping(uint256 startTime => uint256) public s_previousSSubmitTimestamp;
    /**
     * @notice Tracks the reveal order index in `secrets` when `requestToSubmitS()` is called
     * @dev
     *   - Used in `submitS()` to verify if the current operator is next in line.
     */
    uint256 public s_requestedToSubmitSFromIndexK;
    /**
     * @notice For each round (`timestamp`), stores an array of final secrets (`S`):
     *         - `s_ss[timestamp][i]` is the revealed secret of operator `i`, if submitted on-chain.
     */
    bytes32[32] public s_secrets;
    /**
     * @notice The array of operator indices in strictly descending difference order (rv and Cvi).
     * @dev
     *   - Used in the final reveal phases to enforce the order of `S` submissions.
     */
    uint256 public s_packedRevealOrders;

    /**
     * @notice Maps each round (identified by its index) to its corresponding {RequestInfo}.
     * @dev
     *   - Stores essential data about who requested the randomness (consumer),
     *     when the round started, how much it cost, and the callback gas limit.
     *   - Updated when `requestRandomNumber()` is called.
     */
    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;

    /**
     * @notice A packed bitmap mapping each round index to its “requested” status.
     * @dev
     *   - Each `uint248` key represents a 256-bit word in storage, where each bit indicates
     *     whether a round is requested (1) or not (0).
     *   - Managed with the `Bitmap` library (e.g., `flipBit()`).
     */
    mapping(uint248 wordPos => uint256) public s_roundBitmap;

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
    uint256 internal constant MERKLEROOTSUB_CALLDATA_BYTES_SIZE = 36;
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

    function getCurStartTime() public view returns (uint256) {
        return s_requestInfo[s_currentRound].startTime;
    }
}
