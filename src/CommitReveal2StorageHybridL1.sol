// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitReveal2StorageHybridL1 {
    // *** Type Declarations
    struct Message {
        uint256 round;
        bytes32 cv;
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

    // *** State Variables
    // ** public
    uint256 public s_requestFee;
    mapping(address operator => uint256 depositAmount) public s_depositAmount;

    uint256 public s_activationThreshold;
    mapping(address operator => uint256) public s_activatedOperatorOrder;
    address[] internal s_activatedOperators;
    bytes32 public s_merkleRoot;
    uint256 public s_round;
    bool public s_isStarted;
    mapping(uint256 round => uint256 randomNum) public s_randomNum;
    // ** internal

    // *constants
    bytes32 internal constant MESSAGE_TYPEHASH =
        keccak256("Message(uint256 round,bytes32 cv)");
}
