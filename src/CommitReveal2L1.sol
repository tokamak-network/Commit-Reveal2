// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2StorageL1} from "./CommitReveal2StorageL1.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CommitReveal2L1 is Ownable, CommitReveal2StorageL1 {
    constructor(
        uint256 activationThreshold,
        uint256 requestFee,
        uint256 commitDuration,
        uint256 reveal1Duration
    ) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_requestFee = requestFee;
        s_commitDuration = commitDuration;
        s_commitReveal1Duration = commitDuration + reveal1Duration;
    }

    // *** For Consumers
    function requestRandomNumber() external payable {
        require(s_activatedNum > 1, NotEnoughActivatedOperators());
        require(msg.value >= s_requestFee, InsufficientAmount());
        require(s_secrets.length == s_cvs.length, StillInProgress());
        s_depositAmount[owner()] += msg.value;
        s_reveal1StartTime = block.timestamp + s_commitDuration;
        s_reveal2StartTime = block.timestamp + s_commitReveal1Duration;
        unchecked {
            ++s_requestId;
        }
        delete s_cvs;
        delete s_cos;
        delete s_secrets;
        delete s_revealOrders;
        s_isRevealPhase = false;
        emit RandomNumberRequested();
    }

    // *** For Operators
    function commit(uint256 cv) external {
        mapping(address operator => uint256 commitOrder)
            storage commitOrders = s_commitOrders[s_requestId];
        require(
            s_depositAmount[msg.sender] >= s_activationThreshold,
            DepositLessThanActivationThreshold()
        );
        require(commitOrders[msg.sender] == 0, AlreadyCommitted());
        require(block.timestamp < s_reveal1StartTime, CommitPhaseOver());
        s_cvs.push(cv);
        commitOrders[msg.sender] = s_cvs.length;
    }

    function reveal1(bytes32 co) external {
        require(
            block.timestamp >= s_reveal1StartTime,
            Reveal1PhaseNotStarted()
        );
        require(block.timestamp < s_reveal2StartTime, Reveal1PhaseOver());
        uint256 commitOrder = s_commitOrders[s_requestId][msg.sender] - 1;
        require(keccak256(abi.encodePacked(co)) == bytes32(s_cvs[commitOrder]));
        if (!s_isRevealPhase) {
            s_isRevealPhase = true;
            s_cos = new bytes32[](s_cvs.length);
        }
        s_cos[commitOrder] = co;
    }

    function firstReveal2(
        bytes32 secret,
        uint256[] calldata revealOrders
    ) external {
        require(
            block.timestamp >= s_reveal2StartTime,
            Reveal2PhaseNotStarted()
        );
        // ** verify revealOrders
        uint256 rv = uint256(keccak256(abi.encodePacked(s_cos)));
        uint256 commitLength = s_cvs.length;
        for (uint256 i = 1; i < commitLength; i = unchecked_inc(i)) {
            require(
                diff(rv, s_cvs[revealOrders[i - 1]]) <
                    diff(rv, s_cvs[revealOrders[i]]),
                RevealNotInAscendingOrder()
            );
        }
        s_revealOrders = revealOrders;
        // ** reveal2
        uint256 firstRevealOrder = revealOrders[0];
        require(
            firstRevealOrder == s_commitOrders[s_requestId][msg.sender] - 1,
            NotTheFirstRevealer()
        );
        require(
            keccak256(abi.encodePacked(secret)) ==
                bytes32(s_cos[firstRevealOrder])
        );
        s_secrets.push(secret);
    }

    function reveal2(bytes32 secret) external {
        uint256 commitIndex = s_commitOrders[s_requestId][msg.sender] - 1;
        uint256 secretLength = s_secrets.length;
        require(secretLength > 0, FirstReveal2NotCalled());
        require(
            s_revealOrders[secretLength] == commitIndex,
            RevealNotInAscendingOrder()
        );
        require(
            keccak256(abi.encodePacked(secret)) == bytes32(s_cos[commitIndex])
        );
        s_secrets.push(secret);
        if (secretLength + 1 == s_cvs.length) {
            s_randomNum[s_requestId] = uint256(
                keccak256(abi.encodePacked(s_secrets))
            );
        }
    }

    function diff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function deposit() external payable {
        uint256 depositAmount = s_depositAmount[msg.sender];
        uint256 activationThreshold = s_activationThreshold;
        unchecked {
            if (
                (s_depositAmount[msg.sender] += msg.value) >=
                activationThreshold &&
                depositAmount < activationThreshold
            ) ++s_activatedNum;
        }
    }

    function withdraw(uint256 amount) external {
        uint256 depositAmount = s_depositAmount[msg.sender];
        uint256 activationThreshold = s_activationThreshold;
        unchecked {
            if (
                (s_depositAmount[msg.sender] -= amount) <
                s_activationThreshold &&
                depositAmount >= activationThreshold
            ) --s_activatedNum;
        }
        payable(msg.sender).transfer(amount);
    }

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }
}
