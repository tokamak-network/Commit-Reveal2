// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {CommitReveal2Storage} from "./CommitReveal2Storage.sol";
import {Sort} from "./Sort.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {console2} from "forge-std/Test.sol";

contract CommitReveal2 is
    EIP712,
    Ownable2Step,
    OptimismL1Fees,
    CommitReveal2Storage
{
    constructor(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 maxActivatedOperators,
        string memory name,
        string memory version,
        uint256 phase1StartOffset,
        uint256 phase2StartOffset,
        uint256 phase3StartOffset,
        uint256 phase4StartOffset,
        uint256 phase5StartOffset,
        uint256 phase6StartOffset,
        uint256 phase7StartOffset,
        uint256 phase8StartOffset,
        uint256 phase9StartOffset,
        uint256 phase10StartOffset
    ) EIP712(name, version) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_maxActivatedOperators = maxActivatedOperators;
        s_phase1StartOffset = phase1StartOffset;
        s_phase2StartOffset = phase2StartOffset;
        s_phase3StartOffset = phase3StartOffset;
        s_phase4StartOffset = phase4StartOffset;
        s_phase5StartOffset = phase5StartOffset;
        s_phase6StartOffset = phase6StartOffset;
        s_phase7StartOffset = phase7StartOffset;
        s_phase8StartOffset = phase8StartOffset;
        s_phase9StartOffset = phase9StartOffset;
        s_phase10StartOffset = phase10StartOffset;
    }

    function estimateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice
    ) external view returns (uint256) {
        return
            _calculateRequestPrice(
                callbackGasLimit,
                gasPrice,
                s_activatedOperators.length
            );
    }

    function estimateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice,
        uint256 numOfOperators
    ) external view returns (uint256) {
        return
            _calculateRequestPrice(callbackGasLimit, gasPrice, numOfOperators);
    }

    function requestRandomNumber(
        uint32 callbackGasLimit
    ) external payable returns (uint256 round) {
        require(
            callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT,
            ExceedCallbackGasLimit()
        );
        uint256 activatedOperatorsLength = s_activatedOperators.length;
        require(activatedOperatorsLength > 1, NotEnoughActivatedOperators());
        require(
            msg.value >=
                _calculateRequestPrice(
                    callbackGasLimit,
                    tx.gasprice,
                    activatedOperatorsLength
                ),
            InsufficientAmount()
        );
        unchecked {
            round = s_nextRound++;
        }
        uint256 startTime = round > s_fulfilledCount ? 0 : block.timestamp;
        s_requestInfo[round] = RequestInfo({
            consumer: msg.sender,
            startTime: startTime,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit
        });
        s_isInProcess = IN_PROGRESS;
        emit RandomNumberRequested(round, startTime, s_activatedOperators);
    }

    function _calculateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice,
        uint256 numOfOperators
    ) internal view virtual returns (uint256) {
        // submitRoot l2GasUsed = 47216
        // generateRandomNumber l2GasUsed = 21118.97⋅N + 87117.53
        return
            (gasPrice *
                (callbackGasLimit + (21119 * numOfOperators + 134334))) +
            s_flatFee +
            _getL1CostWeiForcalldataSize2(
                MERKLEROOTSUB_CALLDATA_BYTES_SIZE,
                292 + (128 * numOfOperators)
            );
    }

    function _getL1CostWeiForcalldataSize2(
        uint256 calldataSizeBytes1,
        uint256 calldataSizeBytes2
    ) private view returns (uint256) {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
        return
            _getL1CostWeiForCalldataSize(calldataSizeBytes1) +
            _getL1CostWeiForCalldataSize(calldataSizeBytes2);
    }

    // ** Commit Reveal2

    // * Phase1: On-chain: Commit Submission Request
    function requestToSubmitCV(uint256[] calldata indices) external onlyOwner {
        uint256 startTime = s_requestInfo[s_fulfilledCount].startTime;
        require(block.timestamp >= startTime + s_phase1StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase2StartOffset, TooLate());
        s_requestedToSubmitCVIndices = indices;
        s_cvs[startTime] = new bytes32[](s_activatedOperators.length);
        emit RequestedToSubmitCV(startTime, indices);
    }

    // * Phase2: On-chain: Commit Submission
    function submitCV(bytes32 cv) external {
        uint256 startTime = s_requestInfo[s_fulfilledCount].startTime;
        require(block.timestamp >= startTime + s_phase2StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase3StartOffset, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[
            msg.sender
        ] - 1;
        s_cvs[startTime][activatedOperatorIndex] = cv;
        emit CVSubmitted(startTime, cv, activatedOperatorIndex);
    }

    // * Phase3: On-chain: Merkle Root Submission
    // * Or Restart this round
    function phase2FailedAndRestart() external onlyOwner {}

    function submitMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        uint256 round = s_fulfilledCount;
        uint256 startTime = s_requestInfo[round].startTime;
        require(block.timestamp >= startTime + s_phase3StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase4StartOffset, TooLate());
        s_merkleRoot = merkleRoot;
        emit MerkleRootSubmitted(round, merkleRoot);
    }

    // * Phase5: On-chain: Reaveal-1 Submission Request
    function requestToSubmitCO(
        uint256[] calldata indices,
        bytes32[] calldata cvs,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external onlyOwner {
        uint256 startTime = s_requestInfo[s_fulfilledCount].startTime;
        require(block.timestamp >= startTime + s_phase5StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase6StartOffset, TooLate());
        uint256 cvsLength = cvs.length;
        bytes32[] storage s_cvsArray = s_cvs[startTime];
        for (uint256 i; i < cvsLength; i = unchecked_inc(i)) {
            require(
                ss[i] <=
                    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                InvalidSignatureS()
            );
            require(
                indices[i] + 1 ==
                    s_activatedOperatorIndex1Based[
                        ecrecover(
                            _hashTypedDataV4(
                                keccak256(
                                    abi.encode(
                                        MESSAGE_TYPEHASH,
                                        Message({
                                            timestamp: startTime,
                                            cv: cvs[i]
                                        })
                                    )
                                )
                            ),
                            vs[i],
                            rs[i],
                            ss[i]
                        )
                    ],
                InvalidSignature()
            );
            s_cvsArray[indices[i]] = cvs[i];
        }
        uint256 indicesLength = indices.length;
        for (uint256 i = cvsLength; i < indicesLength; i = unchecked_inc(i)) {
            require(s_cvsArray[indices[i]] > 0, CVNotSubmitted(indices[i]));
        }
        s_requestedToSubmitCOIndices = indices;
        emit RequestedToSubmitCO(startTime, indices);
    }

    // * Phase6: On-chain: Reaveal-1 Submission
    function submitCO(bytes32 co) external {
        uint256 startTime = s_requestInfo[s_fulfilledCount].startTime;
        require(block.timestamp >= startTime + s_phase6StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase7StartOffset, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[
            msg.sender
        ] - 1;
        require(
            s_cvs[startTime][activatedOperatorIndex] ==
                keccak256(abi.encodePacked(co)),
            InvalidCO()
        );
        emit COSubmitted(startTime, co, activatedOperatorIndex);
    }

    // * Phase8: On-chain: Reveal-2 Submission Request
    function requestToSubmitSFromIndex(
        uint256 k,
        bytes32[] calldata cos,
        Signature[] calldata signatures // used struct to avoid stack too deep error
    ) external onlyOwner {
        uint256 startTime = s_requestInfo[s_fulfilledCount].startTime;
        require(block.timestamp >= startTime + s_phase8StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase9StartOffset, TooLate());
        bytes32[] storage s_cvsArray = s_cvs[startTime];
        uint256 operatorsLength = s_activatedOperators.length;
        uint256[] memory diffs = new uint256[](operatorsLength);
        uint256[] memory revealOrders = new uint256[](operatorsLength);
        uint256 rv = uint256(keccak256(abi.encodePacked(cos)));
        uint256 i;
        s_ss[startTime] = new bytes32[](operatorsLength);
        do {
            unchecked {
                bytes32 cv = _efficientOneKeccak256(cos[--operatorsLength]);
                if (s_cvsArray[operatorsLength] > 0) {
                    require(s_cvsArray[operatorsLength] == cv, InvalidCO());
                } else {
                    require(
                        signatures[i].s <=
                            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                        InvalidSignatureS()
                    );
                    require(
                        s_activatedOperatorIndex1Based[
                            ecrecover(
                                _hashTypedDataV4(
                                    keccak256(
                                        abi.encode(
                                            MESSAGE_TYPEHASH,
                                            Message({
                                                timestamp: startTime,
                                                cv: cv
                                            })
                                        )
                                    )
                                ),
                                signatures[i].v,
                                signatures[i].r,
                                signatures[i++].s
                            )
                        ] == operatorsLength + 1,
                        InvalidSignature()
                    );
                    s_cvsArray[operatorsLength] = cv;
                }
                diffs[operatorsLength] = diff(rv, uint256(cv));
                revealOrders[operatorsLength] = operatorsLength;
            }
        } while (operatorsLength > 0);
        // ** calculate reveal order
        Sort.sort(diffs, revealOrders);
        s_revealOrders = revealOrders;
        s_requestedToSubmitSFromIndexK = k;
        emit RequestedToSubmitSFromIndex(startTime, k);
    }

    // * Phase9: On-chain: Reveal-2 Submission
    function submitS(bytes32 s) external {
        uint256 startTime = s_requestInfo[s_fulfilledCount].startTime;
        require(block.timestamp >= startTime + s_phase9StartOffset, TooEarly());
        require(block.timestamp < startTime + s_phase10StartOffset, TooLate());
        uint256 activatedOperatorIndex = s_activatedOperatorIndex1Based[
            msg.sender
        ] - 1;
        unchecked {
            require(
                s_revealOrders[s_requestedToSubmitSFromIndexK++] ==
                    activatedOperatorIndex,
                InvalidRevealOrder()
            );
        }
        require(
            s_cvs[startTime][activatedOperatorIndex] ==
                _efficientTwoKeccak256(s),
            InvalidS()
        );
        s_ss[startTime][activatedOperatorIndex] = s;
        emit SSubmitted(startTime, s, activatedOperatorIndex);
    }

    function generateRandomNumber(
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external {
        uint256 secretsLength = secrets.length;
        require(secretsLength > 1, NotEnoughParticipatedOperators());

        bytes32[] memory cos = new bytes32[](secretsLength);
        bytes32[] memory cvs = new bytes32[](secretsLength);

        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            cos[i] = keccak256(abi.encodePacked(secrets[i]));
            cvs[i] = keccak256(abi.encodePacked(cos[i]));
        }

        // ** verify merkle root
        require(
            createMerkleRoot(cvs) == s_merkleRoot,
            MerkleVerificationFailed()
        );

        // ** verify signer
        uint256 round = s_fulfilledCount;
        RequestInfo storage requestInfo = s_requestInfo[round];
        uint256 startTimestamp = requestInfo.startTime;
        address[] memory participatedOperators = new address[](secretsLength);
        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            // signature malleability prevention
            require(
                ss[i] <=
                    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                InvalidSignatureS()
            );
            address recoveredAddress = ecrecover(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            MESSAGE_TYPEHASH,
                            Message({timestamp: startTimestamp, cv: cvs[i]})
                        )
                    )
                ),
                vs[i],
                rs[i],
                ss[i]
            );
            participatedOperators[i] = recoveredAddress;
            require(
                s_activatedOperatorIndex1Based[recoveredAddress] > 0,
                InvalidSignature()
            );
        }
        // ** create random number
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(secrets)));
        unchecked {
            if (++s_fulfilledCount == s_nextRound)
                s_isInProcess = NOT_IN_PROGRESS;
            else s_requestInfo[round + 1].startTime = block.timestamp;
        }
        emit RandomNumberGenerated(
            round,
            randomNumber,
            _call(
                requestInfo.consumer,
                abi.encodeWithSelector(
                    ConsumerBase.rawFulfillRandomNumber.selector,
                    round,
                    randomNumber
                ),
                requestInfo.callbackGasLimit
            ),
            participatedOperators
        );
    }

    function getMessageHash(
        uint256 timestamp,
        bytes32 cv
    ) external view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MESSAGE_TYPEHASH,
                        Message({timestamp: timestamp, cv: cv})
                    )
                )
            );
    }

    function getMerkleRoot(
        bytes32[] memory leaves
    ) external pure returns (bytes32) {
        return createMerkleRoot(leaves);
    }

    function createMerkleRoot(
        bytes32[] memory leaves
    ) private pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function _efficientKeccak256(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _efficientOneKeccak256(
        bytes32 a
    ) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            value := keccak256(0x00, 0x20)
        }
    }

    function _efficientTwoKeccak256(
        bytes32 a
    ) private pure returns (bytes32 value) {
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

    function diff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /// ** deposit and withdraw
    function deposit() public payable {
        s_depositAmount[msg.sender] += msg.value;
    }

    function depositAndActivate() external payable {
        deposit();
        activate();
    }

    function withdraw(uint256 amount) external {
        s_depositAmount[msg.sender] -= amount;
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        if (
            activatedOperatorIndex1Based != 0 &&
            s_depositAmount[msg.sender] < s_activationThreshold
        ) _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    function activate() public {
        require(s_isInProcess == NOT_IN_PROGRESS, InProcess());
        require(
            s_depositAmount[msg.sender] >= s_activationThreshold,
            LessThanActivationThreshold()
        );
        require(
            s_activatedOperatorIndex1Based[msg.sender] == 0,
            AlreadyActivated()
        );
        s_activatedOperators.push(msg.sender);
        uint256 activatedOperatorLength = s_activatedOperators.length;
        require(
            activatedOperatorLength <= s_maxActivatedOperators,
            ActivatedOperatorsLimitReached()
        );
        s_activatedOperatorIndex1Based[msg.sender] = activatedOperatorLength;
        emit Activated(msg.sender);
    }

    function deactivate() external {
        require(s_isInProcess == NOT_IN_PROGRESS, InProcess());
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        require(activatedOperatorIndex1Based != 0, OperatorNotActivated());
        _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
    }

    function _deactivate(
        uint256 activatedOperatorIndex,
        address operator
    ) private {
        address lastOperator = s_activatedOperators[
            s_activatedOperators.length - 1
        ];
        s_activatedOperators[activatedOperatorIndex] = lastOperator;
        s_activatedOperators.pop();
        s_activatedOperatorIndex1Based[lastOperator] =
            activatedOperatorIndex +
            1;
        delete s_activatedOperatorIndex1Based[operator];
        emit DeActivated(operator);
    }

    function _call(
        address target,
        bytes memory data,
        uint256 callbackGasLimit
    ) private returns (bool success) {
        assembly ("memory-safe") {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) {
                revert(0, 0)
            }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) {
                revert(0, 0)
            }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) {
                return(0, 0)
            }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := call(
                callbackGasLimit,
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }
    }
}
