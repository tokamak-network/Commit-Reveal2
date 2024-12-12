// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitReveal2StorageL1 {
    // *** Type Declarations

    // *** Errors
    error NotEnoughActivatedOperators();
    error DepositLessThanActivationThreshold();
    error InsufficientAmount();
    error RevealNotInAscendingOrder();
    error NotTheFirstRevealer();
    error FirstReveal2NotCalled();
    error AlreadyCommitted();
    error CommitPhaseOver();
    error Reveal1PhaseOver();
    error Reveal1PhaseNotStarted();
    error Reveal2PhaseNotStarted();
    error StillInProgress();

    // *** Events
    event RandomNumberRequested();

    // *** State Variables
    // ** public
    // * service variables
    uint256 public s_requestFee;
    mapping(address operator => uint256 depositAmount) public s_depositAmount;

    // * protocol variables
    uint256 public s_activationThreshold;
    uint256 public s_activatedNum;
    uint256[] public s_cvs;
    bytes32[] public s_cos;
    bytes32[] public s_secrets;
    uint256[] public s_revealOrders;

    // * phase variables
    uint256 public s_commitDuration;
    uint256 public s_commitReveal1Duration;
    uint256 public s_reveal1StartTime;
    uint256 public s_reveal2StartTime;
    uint256 public s_requestId;
    bool public s_isRevealPhase;
    mapping(uint256 requestId => mapping(address operator => uint256 commitOrder))
        public s_commitOrders;
    mapping(uint256 requestId => uint256 randomNum) public s_randomNum;
}
