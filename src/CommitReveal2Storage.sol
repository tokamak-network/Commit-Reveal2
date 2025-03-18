// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitReveal2Storage {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Message {
        uint256 timestamp;
        bytes32 cv;
    }

    // * Type Declarations
    struct RequestInfo {
        address consumer;
        uint256 startTime;
        uint256 cost;
        uint256 callbackGasLimit;
    }

    // * Errors

    error OperatorNotActivated();
    error ExceedCallbackGasLimit();
    error NotEnoughActivatedOperators();
    error InsufficientAmount();
    error NotActivatedOperator();
    error MerkleVerificationFailed();
    error InvalidSignatureS();
    error InvalidSignature();
    error InvalidSignatureLength();
    error TooEarly();
    error TooLate(); // 0xecdd1c29
    error InvalidCo();
    error InvalidS();
    error InvalidRevealOrder();
    error InvalidSecretLength(); // 0xe0767fa4
    error ShouldNotBeZero();
    error NotConsumer();
    error InvalidRound();
    error AlreadyRefunded();
    error AlreadySubmittedMerkleRoot();
    error AlreadyRequestedToSubmitCv();
    error CvNotRequested();
    error MerkleRootNotSubmitted();
    error NotHalted();
    error ZeroLength();
    error LeaderLowDeposit();
    error CoNotRequested();
    error SNotRequested();
    error AlreadySubmittedS();
    error ETHTransferFailed(); // 0xb12d13eb
    error RevealNotInDescendingOrder(); // 0x24f1948e

    error CvNotSubmitted(uint256 index);

    // * Events

    event RandomNumberRequested(uint256 round, uint256 timestamp, address[] activatedOperators);
    event MerkleRootSubmitted(uint256 timestamp, bytes32 merkleRoot);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess);

    event RequestedToSubmitCv(uint256 timestamp, uint256[] indices);
    event RequestedToSubmitCo(uint256 timestamp, uint256[] indices);
    event CvSubmitted(uint256 timestamp, bytes32 cv, uint256 index);
    event CoSubmitted(uint256 timestamp, bytes32 co, uint256 index);
    event RequestedToSubmitSFromIndexK(uint256 timestamp, uint256 index);
    event SSubmitted(uint256 timestamp, bytes32 s, uint256 index);
    event IsInProcess(uint256 isInProcess);

    // * State Variables
    // ** public

    uint256 public s_flatFee;

    uint256 public s_currentRound;
    uint256 public s_requestCount;
    uint256 public s_lastfulfilledRound;

    bytes32 public s_merkleRoot;

    uint256 public s_requestedToSubmitCvTimestamp;
    uint256 public s_merkleRootSubmittedTimestamp;
    uint256 public s_requestedToSubmitCoTimestamp;
    uint256 public s_previousSSubmitTimestamp;

    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;

    uint256[] public s_requestedToSubmitCvIndices;
    uint256[] public s_requestedToSubmitCoIndices;
    uint256 public s_requestedToSubmitSFromIndexK;
    uint256[] public s_revealOrders;

    mapping(uint248 wordPos => uint256) public s_roundBitmap;

    mapping(uint256 timestamp => bool) public s_isSubmittedMerkleRoot;
    mapping(uint256 timestamp => uint256) public s_requestToSubmitCoBitmap;
    mapping(uint256 timestamp => bytes32[]) public s_cvs;
    mapping(uint256 timestamp => bytes32[]) public s_ss;

    // ** internal

    // uint256 internal s_fulfilledCount;

    uint256 internal s_offChainSubmissionPeriod;
    uint256 internal s_requestOrSubmitOrFailDecisionPeriod;
    uint256 internal s_onChainSubmissionPeriod;
    uint256 internal s_offChainSubmissionPeriodPerOperator;
    uint256 internal s_onChainSubmissionPeriodPerOperator;

    // ** constant

    // uint256 internal constant MERKLEROOTSUB_RANDOMNUMGENERATE_GASUSED = 100000;
    uint256 internal constant MERKLEROOTSUB_CALLDATA_BYTES_SIZE = 68;
    // uint256 internal constant RANDOMNUMGENERATE_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    bytes32 internal constant MESSAGE_TYPEHASH = keccak256("Message(uint256 timestamp,bytes32 cv)");

    // *** functions gasUsed;
    uint256 internal constant FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITMERKLEROOTAFTERDISPUTE_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITCV_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITCO_GASUSED = 123;
    uint256 internal constant FAILTOSUBMITS_GASUSED = 123;

    // *** functions calldata size;
    uint256 internal constant NO_CALLDATA_SIZE = 4;
}
