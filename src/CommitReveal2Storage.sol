// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract CommitReveal2Storage {
    // * Type Declarations
    /**
     * @notice Represents a commitment message containing a timestamp and a commitment value (`cv`).
     * @dev
     *   - Used in EIP-712 typed data hashing (see `MESSAGE_TYPEHASH`) for operator signatures.
     *   - `round`
     *   - `trialNum` indicates the trial number of the round.
     *   - `cv` is a double hashed value of operator secret
     */
    struct Message {
        uint256 round;
        uint256 trialNum;
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
    error CvNotRequestedForThisOperator(); // 0x998cf22e
    error NotActivatedOperator(); // 0x1b256530
    error MerkleVerificationFailed(); // 0x624dc351
    error InvalidSignatureS(); // 0xbf4bf5b8
    error SubmitAfterStartTime(); // 0xc2794058
    error InvalidSignature(); // 0x8baa579f
    error MerkleRootAlreadySubmitted(); // 0xa34402b2
    error CannotRequestWhenHalted(); // 0x2caa910c
    error AllSubmittedCv(); // 0x7d39a81b
    error TooEarly(); // 0x085de625
    error OnChainCvNotEqualDoubleHashS(); // 0xa39ecadf
    error L1FeeEstimationFailed(); // 0xb75f34bf
    error TooLate(); // 0xecdd1c29
    error RoundAlreadyProcessed(); // 0x5cafea8c
    error NonExistentRound(); // 0x905deff6
    error TooManyRequestsQueued(); // 0x02cd147b
    error AlreadyHalted(); // 0xd6c912e6
    error NoCvsOnChain(); // 0x96fbee7b
    error LengthExceedsMax(); // 0x12466af8
    error SignatureAndIndexDoNotMatch(); // 0x980c4296
    error InvalidIndex(); // 0x63df8171
    error NewOwnerCannotBeActivatedOperator(); // 0x9279dd8e
    error DuplicateIndices(); // 0x7a69f8d3
    error WrongRevealOrder(); // 0xe3ae7cc0
    error RevealOrderHasDuplicates(); // 0x06efcba4
    error AllCvsNotSubmitted(); // 0xad029eb9
    error InvalidSecretLength(); // 0xe0767fa4
    error NotConsumer(); // 0x8c7dc13d
    error SRequested(); // 0x53489cf9
    error AlreadyRefunded(); // 0xa85e6f1a
    error AlreadyCompleted(); // 0x195332a5
    error RandomNumGenerated(); // 0xd51a29b7
    error AlreadySubmittedMerkleRoot(); // 0x1c044d8b
    error AlreadyRequestedToSubmitS(); // 0x0d934196
    error AlreadyRequestedToSubmitCv(); // 0x899a05f2
    error AlreadyRequestedToSubmitCo(); // 0x13efcda2
    error CvNotRequested(); // 0xd3e6c959
    error MerkleRootNotSubmitted(); // 0x8e56b845
    error NotHalted(); // 0x78b19eb2
    error MerkleRootIsSubmitted(); // 0x22b9d231
    error AllCosNotSubmitted(); // 0x15467973
    error AllSubmittedCo(); // 0x1c7f7cc9
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
    event Status(uint256 curRound, uint256 curTrialNum, uint256 curState); // 0xd42cacab4700e77b08a2d33cc97d95a9cb985cdfca3a206cfa4990da46dd1813
    event MerkleRootSubmitted(uint256 round, uint256 trialNum, bytes32 merkleRoot); // 0x45b19880b523c6750f7f39fca8d77d51101b315495adc482994a4fa2a8294466

    event RequestedToSubmitCv(uint256 round, uint256 trialNum, uint256 packedIndicesAscendingFromLSB); // 0x16759d80d11394de93184cfeb4e91cf57282cef239f68ed141c496600454f757
    event RequestedToSubmitCo(uint256 round, uint256 trialNum, uint256 indicesLength, uint256 packedIndices); // 0xd4cc5cd95f180f10aaacba0729abc069b8080ec3a7e8e41856decb17bdc28ece
    event CvSubmitted(uint256 round, uint256 trialNum, bytes32 cv, uint256 index); // 0x6a6385c5eaed19d346ec4f9bd0010cfba4ac1d0407e2e55f959cb8fcac30f873
    event CoSubmitted(uint256 round, uint256 trialNum, bytes32 co, uint256 index); // 0xc294138987faa6e0ebef350caeac5cf5e1eff8dbbe8a158e421601f48674babd
    event RequestedToSubmitSFromIndexK(uint256 round, uint256 trialNum, uint256 indexK); // 0x583f939e9612a50da8a140b5e7247ff7c3c899c45e4051a5ba045abea6177f08
    event SSubmitted(uint256 round, uint256 trialNum, bytes32 s, uint256 index); // 0xfa070a58e2c77080acd5c2b1819669eb194bbeeca6f680a31a2076510be5a7b1

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
     *   - Used to track which request is "active" for on-chain commit/reveal phases.
     */
    uint256 public s_currentRound;

    /**
     * @notice The total number of requests ever made (incremented each time `requestRandomNumber()` is called).
     * @dev
     *   - Each request is identified by a "round" index in [0..s_requestCount-1].
     *   - Used to ensure newly created round indices are unique and sequential.
     */
    uint256 public s_requestCount;

    mapping(uint256 round => uint256 trialNum) public s_trialNum;

    /**
     * @notice Stores the latest submitted Merkle root for the current round.
     * @dev
     *   - Used to validate operator commitments in the chain of trust for reveal phases.
     *   - Updated by the leader node via `submitMerkleRoot()`.
     */
    mapping(uint256 round => mapping(uint256 trialNum => uint256)) public s_requestedToSubmitCvTimestamp;
    uint256 public s_requestedToSubmitCvPackedIndicesAscFromLSB;
    uint256 public s_bitSetIfRequestedToSubmitCv_zeroBitIfSubmittedCv_bitmap128x2;
    bytes32[32] public s_cvs;
    bytes32[32] public s_cos;

    mapping(uint256 round => mapping(uint256 trialNum => uint256)) public s_merkleRootSubmittedTimestamp;
    bytes32 public s_merkleRoot;

    mapping(uint256 round => mapping(uint256 trialNum => uint256)) public s_requestedToSubmitCoTimestamp;
    uint256 public s_requestedToSubmitCoLength;
    uint256 public s_requestedToSubmitCoPackedIndices;
    uint256 public s_zeroBitIfSubmittedCoBitmap;

    mapping(uint256 round => mapping(uint256 trialNum => uint256)) public s_previousSSubmitTimestamp;
    /**
     * @notice Tracks the reveal order index in `secrets` when `requestToSubmitS()` is called
     * @dev
     *   - Used in `submitS()` to verify if the current operator is next in line.
     */
    uint256 public s_requestedToSubmitSFromIndexK;

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
     * @notice A packed bitmap mapping each round index to its "requested" status.
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
    uint256 internal constant GENRANDNUM_CALLDATA_BYTES_SIZE_A = 96;
    uint256 internal constant GENRANDNUM_CALLDATA_BYTES_SIZE_B = 132;
    uint256 internal constant GASUSED_MERKLEROOTSUB_GENRANDNUM_A = 3932;
    uint256 internal constant GASUSED_MERKLEROOTSUB_GENRANDNUM_B = 131509;

    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    bytes32 internal constant MESSAGE_TYPEHASH = keccak256("Message(uint256 round,uint256 trialNum,bytes32 cv)");
    bytes32 internal constant MESSAGE_TYPEHASH_DIRECT =
        0x7c90823f4ccd06a00814473b1ad932d6313680c6d946963ecf1d30094346c24e; // keccak256("Message(uint256 round,uint256 trialNum,bytes32 cv)");

    // *** functions gasUsed;
    uint256 internal constant FAIL_FUNCTIONS_CALLDATA_BYTES_SIZE = 4;
    // 21833 ~ 21934
    uint256 internal constant GETL1UPPERBOUND_GASUSED_CALLDATASIZE4 = 21833;
    uint256 internal constant FAILTOREQUESTSUBMITCVORSUBMITMERKLEROOT_GASUSED = 85386;
    uint256 internal constant FAILTOSUBMITMERKLEROOTAFTERDISPUTE_GASUSED = 82746;
    uint256 internal constant FAILTOREQUESTSORGENERATERANDOMNUMBER_GASUSED = 86242;

    /**
     * @dev  FailToSubmitCo GasUsed
     * if (requestedToSubmitLength == operatorsLength):
     * gasUsage = 95,000 + 500 × operatorsLength + 15,000 × (didntSubmitLength - 1)
     * else:
     * gasUsage = 110,000 + 200 × operatorsLength + 500 × requestedToSubmitLength +
     *            24,000 × (didntSubmitLength - 1)
     */
    uint256 internal constant FAILTOSUBMITCO_GASUSED_BASE_A = 95000;

    /**
     * @dev  FailToSubmitCv GasUsed
     * if (requestedToSubmitLength == operatorsLength):
     * gasUsage = 95,500 + 500 × operatorsLength + 15,000 × (didntSubmitLength - 1)
     * else:
     * gasUsage = 110,000 + 200 × operatorsLength + 500 × requestedToSubmitLength +
     *            24,000 × (didntSubmitLength - 1)
     */
    uint256 internal constant FAILTOSUBMITCV_GASUSED_BASE_A = 95500;

    uint256 internal constant FAILTOSUBMIT_GASUSED_BASE_B = 110000;
    uint256 internal constant PER_OPERATOR_INCREASE_GASUSED_A = 500;
    uint256 internal constant PER_OPERATOR_INCREASE_GASUSED_B = 200;
    uint256 internal constant PER_ADDITIONAL_DIDNTSUBMIT_A = 15000;
    uint256 internal constant PER_ADDITIONAL_DIDNTSUBMIT_B = 24000;
    uint256 internal constant PER_REQUESTED_INCREASE_GASUSED = 500;

    uint256 internal constant FAILTOSUBMITS_GASUSED = 122282;

    // *** functions calldata size;
    uint256 internal constant NO_CALLDATA_SIZE = 4;

    function getPeriods()
        external
        view
        returns (
            uint256 offChainSubmissionPeriod,
            uint256 requestOrSubmitOrFailDecisionPeriod,
            uint256 onChainSubmissionPeriod,
            uint256 offChainSubmissionPeriodPerOperator,
            uint256 onChainSubmissionPeriodPerOperator
        )
    {
        return (
            s_offChainSubmissionPeriod,
            s_requestOrSubmitOrFailDecisionPeriod,
            s_onChainSubmissionPeriod,
            s_offChainSubmissionPeriodPerOperator,
            s_onChainSubmissionPeriodPerOperator
        );
    }

    function getMerkleRoot(uint256 round, uint256 trialNum) external view returns (bytes32, bool) {
        if (s_merkleRootSubmittedTimestamp[round][trialNum] == 0) {
            return (bytes32(0), false);
        }
        return (s_merkleRoot, true);
    }

    function getCurStartTime() public view returns (uint256) {
        return s_requestInfo[s_currentRound].startTime;
    }

    function getCurRoundAndStartTime() external view returns (uint256, uint256) {
        uint256 curRound = s_currentRound;
        return (curRound, s_requestInfo[curRound].startTime);
    }

    function getCurRoundAndTrialNum() external view returns (uint256, uint256) {
        uint256 curRound = s_currentRound;
        return (curRound, s_trialNum[curRound]);
    }

    function getZeroBitIfSubmittedCvOnChainBitmap() external view returns (uint256) {
        uint256 curRound = s_currentRound;
        uint256 requestedToSubmitCvTimestamp = s_requestedToSubmitCvTimestamp[curRound][s_trialNum[curRound]];
        if (requestedToSubmitCvTimestamp == 0) {
            return 0xffffffff;
        }
        return s_bitSetIfRequestedToSubmitCv_zeroBitIfSubmittedCv_bitmap128x2 & 0xffffffff;
    }

    function getZeroBitIfSubmittedCoOnChainBitmap() external view returns (uint256) {
        uint256 curRound = s_currentRound;
        uint256 requestedToSubmitCoTimestamp = s_requestedToSubmitCoTimestamp[curRound][s_trialNum[curRound]];
        if (requestedToSubmitCoTimestamp == 0) {
            return 0xffffffff;
        }
        return s_zeroBitIfSubmittedCoBitmap;
    }

    function getSecrets(uint256 length) external view returns (bytes32[] memory secrets) {
        secrets = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            secrets[i] = s_secrets[i];
        }
        return secrets;
    }

    function getDisputeInfos(uint256 round, uint256 trialNum)
        external
        view
        returns (
            uint256 requestedToSubmitCvTimestamp,
            uint256 requestedToSubmitCvPackedIndicesAscFromLSB,
            uint256 zeroBitIfSubmittedCvBitmap,
            uint256 requestedToSubmitCoTimestamp,
            uint256 requestedToSubmitCoPackedIndices,
            uint256 requestedToSubmitCoLength,
            uint256 zeroBitIfSubmittedCoBitmap,
            uint256 previousSSubmitTimestamp,
            uint256 packedRevealOrders,
            uint256 requestedToSubmitSFromIndexK
        )
    {
        requestedToSubmitCvTimestamp = s_requestedToSubmitCvTimestamp[round][trialNum];
        requestedToSubmitCvPackedIndicesAscFromLSB = s_requestedToSubmitCvPackedIndicesAscFromLSB;
        zeroBitIfSubmittedCvBitmap = s_bitSetIfRequestedToSubmitCv_zeroBitIfSubmittedCv_bitmap128x2;
        requestedToSubmitCoTimestamp = s_requestedToSubmitCoTimestamp[round][trialNum];
        requestedToSubmitCoPackedIndices = s_requestedToSubmitCoPackedIndices;
        requestedToSubmitCoLength = s_requestedToSubmitCoLength;
        zeroBitIfSubmittedCoBitmap = s_zeroBitIfSubmittedCoBitmap;
        previousSSubmitTimestamp = s_previousSSubmitTimestamp[round][trialNum];
        packedRevealOrders = s_packedRevealOrders;
        requestedToSubmitSFromIndexK = s_requestedToSubmitSFromIndexK;
    }

    function getDisputeTimestamps(uint256 round, uint256 trialNum)
        external
        view
        returns (
            uint256 requestedToSubmitCvTimestamp,
            uint256 requestedToSubmitCoTimestamp,
            uint256 previousSSubmitTimestamp
        )
    {
        requestedToSubmitCvTimestamp = s_requestedToSubmitCvTimestamp[round][trialNum];
        requestedToSubmitCoTimestamp = s_requestedToSubmitCoTimestamp[round][trialNum];
        previousSSubmitTimestamp = s_previousSSubmitTimestamp[round][trialNum];
    }
}
