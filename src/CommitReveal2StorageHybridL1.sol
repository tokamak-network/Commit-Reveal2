// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitReveal2StorageHybridL1 {
    // *** Type Declarations
    struct Message {
        uint256 round;
        bytes32 cv;
    }

    struct RequestInfo {
        address consumer;
        uint256 cost;
        uint256 callbackGasLimit;
    }

    struct RoundInfo {
        bytes32 merkleRoot;
        uint256 randomNumber;
    }

    // *** Errors
    error ExceedCallbackGasLimit();
    error NotEnoughActivatedOperators();
    error InsufficientAmount();
    error NotActivatedOperatorForThisRound();
    error NotEnoughParticipatedOperators();
    error RevealNotInAscendingOrder();
    error MerkleVerificationFailed();
    error InvalidSignatureS();
    error InvalidSignature();
    error LessThanActivationThreshold();
    error AlreadyActivated();
    error ActivatedOperatorsLimitReached();
    error OperatorNotActivated();

    // // *** Events
    // event RandomNumberRequested(uint256 round, address[] activatedOperators);
    // event MerkleRootSubmitted(uint256 round, bytes32 merkleRoot);
    // event RandomNumberGenerated(
    //     uint256 round,
    //     uint256 randomNumber,
    //     bool callbackSucceeded
    // );
    // event Activated(address operator);
    // event DeActivated(address operator);

    // *** State Variables
    // ** public
    uint256 public s_activationThreshold;
    uint256 public s_flatFee;
    uint256 public s_maxActivatedOperators;
    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;
    mapping(address operator => uint256 depositAmount) public s_depositAmount;
    mapping(uint256 round => address[] activatedOperators)
        internal s_activatedOperatorsAtRound;
    mapping(uint256 round => RoundInfo roundInfo) public s_roundInfo;
    mapping(address operator => uint256) public s_activatedOperatorOrder;

    // ** internal
    address[] internal s_activatedOperators;
    uint256 internal s_nextRound;
    mapping(uint256 round => mapping(address operator => uint256))
        public s_activatedOperatorOrderAtRound;

    // *constants
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    bytes32 internal constant MESSAGE_TYPEHASH =
        keccak256("Message(uint256 round,bytes32 cv)");
}
