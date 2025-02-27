// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CommitReveal2OnChain is Ownable {
    // *** Errors
    error NotEnoughActivatedOperators();
    error DepositLessThanActivationThreshold();
    error InsufficientAmount();
    error RevealNotInAscendingOrder();
    error NotTheFirstRevealer();
    error FirstReveal2NotCalled();
    error AlreadyCommitted();
    error CommitPhaseOver();
    error ReveaPhaseOver();
    error ReveaPhaseNotStarted();
    error Reveal2PhaseNotStarted();
    error ProtocolStillInProgress();

    // *** State Variables
    // ** public
    uint256 public s_requestFee;
    mapping(address operator => uint256 depositAmount) public s_depositAmount;

    uint256 public s_d;
    uint256 public s_canParticipateNum;
    uint256[] public s_cvs;
    bytes32[] public s_cos;
    bytes32[] public s_secrets;
    uint256[] public s_revealOrders;

    uint256 public s_commitDuration;
    uint256 public s_commitReveaDuration;
    uint256 public s_reveaStartTime;
    uint256 public s_reveal2StartTime;
    uint256 public s_round;
    bool public s_isRevealPhase;
    mapping(uint256 round => mapping(address operator => uint256 commitOrder))
        public s_commitOrders;
    mapping(uint256 round => uint256 randomNum) public s_randomNum;

    constructor(
        uint256 d,
        uint256 requestFee,
        uint256 commitDuration,
        uint256 reveaDuration
    ) Ownable(msg.sender) {
        s_d = d;
        s_requestFee = requestFee;
        s_commitDuration = commitDuration;
        s_commitReveaDuration = commitDuration + reveaDuration;
    }

    // *** For Consumers
    function requestRandomNumber() external payable {
        require(s_canParticipateNum > 1, NotEnoughActivatedOperators());
        require(msg.value >= s_requestFee, InsufficientAmount());
        require(s_secrets.length == s_cvs.length, ProtocolStillInProgress());
        s_depositAmount[owner()] += msg.value;
        s_reveaStartTime = block.timestamp + s_commitDuration;
        s_reveal2StartTime = block.timestamp + s_commitReveaDuration;
        unchecked {
            ++s_round;
        }
        delete s_cvs;
        delete s_cos;
        delete s_secrets;
        delete s_revealOrders;
        s_isRevealPhase = false;
    }

    // *** For Participants
    function commit(uint256 cv) external {
        require(
            s_depositAmount[msg.sender] >= s_d,
            DepositLessThanActivationThreshold()
        );
        mapping(address operator => uint256 commitOrder)
            storage commitOrders = s_commitOrders[s_round];
        require(commitOrders[msg.sender] == 0, AlreadyCommitted());
        require(block.timestamp < s_reveaStartTime, CommitPhaseOver());
        s_cvs.push(cv);
        commitOrders[msg.sender] = s_cvs.length;
    }

    function reveal1(bytes32 co) external {
        require(block.timestamp >= s_reveaStartTime, ReveaPhaseNotStarted());
        require(block.timestamp < s_reveal2StartTime, ReveaPhaseOver());
        uint256 commitIndex = s_commitOrders[s_round][msg.sender] - 1;
        require(keccak256(abi.encodePacked(co)) == bytes32(s_cvs[commitIndex]));
        if (!s_isRevealPhase) {
            s_isRevealPhase = true;
            s_cos = new bytes32[](s_cvs.length);
        }
        s_cos[commitIndex] = co;
    }

    function firstReveal2(
        bytes32 secret,
        uint256[] calldata revealOrders
    ) external {
        require(
            block.timestamp >= s_reveal2StartTime,
            Reveal2PhaseNotStarted()
        );
        // ** verify and save revealOrders
        uint256 rv = uint256(keccak256(abi.encodePacked(s_cos)));
        uint256 commitLength = s_cvs.length;
        for (uint256 i = 1; i < commitLength; i = unchecked_inc(i)) {
            require(
                efficientKeccak256(diff(rv, s_cvs[revealOrders[i - 1]])) >
                    efficientKeccak256(diff(rv, s_cvs[revealOrders[i]])),
                RevealNotInAscendingOrder()
            );
        }
        s_revealOrders = revealOrders;

        // ** reveal2
        uint256 firstRevealOrder = revealOrders[0];
        require(
            firstRevealOrder == s_commitOrders[s_round][msg.sender] - 1,
            NotTheFirstRevealer()
        );
        require(
            keccak256(abi.encodePacked(secret)) ==
                bytes32(s_cos[firstRevealOrder])
        );
        s_secrets.push(secret);
    }

    function reveal2(bytes32 secret) external {
        uint256 secretLength = s_secrets.length;
        require(secretLength > 0, FirstReveal2NotCalled());
        uint256 commitIndex = s_commitOrders[s_round][msg.sender] - 1;
        require(
            s_revealOrders[secretLength] == commitIndex,
            RevealNotInAscendingOrder()
        );
        require(
            keccak256(abi.encodePacked(secret)) == bytes32(s_cos[commitIndex])
        );
        s_secrets.push(secret);
        if (secretLength + 1 == s_cvs.length) {
            s_randomNum[s_round] = uint256(
                keccak256(abi.encodePacked(s_secrets))
            );
        }
    }

    function diff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function efficientKeccak256(
        uint256 a
    ) private pure returns (uint256 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            value := keccak256(0x00, 0x20)
        }
    }

    function deposit() external payable {
        uint256 depositAmount = s_depositAmount[msg.sender];
        uint256 d = s_d;
        unchecked {
            if (
                (s_depositAmount[msg.sender] += msg.value) >= d &&
                depositAmount < d
            ) ++s_canParticipateNum;
        }
    }

    function withdraw(uint256 amount) external {
        uint256 depositAmount = s_depositAmount[msg.sender];
        uint256 d = s_d;
        unchecked {
            if (
                (s_depositAmount[msg.sender] -= amount) < s_d &&
                depositAmount >= d
            ) --s_canParticipateNum;
        }
        payable(msg.sender).transfer(amount);
    }

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }
}
