// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {CommitReveal2Storage} from "./CommitReveal2Storage.sol";
import {Sort} from "./Sort.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Bitmap} from "./libraries/Bitmap.sol";
import {OperatorManager} from "./OperatorManager.sol";
import {console2} from "forge-std/Test.sol";

contract CommitReveal2 is EIP712, OptimismL1Fees, CommitReveal2Storage, OperatorManager {
    using Bitmap for mapping(uint248 => uint256);

    constructor(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 maxActivatedOperators,
        string memory name,
        string memory version,
        uint256 offChainSubmissionPeriod,
        uint256 requestOrSubmitOrFailDecisionPeriod,
        uint256 onChainSubmissionPeriod,
        uint256 offChainSubmissionPeriodPerOperator,
        uint256 onChainSubmissionPeriodPerOperator
    ) payable EIP712(name, version) {
        require(msg.value >= activationThreshold);
        s_depositAmount[msg.sender] = msg.value;
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_maxActivatedOperators = maxActivatedOperators;
        s_offChainSubmissionPeriod = offChainSubmissionPeriod;
        s_requestOrSubmitOrFailDecisionPeriod = requestOrSubmitOrFailDecisionPeriod;
        s_onChainSubmissionPeriod = onChainSubmissionPeriod;
        s_offChainSubmissionPeriodPerOperator = offChainSubmissionPeriodPerOperator;
        s_onChainSubmissionPeriodPerOperator = onChainSubmissionPeriodPerOperator;
        s_isInProcess = COMPLETED;
    }

    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, gasPrice, s_activatedOperators.length);
    }

    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        external
        view
        returns (uint256)
    {
        return _calculateRequestPrice(callbackGasLimit, gasPrice, numOfOperators);
    }

    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256 newRound) {
        require(callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT, ExceedCallbackGasLimit());
        uint256 activatedOperatorsLength = s_activatedOperators.length;
        require(activatedOperatorsLength > 1, NotEnoughActivatedOperators());
        require(s_depositAmount[owner()] >= s_activationThreshold, LeaderLowDeposit());
        require(
            msg.value >= _calculateRequestPrice(callbackGasLimit, tx.gasprice, activatedOperatorsLength),
            InsufficientAmount()
        );
        unchecked {
            newRound = s_requestCount++;
        }
        s_roundBitmap.flipBit(newRound);
        uint256 startTime = s_currentRound > s_lastfulfilledRound ? 0 : block.timestamp;
        s_requestInfo[newRound] = RequestInfo({
            consumer: msg.sender,
            startTime: startTime,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit
        });
        emit RandomNumberRequested(newRound, startTime, s_activatedOperators);
        if (s_isInProcess == COMPLETED) {
            s_currentRound = newRound;
            s_isInProcess = IN_PROGRESS;
            emit IsInProcess(IN_PROGRESS);
        }
    }

    function _calculateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        internal
        view
        virtual
        returns (uint256)
    {
        // submitRoot l2GasUsed = 47216
        // generateRandomNumber l2GasUsed = 21118.97⋅N + 87117.53
        return (gasPrice * (callbackGasLimit + (21119 * numOfOperators + 134334))) + s_flatFee
            + _getL1CostWeiForcalldataSize2(MERKLEROOTSUB_CALLDATA_BYTES_SIZE, 292 + (128 * numOfOperators));
    }

    function _getL1CostWeiForcalldataSize2(uint256 calldataSizeBytes1, uint256 calldataSizeBytes2)
        private
        view
        returns (uint256)
    {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
        return _getL1CostWeiForCalldataSize(calldataSizeBytes1) + _getL1CostWeiForCalldataSize(calldataSizeBytes2);
    }

    // ** On-chain: Commit Submission Request
    function requestToSubmitCv(uint256[] calldata indices) external onlyOwner {
        require(indices.length > 0, ZeroLength());
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(
            block.timestamp < startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod, TooLate()
        );
        s_cvs[startTime] = new bytes32[](s_activatedOperators.length);
        s_requestedToSubmitCvIndices = indices;
        s_requestedToSubmitCvTimestamp = block.timestamp;
        emit RequestedToSubmitCv(startTime, indices);
    }

    // address를 제출했다면

    // ** On-chain: Commit Submission
    function submitCv(bytes32 cv) external {
        require(cv != 0x00, ShouldNotBeZero());
        require(block.timestamp < s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        s_cvs[startTime][activatedOperatorIndex] = cv;
        emit CvSubmitted(startTime, cv, activatedOperatorIndex);
    }

    // * On-chain: Merkle Root Submission
    // * Or Restart this round
    function failToSubmitCv() external {
        // ** check if it's time to submit merkle root or to fail this round
        uint256 round = s_currentRound;
        bytes32[] storage s_cvsArray = s_cvs[s_requestInfo[round].startTime];
        require(s_cvsArray.length > 0, CvNotRequested());
        require(block.timestamp >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod, TooEarly());
        // ** who didn't submi CV even though requested
        uint256 requestedToSubmitCVLength = s_requestedToSubmitCvIndices.length;
        uint256 didntSubmitCVLength; // ** count of operators who didn't submit CV
        address[] memory addressToDeactivates = new address[](requestedToSubmitCVLength);
        for (uint256 i; i < requestedToSubmitCVLength; i = unchecked_inc(i)) {
            uint256 index = s_requestedToSubmitCvIndices[i];
            if (s_cvsArray[index] == 0) {
                // ** slash deposit and deactivate
                unchecked {
                    addressToDeactivates[didntSubmitCVLength++] = s_activatedOperators[index];
                }
            }
        }

        // ** return gas fee
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCV_GASUSED; // + L1Gas
        s_depositAmount[msg.sender] += returnGasFee;

        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator = slashRewardPerOperator
            + (activationThreshold * didntSubmitCVLength - returnGasFee)
                / (s_activatedOperators.length - didntSubmitCVLength + 1); // 1 for owner
        // ** update global slash reward
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        for (uint256 i; i < didntSubmitCVLength; i = unchecked_inc(i)) {
            // *** update each slash reward
            address operator = addressToDeactivates[i];
            uint256 accumulatedReward = slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator];
            s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;

            // *** update deposit amount
            s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + accumulatedReward;
            _deactivate(s_activatedOperatorIndex1Based[operator] - 1, operator);
        }

        // ** restart or end this round
        if (s_activatedOperators.length > 1) {
            s_requestInfo[round].startTime = block.timestamp;
            emit RandomNumberRequested(round, block.timestamp, s_activatedOperators);
        } else {
            s_isInProcess = HALTED;
            emit IsInProcess(HALTED);
        }
    }

    // ** On-chain: Merkle Root Submission
    function submitMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(
            block.timestamp < startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod, TooLate()
        );
        s_merkleRoot = merkleRoot;
        s_merkleRootSubmittedTimestamp = block.timestamp;
        s_isSubmittedMerkleRoot[startTime] = true;
        emit MerkleRootSubmitted(startTime, merkleRoot);
    }

    function failToRequestSubmitCvOrSubmitMerkleRoot() external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** Not requested
        require(s_cvs[startTime].length == 0, AlreadyRequestedToSubmitCv());
        // ** MerkleRoot Not Submitted
        require(!s_isSubmittedMerkleRoot[startTime], AlreadySubmittedMerkleRoot());
        require(
            block.timestamp >= startTime + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooEarly()
        );
        // ** slash the leadernode(owner)'s deposit
        uint256 activationThreshold = s_activationThreshold;
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED; // + L1Gas
        address owner = owner();
        unchecked {
            s_depositAmount[owner] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[owner] += delta;

        s_isInProcess = HALTED;
        emit IsInProcess(HALTED);
    }

    function submitMerkleRootAfterDispute(bytes32 merkleRoot) external onlyOwner {
        require(
            block.timestamp
                < s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooLate()
        );
        s_merkleRoot = merkleRoot;
        s_merkleRootSubmittedTimestamp = block.timestamp;
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        s_isSubmittedMerkleRoot[startTime] = true;
        emit MerkleRootSubmitted(startTime, merkleRoot);
    }

    function failToSubmitMerkleRootAfterDispute() external {
        uint256 round = s_currentRound;
        require(
            block.timestamp
                >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooEarly()
        );
        uint256 startTime = s_requestInfo[round].startTime;
        require(s_cvs[startTime].length > 0, CvNotRequested());
        require(!s_isSubmittedMerkleRoot[startTime], AlreadySubmittedMerkleRoot());

        // ** slash the leadernode(owner)'s deposit
        uint256 activationThreshold = s_activationThreshold;
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITMERKLEROOTAFTERDISPUTE_GASUSED; // + L1Gas
        address owner = owner();
        unchecked {
            s_depositAmount[owner] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[owner] += delta;

        s_isInProcess = HALTED;
        emit IsInProcess(HALTED);
    }

    // The consumer can issue a refund || operators can activate, and if more than one operator is available, the round can be restarted.
    function refund(uint256 round) external notInProcess {
        require(round < s_requestCount, InvalidRound());
        require(round >= s_currentRound, InvalidRound());
        RequestInfo storage requestInfo = s_requestInfo[round];
        require(requestInfo.consumer == msg.sender, NotConsumer());
        s_roundBitmap.flipBit(round); // 1 -> 0

        // ** refund
        uint256 cost = requestInfo.cost;
        require(cost > 0, AlreadyRefunded());
        requestInfo.cost = 0;
        assembly ("memory-safe") {
            // Transfer the ETH and check if it succeeded or not.
            if iszero(call(gas(), caller(), cost, 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    function resume() external payable onlyOwner {
        require(s_isInProcess == HALTED, NotHalted());
        require(s_activatedOperators.length > 1, NotEnoughActivatedOperators());
        address owner = owner();
        if (msg.value > 0) s_depositAmount[owner] += msg.value;
        require(s_depositAmount[owner] >= s_activationThreshold, LeaderLowDeposit());
        uint256 nextRequestedRound = s_currentRound;
        bool requested;
        uint256 requestCountMinusOne = s_requestCount - 1;
        for (uint256 i; i < 10; i++) {
            (nextRequestedRound, requested) = s_roundBitmap.nextRequestedRound(nextRequestedRound);
            if (requested) {
                s_currentRound = nextRequestedRound;
                // s_lastfulfilledRound = nextRequestedRound - 1;
                s_requestInfo[nextRequestedRound].startTime = block.timestamp;
                s_isInProcess = IN_PROGRESS;
                emit IsInProcess(IN_PROGRESS);
                emit RandomNumberRequested(nextRequestedRound, block.timestamp, s_activatedOperators);
                return;
            }
            unchecked {
                if (nextRequestedRound++ >= requestCountMinusOne) {
                    // && requested = false
                    s_isInProcess = COMPLETED;
                    s_lastfulfilledRound = requestCountMinusOne;
                    s_currentRound = requestCountMinusOne;
                    emit IsInProcess(COMPLETED);
                    return;
                }
            }
        }
        s_currentRound = nextRequestedRound;
    }

    // * Phase5: On-chain: Reaveal-1 Submission Request
    function requestToSubmitCo(
        uint256[] calldata indices,
        bytes32[] calldata cvs,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external onlyOwner {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(s_isSubmittedMerkleRoot[startTime], MerkleRootNotSubmitted());
        require(
            block.timestamp
                < s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod + s_requestOrSubmitOrFailDecisionPeriod,
            TooLate()
        );
        uint256 cvsLength = cvs.length;
        bytes32[] storage s_cvsArray = s_cvs[startTime];
        if (s_cvsArray.length == 0) {
            s_cvs[startTime] = new bytes32[](s_activatedOperators.length);
        }
        uint256 requestToSubmitCoBitmap;
        for (uint256 i; i < cvsLength; i = unchecked_inc(i)) {
            uint256 index = indices[i];
            requestToSubmitCoBitmap ^= 1 << index;
            require(ss[i] <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, InvalidSignatureS());
            require(
                index + 1
                    == s_activatedOperatorIndex1Based[ecrecover(
                        _hashTypedDataV4(
                            keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: startTime, cv: cvs[i]})))
                        ),
                        vs[i],
                        rs[i],
                        ss[i]
                    )],
                InvalidSignature()
            );
            s_cvsArray[index] = cvs[i];
        }
        uint256 indicesLength = indices.length;
        for (uint256 i = cvsLength; i < indicesLength; i = unchecked_inc(i)) {
            uint256 index = indices[i];
            requestToSubmitCoBitmap ^= 1 << index;
            require(s_cvsArray[index] > 0, CvNotSubmitted(indices[i]));
        }
        s_requestedToSubmitCoIndices = indices;
        s_requestToSubmitCoBitmap[startTime] = requestToSubmitCoBitmap;
        s_requestedToSubmitCoTimestamp = block.timestamp;
        // ** Not Complete
        emit RequestedToSubmitCo(startTime, indices);
    }

    // * Phase6: On-chain: Reaveal-1 Submission
    function submitCo(bytes32 co) external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        require(block.timestamp < s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        require(s_cvs[startTime][activatedOperatorIndex] == keccak256(abi.encodePacked(co)), InvalidCo());
        assembly ("memory-safe") {
            mstore(0, startTime)
            mstore(0x20, s_requestToSubmitCoBitmap.slot)
            let slot := keccak256(0, 0x40)
            sstore(slot, and(sload(slot), not(shl(activatedOperatorIndex, 1))))
        }
        emit CoSubmitted(startTime, co, activatedOperatorIndex);
    }

    function failToSubmitCo() external {
        // ** check if it's time to fail this round
        uint256 round = s_currentRound;
        uint256 startTime = s_requestInfo[round].startTime;
        require(block.timestamp >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod, TooEarly());
        uint256 requestToSubmitCoBitmap = s_requestToSubmitCoBitmap[startTime];
        require(requestToSubmitCoBitmap > 0, CoNotRequested());
        // ** who didn't submit Co even though requested
        uint256 requestedToSubmitCoLength = s_requestedToSubmitCoIndices.length;
        uint256 didntSubmitCoLength; // ** count of operators who didn't submit Co
        address[] memory addressToDeactivates = new address[](requestedToSubmitCoLength);
        for (uint256 i; i < requestedToSubmitCoLength; i = unchecked_inc(i)) {
            uint256 index = s_requestedToSubmitCoIndices[i];
            if (requestToSubmitCoBitmap & 1 << index > 0) {
                // ** slash deposit and deactivate
                unchecked {
                    addressToDeactivates[didntSubmitCoLength++] = s_activatedOperators[index];
                }
            }
        }
        // ** return gas fee
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCO_GASUSED;
        s_depositAmount[msg.sender] += returnGasFee;

        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator = slashRewardPerOperator
            + (activationThreshold * didntSubmitCoLength - returnGasFee)
                / (s_activatedOperators.length - didntSubmitCoLength + 1); // 1 for owner
        // ** update global slash reward
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;
        for (uint256 i; i < didntSubmitCoLength; i = unchecked_inc(i)) {
            // *** update each slash reward
            address operator = addressToDeactivates[i];
            uint256 accumulatedReward = slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator];
            s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;
            // *** update deposit amount
            s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + accumulatedReward;
            _deactivate(s_activatedOperatorIndex1Based[operator] - 1, operator);
        }

        // ** restart or end this round
        if (s_activatedOperators.length > 1) {
            s_requestInfo[round].startTime = block.timestamp;
            emit RandomNumberRequested(round, block.timestamp, s_activatedOperators);
        } else {
            s_isInProcess = HALTED;
            emit IsInProcess(HALTED);
        }
    }

    struct TempStackVariables {
        // to avoid stack too deep error
        uint256 startTime;
        uint256 operatorsLength;
        uint256 secretsLength;
    }

    struct RVICV {
        // to avoid stack too deep error
        uint256 rv;
        uint256 i;
        bytes32 cv;
    }

    // * Phase8: On-chain: Reveal-2 Submission Request
    function requestToSubmitS(
        bytes32[] calldata cos, // all cos
        bytes32[] calldata secrets, // already received off-chain
        Signature[] calldata signatures, // used struct to avoid stack too deep error, who didn't submit cv onchain, index descending order
        uint256[] calldata revealOrders
    ) external onlyOwner {
        TempStackVariables memory tempStackVariables = TempStackVariables({
            startTime: s_requestInfo[s_currentRound].startTime,
            operatorsLength: s_activatedOperators.length,
            secretsLength: secrets.length
        });
        require(
            (
                block.timestamp
                    < s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
                        + (s_offChainSubmissionPeriodPerOperator * tempStackVariables.operatorsLength)
                        + s_requestOrSubmitOrFailDecisionPeriod
            )
                || (
                    block.timestamp
                        < s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
                            + (s_offChainSubmissionPeriodPerOperator * tempStackVariables.operatorsLength)
                            + s_requestOrSubmitOrFailDecisionPeriod
                ),
            TooLate()
        );
        s_ss[tempStackVariables.startTime] = new bytes32[](tempStackVariables.operatorsLength);
        bytes32[] storage s_cvsArray = s_cvs[tempStackVariables.startTime];
        if (s_cvsArray.length == 0) {
            s_cvs[tempStackVariables.startTime] = new bytes32[](tempStackVariables.operatorsLength);
        }
        {
            // to avoid stack too deep error
            RVICV memory rvicv;
            rvicv.rv = uint256(keccak256(abi.encodePacked(cos)));
            uint256[] memory diffs = new uint256[](tempStackVariables.operatorsLength);
            do {
                unchecked {
                    rvicv.cv = _efficientOneKeccak256(cos[--tempStackVariables.operatorsLength]);
                    diffs[tempStackVariables.operatorsLength] = _diff(rvicv.rv, uint256(rvicv.cv));
                    if (s_cvsArray[tempStackVariables.operatorsLength] > 0) {
                        require(s_cvsArray[tempStackVariables.operatorsLength] == rvicv.cv, InvalidCo());
                    } else {
                        require(
                            signatures[rvicv.i].s <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                            InvalidSignatureS()
                        );
                        require(
                            s_activatedOperatorIndex1Based[ecrecover(
                                _hashTypedDataV4(
                                    keccak256(
                                        abi.encode(
                                            MESSAGE_TYPEHASH,
                                            Message({timestamp: tempStackVariables.startTime, cv: rvicv.cv})
                                        )
                                    )
                                ),
                                signatures[rvicv.i].v,
                                signatures[rvicv.i].r,
                                signatures[rvicv.i++].s
                            )] == tempStackVariables.operatorsLength + 1,
                            InvalidSignature()
                        );
                        s_cvsArray[tempStackVariables.operatorsLength] = rvicv.cv;
                    }
                }
            } while (tempStackVariables.operatorsLength > 0);
            // ** verify reveal order
            uint256 before = diffs[revealOrders[0]];
            uint256 activatedOperatorLength = cos.length;
            for (rvicv.i = 1; rvicv.i < activatedOperatorLength; rvicv.i = unchecked_inc(rvicv.i)) {
                uint256 curr = diffs[revealOrders[rvicv.i]];
                require(before >= curr, RevealNotInDescendingOrder());
                before = curr;
            }
        }
        s_revealOrders = revealOrders;

        s_requestedToSubmitSFromIndexK = tempStackVariables.secretsLength;
        emit RequestedToSubmitSFromIndexK(tempStackVariables.startTime, tempStackVariables.secretsLength);
        bytes32[] storage s_ssArray = s_ss[tempStackVariables.startTime];
        while (tempStackVariables.secretsLength > 0) {
            unchecked {
                uint256 activatedOperatorIndex = revealOrders[--tempStackVariables.secretsLength];
                bytes32 secret = secrets[tempStackVariables.secretsLength];
                require(s_cvsArray[activatedOperatorIndex] == _efficientTwoKeccak256(secret), InvalidS());
                s_ssArray[activatedOperatorIndex] = secret;
            }
        }
        s_previousSSubmitTimestamp = block.timestamp;
    }

    // * Phase9: On-chain: Reveal-2 Submission
    function submitS(bytes32 s) external {
        uint256 round = s_currentRound;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTime = requestInfo.startTime;
        require(block.timestamp < s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        require(s_cvs[startTime][activatedOperatorIndex] == _efficientTwoKeccak256(s), InvalidS());
        unchecked {
            require(s_revealOrders[s_requestedToSubmitSFromIndexK++] == activatedOperatorIndex, InvalidRevealOrder());
        }
        emit SSubmitted(startTime, s, activatedOperatorIndex);
        s_ss[startTime][activatedOperatorIndex] = s;
        if (activatedOperatorIndex == s_revealOrders[s_revealOrders.length - 1]) {
            // ** create random number
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(s_ss[startTime])));
            uint256 nextRound = unchecked_inc(round);
            if (nextRound == s_requestCount) {
                s_isInProcess = COMPLETED;
                emit IsInProcess(COMPLETED);
            } else {
                s_requestInfo[nextRound].startTime = block.timestamp;
                s_currentRound = nextRound;
            }
            s_depositAmount[s_activatedOperators[activatedOperatorIndex]] += requestInfo.cost;
            s_lastfulfilledRound = round;
            emit RandomNumberGenerated(
                round,
                randomNumber,
                _call(
                    requestInfo.consumer,
                    abi.encodeWithSelector(ConsumerBase.rawFulfillRandomNumber.selector, round, randomNumber),
                    requestInfo.callbackGasLimit
                )
            );
        }
    }

    function failToSubmitS() external {
        // ** check if S is requested
        bytes32[] storage s_ssArray = s_ss[s_requestInfo[s_currentRound].startTime];
        require(s_ssArray.length > 0, SNotRequested());
        // ** check if it's time to fail this round
        require(block.timestamp >= s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator, TooEarly());

        // ** return gas fee
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITS_GASUSED;
        s_depositAmount[msg.sender] += returnGasFee;

        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator =
            slashRewardPerOperator + (activationThreshold - returnGasFee) / (s_activatedOperators.length); // 1 for owner
        // ** update global slash reward
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        // ** s_revealOrders[s_requestedToSubmitSFromIndexK] is the index of the operator who didn't submit S
        uint256 indexToSlash = s_revealOrders[s_requestedToSubmitSFromIndexK];
        address operator = s_activatedOperators[indexToSlash];
        // ** update deposit amount
        s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + slashRewardPerOperator
            - s_slashRewardPerOperatorPaid[operator];
        s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;
        // ** deactivate
        _deactivate(indexToSlash, operator);

        // ** restart or end this round
        if (s_activatedOperators.length > 1) {
            s_requestInfo[s_currentRound].startTime = block.timestamp;
            emit RandomNumberRequested(s_currentRound, block.timestamp, s_activatedOperators);
        } else {
            s_isInProcess = HALTED;
            emit IsInProcess(HALTED);
        }
    }

    function failToRequestSOrGenerateRandomNumber() external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** MerkleRoot Submitted
        require(s_isSubmittedMerkleRoot[startTime], MerkleRootNotSubmitted());
        if (s_requestToSubmitCoBitmap[startTime] > 0) {
            require(
                block.timestamp
                    >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod
                        + (s_onChainSubmissionPeriodPerOperator * s_activatedOperators.length)
                        + s_requestOrSubmitOrFailDecisionPeriod,
                TooEarly()
            );
        } else {
            require(
                block.timestamp
                    >= s_merkleRootSubmittedTimestamp + s_offChainSubmissionPeriod
                        + (s_offChainSubmissionPeriodPerOperator * s_activatedOperators.length)
                        + s_requestOrSubmitOrFailDecisionPeriod,
                TooEarly()
            );
        }
        // ** slash the leadernode(owner)'s deposit
        uint256 activationThreshold = s_activationThreshold;
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCVORSUBMITMERKLEROOT_GASUSED; // + L1Gas
        address owner = owner();
        unchecked {
            s_depositAmount[owner] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[owner] += delta;

        s_isInProcess = HALTED;
        emit IsInProcess(HALTED);
    }

    function generateRandomNumber(
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint256[] calldata revealOrders
    ) external {
        uint256 activatedOperatorsLength;
        assembly ("memory-safe") {
            activatedOperatorsLength := sload(s_activatedOperators.slot)
            // ** check if all secrets are submitted
            if gt(activatedOperatorsLength, secrets.length) {
                mstore(0, 0xe0767fa4) // selector for InvalidSecretLength()
                revert(0x1c, 0x04)
            }
            // ** check if it is not too late
            if iszero(
                or(
                    lt(
                        timestamp(),
                        add(
                            add(
                                add(sload(s_merkleRootSubmittedTimestamp.slot), sload(s_offChainSubmissionPeriod.slot)),
                                mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorsLength)
                            ),
                            sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                        )
                    ),
                    lt(
                        timestamp(),
                        add(
                            add(
                                add(sload(s_requestedToSubmitCoTimestamp.slot), sload(s_onChainSubmissionPeriod.slot)),
                                mul(sload(s_offChainSubmissionPeriodPerOperator.slot), activatedOperatorsLength)
                            ),
                            sload(s_requestOrSubmitOrFailDecisionPeriod.slot)
                        )
                    )
                )
            ) {
                mstore(0, 0xecdd1c29) // selector for TooLate()
                revert(0x1c, 0x04)
            }
        }
        // *** All secrets are submitted
        // require(
        //     (block.timestamp <
        //         s_merkleRootSubmittedTimestamp +
        //             s_offChainSubmissionPeriod +
        //             (s_offChainSubmissionPeriodPerOperator *
        //                 activatedOperatorsLength) +
        //             s_requestOrSubmitOrFailDecisionPeriod) ||
        //         (block.timestamp <
        //             s_requestedToSubmitCoTimestamp +
        //                 s_onChainSubmissionPeriod +
        //                 (s_offChainSubmissionPeriodPerOperator *
        //                     activatedOperatorsLength) +
        //                 s_requestOrSubmitOrFailDecisionPeriod),
        //     TooLate()
        // );

        bytes32[] memory cos = new bytes32[](activatedOperatorsLength);
        bytes32[] memory cvs = new bytes32[](activatedOperatorsLength);
        assembly ("memory-safe") {
            for { let i := 0 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                //cos[i] = keccak256(abi.encodePacked(secrets[i]));
                //cvs[i] = keccak256(abi.encodePacked(cos[i]));
                mstore(0x00, calldataload(add(secrets.offset, shl(5, i))))
                let cosMemP := add(add(cos, 0x20), shl(5, i))
                mstore(cosMemP, keccak256(0x00, 0x20))
                mstore(add(add(cvs, 0x20), shl(5, i)), keccak256(cosMemP, 0x20))
            }

            // ** verify reveal order
            /**
             * uint256 rv = uint256(keccak256(abi.encodePacked(cos)));
             * for (uint256 i = 1; i < secretsLength; i = unchecked_inc(i)) {
             * require(
             *    diff(rv, cvs[revealOrders[i - 1]]) >
             *        diff(rv, cvs[revealOrders[i]]),
             *    RevealNotInAscendingOrder()
             * );
             *
             * uint256 before = diff(rv, cvs[revealOrders[0]]);
             * for (uint256 i = 1; i < secretsLength; i = unchecked_inc(i)) {
             *  uint256 after = diff(rv, cvs[revealOrders[i]]);
             *  require(before >= after, RevealNotInAscendingOrder());
             *  before = after;
             * }
             *
             */
            function _diff(a, b) -> c {
                switch gt(a, b)
                case true { c := sub(a, b) }
                default { c := sub(b, a) }
            }
            let rv := keccak256(add(cos, 0x20), shl(5, activatedOperatorsLength))
            let before := _diff(rv, mload(add(cvs, add(0x20, shl(5, calldataload(revealOrders.offset))))))
            for { let i := 1 } lt(i, activatedOperatorsLength) { i := add(i, 1) } {
                let after :=
                    _diff(rv, mload(add(cvs, add(0x20, shl(5, calldataload(add(revealOrders.offset, shl(5, i))))))))
                if lt(before, after) {
                    mstore(0, 0x24f1948e) // selector for RevealNotInDescendingOrder()
                    revert(0x1c, 0x04)
                }
                before := after
            }
        }

        // ** verify merkle root
        require(createMerkleRoot(cvs) == s_merkleRoot, MerkleVerificationFailed());

        // ** verify signer
        uint256 round = s_currentRound;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTimestamp = requestInfo.startTime;
        for (uint256 i; i < activatedOperatorsLength; i = unchecked_inc(i)) {
            // signature malleability prevention
            require(ss[i] <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, InvalidSignatureS());
            require(
                s_activatedOperatorIndex1Based[ecrecover(
                    _hashTypedDataV4(
                        keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: startTimestamp, cv: cvs[i]})))
                    ),
                    vs[i],
                    rs[i],
                    ss[i]
                )] > 0,
                InvalidSignature()
            );
        }

        // ** create random number
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(secrets)));
        uint256 nextRound = unchecked_inc(round);
        unchecked {
            if (nextRound == s_requestCount) {
                s_isInProcess = COMPLETED;
                emit IsInProcess(COMPLETED);
            } else {
                s_requestInfo[nextRound].startTime = block.timestamp;
                s_currentRound = nextRound;
            }
        }
        s_lastfulfilledRound = round;
        // reward the last revealer
        s_depositAmount[s_activatedOperators[revealOrders[activatedOperatorsLength - 1]]] += requestInfo.cost;
        emit RandomNumberGenerated(
            round,
            randomNumber,
            _call(
                requestInfo.consumer,
                abi.encodeWithSelector(ConsumerBase.rawFulfillRandomNumber.selector, round, randomNumber),
                requestInfo.callbackGasLimit
            )
        );
    }

    function getMessageHash(uint256 timestamp, bytes32 cv) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, Message({timestamp: timestamp, cv: cv}))));
    }

    function getMerkleRoot(bytes32[] memory leaves) external pure returns (bytes32) {
        return createMerkleRoot(leaves);
    }

    function createMerkleRoot(bytes32[] memory leaves) private pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function _efficientKeccak256(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _efficientOneKeccak256(bytes32 a) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            value := keccak256(0x00, 0x20)
        }
    }

    function _efficientTwoKeccak256(bytes32 a) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x00, keccak256(0x00, 0x20))
            value := keccak256(0x00, 0x20)
        }
    }

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function _diff(uint256 a, uint256 b) private pure returns (uint256 c) {
        assembly ("memory-safe") {
            switch gt(a, b)
            case true { c := sub(a, b) }
            default { c := sub(b, a) }
        }
    }

    /// ** deposit and withdraw

    function _call(address target, bytes memory data, uint256 callbackGasLimit) private returns (bool success) {
        assembly ("memory-safe") {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) { revert(0, 0) }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) { return(0, 0) }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := call(callbackGasLimit, target, 0, add(data, 0x20), mload(data), 0, 0)
        }
    }
}
