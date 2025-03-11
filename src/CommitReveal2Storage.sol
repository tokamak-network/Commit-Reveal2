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
    error LessThanActivationThreshold();
    error AlreadyActivated();
    error OperatorNotActivated();
    error ExceedCallbackGasLimit();
    error ActivatedOperatorsLimitReached();
    error NotEnoughActivatedOperators();
    error InsufficientAmount();
    error NotActivatedOperator();
    error MerkleVerificationFailed();
    error InvalidSignatureS();
    error InvalidSignature();
    error InvalidSignatureLength();
    error InProcess();
    error TooEarly();
    error TooLate();
    error InvalidCO();
    error InvalidS();
    error InvalidRevealOrder();
    error InvalidSecretLength();
    error ShouldNotBeZero();
    error NotConsumer();
    error TransferFailed();
    error InvalidRound();
    error AlreadyRefunded();
    error AlreadySubmittedMerkleRoot();
    error AlreadyRequestedToSubmitCV();
    error CVNotRequested();
    error MerkleRootNotSubmitted();
    error CVNotSubmitted(uint256 index);

    // * Events
    event Activated(address operator);
    event DeActivated(address operator);
    event RandomNumberRequested(
        uint256 round,
        uint256 timestamp,
        address[] activatedOperators
    );
    event MerkleRootSubmitted(uint256 timestamp, bytes32 merkleRoot);
    event RandomNumberGenerated(
        uint256 round,
        uint256 randomNumber,
        bool callbackSuccess
    );

    event RequestedToSubmitCV(uint256 timestamp, uint256[] indices);
    event RequestedToSubmitCO(uint256 timestamp, uint256[] indices);
    event CVSubmitted(uint256 timestamp, bytes32 cv, uint256 index);
    event COSubmitted(uint256 timestamp, bytes32 co, uint256 index);
    event RequestedToSubmitSFromIndexK(uint256 timestamp, uint256 index);
    event SSubmitted(uint256 timestamp, bytes32 s, uint256 index);
    event IsInProcess(uint256 isInProcess);

    // * State Variables
    // ** public
    uint256 public s_activationThreshold;
    uint256 public s_flatFee;
    uint256 public s_maxActivatedOperators;
    uint256 public s_currentRound;
    uint256 public s_requestCount;
    uint256 public s_lastfulfilledRound;

    bytes32 public s_merkleRoot;
    uint256 public s_isInProcess = NOT_IN_PROGRESS;

    uint256 public s_requestedToSubmitCVTimestamp;
    uint256 public s_merkleRootSubmittedTimestamp;
    uint256 public s_requestedToSubmitCOTimestamp;
    uint256 public s_previousSSubmitTimestamp;

    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;

    uint256[] public s_requestedToSubmitCVIndices;
    uint256[] public s_requestedToSubmitCOIndices;
    uint256 public s_requestedToSubmitSFromIndexK;
    uint256[] public s_revealOrders;

    mapping(uint248 wordPos => uint256) public s_roundBitmap;

    mapping(uint256 timestamp => bool) public s_isSubmittedMerkleRoot;
    mapping(uint256 timestamp => bytes32[]) public s_cvs;
    mapping(uint256 timestamp => bytes32[]) public s_ss;
    mapping(address operator => uint256) public s_depositAmount;
    mapping(address operator => uint256) public s_activatedOperatorIndex1Based;

    // ** internal

    // uint256 internal s_fulfilledCount;

    address[] internal s_activatedOperators;

    uint256 internal s_offChainSubmissionPeriod;
    uint256 internal s_requestOrSubmitOrFailDecisionPeriod;
    uint256 internal s_onChainSubmissionPeriod;
    uint256 internal s_offChainSubmissionPeriodPerOperator;
    uint256 internal s_onChainSubmissionPeriodPerOperator;

    // ** constant
    uint256 internal constant NOT_IN_PROGRESS = 1;
    uint256 internal constant IN_PROGRESS = 2;
    // uint256 internal constant MERKLEROOTSUB_RANDOMNUMGENERATE_GASUSED = 100000;
    uint256 internal constant MERKLEROOTSUB_CALLDATA_BYTES_SIZE = 68;
    // uint256 internal constant RANDOMNUMGENERATE_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    bytes32 internal constant MESSAGE_TYPEHASH =
        keccak256("Message(uint256 timestamp,bytes32 cv)");

    // ** getter
    // s_activatedOperators
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length;
    }
}
