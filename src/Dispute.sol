// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OperatorManager} from "./OperatorManager.sol";
import {CommitReveal2Storage} from "./CommitReveal2Storage.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract Dispute is EIP712, OperatorManager, CommitReveal2Storage {
    constructor(string memory name, string memory version) EIP712(name, version) {}

    function requestToSubmitCv(uint256[] calldata indices) external onlyOwner {
        require(indices.length > 0, ZeroLength());
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        s_cvs[startTime] = new bytes32[](s_activatedOperators.length);
        s_requestedToSubmitCvIndices = indices;
        s_requestedToSubmitCvTimestamp = block.timestamp;
        emit RequestedToSubmitCv(startTime, indices);
    }

    function submitCv(bytes32 cv) external {
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        s_cvs[startTime][activatedOperatorIndex] = cv;
        assembly ("memory-safe") {
            mstore(0, startTime)
            mstore(0x20, s_requestToSubmitCvBitmap.slot)
            let slot := keccak256(0, 0x40)
            // set to one
            sstore(slot, or(sload(slot), shl(activatedOperatorIndex, 1)))
        }
        emit CvSubmitted(startTime, cv, activatedOperatorIndex);
    }

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
        // Operators who did not previously submit Cv on-chain
        for (uint256 i; i < cvsLength; i = _unchecked_inc(i)) {
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
        // Operators who already submitted Cv on-chain, simply confirm it exists
        uint256 indicesLength = indices.length;
        for (uint256 i = cvsLength; i < indicesLength; i = _unchecked_inc(i)) {
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

    function submitCo(bytes32 co) external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** Ensure we're within the on-chain submission period.
        require(block.timestamp < s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        // ** Confirm the newly revealed `co` hashes to the on-chain Cv.
        require(s_cvs[startTime][activatedOperatorIndex] == keccak256(abi.encodePacked(co)), InvalidCo());
        // ** Clear the operator’s bit from the bitmap to mark successful submission.
        assembly ("memory-safe") {
            mstore(0, startTime)
            mstore(0x20, s_requestToSubmitCoBitmap.slot)
            let slot := keccak256(0, 0x40)
            // set to zero
            sstore(slot, and(sload(slot), not(shl(activatedOperatorIndex, 1))))
        }
        emit CoSubmitted(startTime, co, activatedOperatorIndex);
    }

    struct TempStackVariables {
        // to avoid stack too deep error
        uint256 startTime;
        uint256 operatorsLength;
        uint256 secretsLength;
    }

    struct Signature {
        // to avoid stack too deep error
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct RVICV {
        // to avoid stack too deep error
        uint256 rv;
        uint256 i;
        bytes32 cv;
    }

    function requestToSubmitS(
        bytes32[] calldata cos, // all cos
        bytes32[] calldata secrets, // already received off-chain
        Signature[] calldata signatures, // used struct to avoid stack too deep error, who didn't submit cv onchain, index descending order
        uint256[] calldata revealOrders
    ) external onlyOwner {
        // Prepare struct variables to avoid stack too deep error.
        TempStackVariables memory tempStackVariables = TempStackVariables({
            startTime: s_requestInfo[s_currentRound].startTime,
            operatorsLength: s_activatedOperators.length,
            secretsLength: secrets.length
        });
        // Initialize arrays for commitments (`cvs`) if not initialized and secrets (`ss`)
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
                        // If cv was not on-chain, require a signature
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
            // Ensure revealOrders is strictly descending by diffs
            uint256 before = diffs[revealOrders[0]];
            uint256 activatedOperatorLength = cos.length;
            for (rvicv.i = 1; rvicv.i < activatedOperatorLength; rvicv.i = _unchecked_inc(rvicv.i)) {
                uint256 curr = diffs[revealOrders[rvicv.i]];
                require(before >= curr, RevealNotInDescendingOrder());
                before = curr;
            }
        }
        // Set revealOrders for next step
        s_revealOrders = revealOrders;

        s_requestedToSubmitSFromIndexK = tempStackVariables.secretsLength;
        emit RequestedToSubmitSFromIndexK(tempStackVariables.startTime, tempStackVariables.secretsLength);
        bytes32[] storage s_ssArray = s_ss[tempStackVariables.startTime];
        // The secrets are in reveal order.
        while (tempStackVariables.secretsLength > 0) {
            unchecked {
                uint256 activatedOperatorIndex = revealOrders[--tempStackVariables.secretsLength];
                bytes32 secret = secrets[tempStackVariables.secretsLength];
                require(s_cvsArray[activatedOperatorIndex] == _efficientTwoKeccak256(secret), InvalidS());
                s_ssArray[activatedOperatorIndex] = secret;
            }
        }
        // Record timestamp for on-chain S-submissions
        s_previousSSubmitTimestamp = block.timestamp;
    }

    function submitS(bytes32 s) external {
        // ** Retrieve current round and its request info.
        uint256 round = s_currentRound;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTime = requestInfo.startTime;

        // ** Ensure S was requested.
        bytes32[] storage s_ssArray = s_ss[startTime];
        require(s_ssArray.length > 0, SNotRequested());

        // ** Identify the caller’s operator index and validate the secret.
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[msg.sender] - 1;
        require(s_cvs[startTime][activatedOperatorIndex] == _efficientTwoKeccak256(s), InvalidS());

        // ** Ensure this operator is next in the reveal order.
        unchecked {
            require(s_revealOrders[s_requestedToSubmitSFromIndexK++] == activatedOperatorIndex, InvalidRevealOrder());
        }

        // ** Record the operator’s final secret on-chain and emit an event.
        emit SSubmitted(startTime, s, activatedOperatorIndex);
        s_ssArray[activatedOperatorIndex] = s;

        // ** If this operator is last in the reveal order, finalize the random number process for this round.
        if (activatedOperatorIndex == s_revealOrders[s_revealOrders.length - 1]) {
            // ** create random number
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(s_ssArray)));
            uint256 nextRound = _unchecked_inc(round);
            // ** Move to the next round or mark as completed.
            if (nextRound == s_requestCount) {
                s_isInProcess = COMPLETED;
                emit Round(startTime, COMPLETED);
            } else {
                s_requestInfo[nextRound].startTime = block.timestamp;
                s_currentRound = nextRound;
                emit Round(block.timestamp, IN_PROGRESS);
            }
            // ** Reward this last revealer.
            s_depositAmount[s_activatedOperators[activatedOperatorIndex]] += requestInfo.cost;
            // ** Notify and callback.
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

    function failToSubmitCv() external {
        // ** check if it's time to submit merkle root or to fail this round
        uint256 round = s_currentRound;
        uint256 startTime = s_requestInfo[round].startTime;
        require(s_cvs[startTime].length > 0, CvNotRequested());
        require(block.timestamp >= s_requestedToSubmitCvTimestamp + s_onChainSubmissionPeriod, TooEarly());
        // ** who didn't submi CV even though requested
        uint256 requestedToSubmitCVLength = s_requestedToSubmitCvIndices.length;
        uint256 didntSubmitCVLength; // ** count of operators who didn't submit CV
        address[] memory addressToDeactivates = new address[](requestedToSubmitCVLength);
        uint256 requestToSubmitCvBitmap = s_requestToSubmitCvBitmap[startTime];
        for (uint256 i; i < requestedToSubmitCVLength; i = _unchecked_inc(i)) {
            uint256 index = s_requestedToSubmitCvIndices[i];
            if (requestToSubmitCvBitmap & 1 << index == 0) {
                // ** slash deposit and deactivate
                unchecked {
                    addressToDeactivates[didntSubmitCVLength++] = s_activatedOperators[index];
                }
            }
        }
        require(didntSubmitCVLength > 0, AllSubmittedCv());

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

        for (uint256 i; i < didntSubmitCVLength; i = _unchecked_inc(i)) {
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
            emit Round(block.timestamp, IN_PROGRESS);
        } else {
            s_isInProcess = HALTED;
            emit Round(startTime, HALTED);
        }
    }

    function failToRequestSubmitCvOrSubmitMerkleRoot() external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** Not requested to submit cv
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
        address ownerToSlash = owner();
        unchecked {
            s_depositAmount[ownerToSlash] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        // ** Distribute remainder among operators
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[ownerToSlash] += delta;

        // Halt the round
        s_isInProcess = HALTED;
        emit Round(startTime, HALTED);
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
        address ownerToSlash = owner();
        unchecked {
            s_depositAmount[ownerToSlash] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[ownerToSlash] += delta;

        s_isInProcess = HALTED;
        emit Round(startTime, HALTED);
    }

    function failToSubmitCo() external {
        // ** check if it's time to fail this round
        uint256 round = s_currentRound;
        uint256 startTime = s_requestInfo[round].startTime;
        // Must be after Co submission deadline.
        require(block.timestamp >= s_requestedToSubmitCoTimestamp + s_onChainSubmissionPeriod, TooEarly());
        uint256 requestToSubmitCoBitmap = s_requestToSubmitCoBitmap[startTime];
        require(requestToSubmitCoBitmap > 0, CoNotRequested());
        // Identify non-submitting operators.
        uint256 requestedToSubmitCoLength = s_requestedToSubmitCoIndices.length;
        uint256 didntSubmitCoLength; // ** count of operators who didn't submit Co
        address[] memory addressToDeactivates = new address[](requestedToSubmitCoLength);
        for (uint256 i; i < requestedToSubmitCoLength; i = _unchecked_inc(i)) {
            uint256 index = s_requestedToSubmitCoIndices[i];
            // ** Check if bit is still set, meaning no Co submitted for this operator.
            if (requestToSubmitCoBitmap & 1 << index > 0) {
                unchecked {
                    addressToDeactivates[didntSubmitCoLength++] = s_activatedOperators[index];
                }
            }
        }
        // Refund caller's gas fee for triggering the fail.
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITCO_GASUSED;
        s_depositAmount[msg.sender] += returnGasFee;

        // Update slash rewards.
        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator = slashRewardPerOperator
            + (activationThreshold * didntSubmitCoLength - returnGasFee)
                / (s_activatedOperators.length - didntSubmitCoLength + 1); // 1 for owner
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        // Slash each non-submitting operator.
        for (uint256 i; i < didntSubmitCoLength; i = _unchecked_inc(i)) {
            // *** update each slash reward
            address operator = addressToDeactivates[i];
            uint256 accumulatedReward = slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator];
            s_slashRewardPerOperatorPaid[operator] = updatedSlashRewardPerOperator;
            // Subtract threshold, add any accumulated slash reward already owed
            s_depositAmount[operator] = s_depositAmount[operator] - activationThreshold + accumulatedReward;
            _deactivate(s_activatedOperatorIndex1Based[operator] - 1, operator);
        }

        // Restart round if enough operators remain.
        if (s_activatedOperators.length > 1) {
            s_requestInfo[round].startTime = block.timestamp;
            emit Round(block.timestamp, IN_PROGRESS);
        } else {
            // Otherwise set contract to HALTED.
            emit Round(startTime, HALTED);
            s_isInProcess = HALTED;
        }
    }

    function failToSubmitS() external {
        // ** Ensure S was requested
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        bytes32[] storage s_ssArray = s_ss[startTime];
        require(s_ssArray.length > 0, SNotRequested());
        // ** check if it's time to fail this round
        require(block.timestamp >= s_previousSSubmitTimestamp + s_onChainSubmissionPeriodPerOperator, TooEarly());

        // ** Refund gas to the caller
        uint256 returnGasFee = tx.gasprice * FAILTOSUBMITS_GASUSED;
        s_depositAmount[msg.sender] += returnGasFee;

        // ** Update slash rewards
        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 activationThreshold = s_activationThreshold;
        uint256 updatedSlashRewardPerOperator =
            slashRewardPerOperator + (activationThreshold - returnGasFee) / (s_activatedOperators.length); // 1 for owner
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
            emit Round(block.timestamp, IN_PROGRESS);
        } else {
            s_isInProcess = HALTED;
            emit Round(startTime, HALTED);
        }
    }

    function failToRequestSOrGenerateRandomNumber() external {
        uint256 startTime = s_requestInfo[s_currentRound].startTime;
        // ** Ensure S was not requested
        require(s_ss[startTime].length == 0, SRequested());
        // ** Ensure random number was not generated
        require(s_isInProcess == IN_PROGRESS, RandomNumGenerated());
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
        address ownerToSlash = owner();
        unchecked {
            s_depositAmount[ownerToSlash] -= activationThreshold;
            s_depositAmount[msg.sender] += returnGasFee;
        }
        uint256 delta = (activationThreshold - returnGasFee) / s_activatedOperators.length;
        s_slashRewardPerOperator += delta;
        s_slashRewardPerOperatorPaid[ownerToSlash] += delta;

        s_isInProcess = HALTED;
        emit Round(startTime, HALTED);
    }

    function _unchecked_inc(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function _efficientOneKeccak256(bytes32 a) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            value := keccak256(0x00, 0x20)
        }
    }

    function _diff(uint256 a, uint256 b) private pure returns (uint256 c) {
        assembly ("memory-safe") {
            switch gt(a, b)
            case true { c := sub(a, b) }
            default { c := sub(b, a) }
        }
    }

    function _efficientTwoKeccak256(bytes32 a) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x00, keccak256(0x00, 0x20))
            value := keccak256(0x00, 0x20)
        }
    }

    function _call(address target, bytes memory data, uint256 callbackGasLimit) internal returns (bool success) {
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
