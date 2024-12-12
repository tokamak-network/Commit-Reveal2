// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitReveal2StorageL2 {
    struct Message {
        uint256 round;
        bytes32 cv;
    }

    // * Type Declarations
    struct RequestInfo {
        address consumer;
        uint256 requestedTime;
        uint256 cost;
        uint256 callbackGasLimit;
    }

    struct RoundInfo {
        bytes32 merkleRoot;
        uint256 randomNumber;
        bool fulfillSucceeded;
    }

    // * Errors
    error LessThanActivationThreshold();
    error AlreadyActivated();
    error OperatorNotActivated();
    error AlreadyForceDeactivated();
    error ExceedCallbackGasLimit();
    error ActivatedOperatorsLimitReached();
    error NotEnoughActivatedOperators();
    error NotEnoughParticipatedOperators();
    error InsufficientAmount();
    error RevealNotInAscendingOrder();
    error NotActivatedOperatorForThisRound();
    error MerkleVerificationFailed();
    error InvalidSignatureS();
    error InvalidSignature();
    error InvalidSignatureLength();

    // * Events
    event Activated(address operator);
    event DeActivated(address operator);
    event RandomNumberRequested(uint256 round, address[] activatedOperators);
    event MerkleRootSubmitted(uint256 round, bytes32 merkleRoot);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber);

    // * State Variables
    // ** public
    uint256 public s_activationThreshold;
    uint256 public s_flatFee;
    uint256 public s_maxActivatedOperators;
    mapping(uint256 round => RoundInfo roundInfo) public s_roundInfo;
    mapping(address operator => uint256 depositAmount) public s_depositAmount;
    mapping(address operator => uint256) public s_activatedOperatorOrder;
    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;
    mapping(uint256 round => address[] activatedOperators)
        internal s_activatedOperatorsAtRound;
    mapping(uint256 round => mapping(address operator => uint256))
        public s_activatedOperatorOrderAtRound;
    // ** internal
    uint256 internal s_nextRound;

    address[] internal s_activatedOperators;

    // ** constant
    // uint256 internal constant MERKLEROOTSUB_RANDOMNUMGENERATE_GASUSED = 100000;
    uint256 internal constant MERKLEROOTSUB_CALLDATA_BYTES_SIZE = 68;
    // uint256 internal constant RANDOMNUMGENERATE_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    bytes32 internal constant MESSAGE_TYPEHASH =
        keccak256("Message(uint256 round,bytes32 cv)");

    // ** getter
    // s_activatedOperators
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length;
    }

    // s_activatedOperatorsAtRound
    function getActivatedOperatorsAtRound(
        uint256 round
    ) external view returns (address[] memory) {
        return s_activatedOperatorsAtRound[round];
    }

    function getActivatedOperatorsAtRoundLength(
        uint256 round
    ) external view returns (uint256) {
        return s_activatedOperatorsAtRound[round].length;
    }
}
