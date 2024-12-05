// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {OptimismL1Fees} from "./../OptimismL1Fees.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConsumerBase} from "./../ConsumerBase.sol";
import {CommitReveal2Storage} from "./../CommitReveal2Storage.sol";
import {Sort} from "./../Sort.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract CommitReveal2TestGenerateRandom is
    EIP712,
    Ownable,
    ReentrancyGuardTransient,
    OptimismL1Fees,
    CommitReveal2Storage
{
    constructor(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 maxActivatedOperators,
        string memory name,
        string memory version
    ) EIP712(name, version) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_maxActivatedOperators = maxActivatedOperators;

        s_activatedOperators.push(address(0));
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
    ) external payable nonReentrant returns (uint256 round) {
        require(
            callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT,
            ExceedCallbackGasLimit()
        );
        uint256 activatedOperatorsLength = s_activatedOperators.length;
        require(activatedOperatorsLength > 2, NotEnoughActivatedOperators());
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
        s_requestInfo[round] = RequestInfo({
            consumer: msg.sender,
            requestedTime: block.timestamp,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit
        });
        address[] memory activatedOperators;
        s_activatedOperatorsAtRound[
            round
        ] = activatedOperators = s_activatedOperators;
        mapping(address => uint256)
            storage activatedOperatorOrderAtRound = s_activatedOperatorOrderAtRound[
                round
            ];

        uint256 i = 1;
        s_depositAmount[owner()] += msg.value;
        do {
            activatedOperatorOrderAtRound[activatedOperators[i]] = i;
            unchecked {
                ++i;
            }
        } while (i < activatedOperatorsLength);
        emit RandomNumberRequested(round, activatedOperators);
    }

    function _calculateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice,
        uint256 numOfOperators
    ) private view returns (uint256) {
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
        uint8 l1FeeCalculationMode = s_l1FeeCalculationMode;
        if (l1FeeCalculationMode == L1_GAS_FEES_ECOTONE_MODE) {
            // estimate based on unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
            return
                _calculateOptimismL1DataFee(
                    calldataSizeBytes1 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                ) +
                _calculateOptimismL1DataFee(
                    calldataSizeBytes2 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                );
        } else if (l1FeeCalculationMode == L1_GAS_FEES_UPPER_BOUND_MODE) {
            // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
            return
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes1 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                ) +
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes2 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                );
        } else if (l1FeeCalculationMode == L1_GAS_FEES_LEGACY_MODE)
            return
                _calculateLegacyL1DataFee(calldataSizeBytes1) +
                _calculateLegacyL1DataFee(calldataSizeBytes2);
        else return 0;
    }

    // **** Operators ****
    // ** Commit Reveal
    function submitMerkleRoot(
        uint256 round,
        bytes32 merkleRoot
    ) external nonReentrant {
        require(
            s_activatedOperatorOrderAtRound[round][msg.sender] > 0,
            NotActivatedOperatorForThisRound()
        );
        s_roundInfo[round].merkleRoot = merkleRoot;
        emit MerkleRootSubmitted(round, merkleRoot);
    }

    function generateRandomNumber(
        uint256 round,
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external nonReentrant {
        uint256 secretsLength = secrets.length;
        require(secretsLength > 1, NotEnoughParticipatedOperators());

        bytes32[] memory cos = new bytes32[](secretsLength);
        uint256[] memory cvs = new uint256[](secretsLength);

        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            cos[i] = keccak256(abi.encodePacked(secrets[i]));
            cvs[i] = uint256(keccak256(abi.encodePacked(cos[i])));
        }
        uint256 rv = uint256(keccak256(abi.encodePacked(cos)));

        // ** determine reveal order
        uint256[] memory diffs = new uint256[](secretsLength);
        uint256[] memory revealOrders = new uint256[](secretsLength);
        for (uint256 i = 0; i < secretsLength; i = unchecked_inc(i)) {
            diffs[i] = diff(rv, cvs[i]);
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);

        bytes32[] memory leaves;
        assembly ("memory-safe") {
            leaves := cvs
        }
        RoundInfo storage roundInfo = s_roundInfo[round];
        // ** verify merkle root
        require(
            createMerkleRoot(leaves) == roundInfo.merkleRoot,
            MerkleVerificationFailed()
        );

        // ** verify signer
        mapping(address => uint256)
            storage activatedOperatorOrderAtRound = s_activatedOperatorOrderAtRound[
                round
            ];
        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            // signature malleability prevention
            require(
                ss[i] <=
                    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                InvalidSignatureS()
            );
            require(
                activatedOperatorOrderAtRound[
                    ecrecover(
                        _hashTypedDataV4(
                            keccak256(
                                abi.encode(
                                    MESSAGE_TYPEHASH,
                                    Message({round: round, cv: leaves[i]})
                                )
                            )
                        ),
                        vs[i],
                        rs[i],
                        ss[i]
                    )
                ] > 0,
                InvalidSignature()
            );
        }
        // ** create random number
        bytes32[] memory secretsInRevealOrder = new bytes32[](secretsLength);
        for (uint256 i; i < secretsLength; i = unchecked_inc(i))
            secretsInRevealOrder[i] = secrets[revealOrders[i]];

        uint256 randomNumber;
        roundInfo.randomNumber = randomNumber = uint256(
            keccak256(abi.encodePacked(secretsInRevealOrder))
        );
        RequestInfo storage requestInfo = s_requestInfo[round];
        bool success = _call(
            requestInfo.consumer,
            abi.encodeWithSelector(
                ConsumerBase.rawFulfillRandomNumber.selector,
                round,
                randomNumber
            ),
            requestInfo.callbackGasLimit
        );
        roundInfo.fulfillSucceeded = success;
        emit RandomNumberGenerated(round, randomNumber);
    }

    function getMessageHash(
        uint256 round,
        bytes32 cv
    ) external view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MESSAGE_TYPEHASH,
                        Message({round: round, cv: cv})
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

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function diff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /// *** Owner ***
    function activate(address operator) external nonReentrant onlyOwner {
        require(
            s_depositAmount[operator] >= s_activationThreshold,
            LessThanActivationThreshold()
        );
        _activate(operator);
    }

    function activate(
        address[] calldata operators
    ) external nonReentrant onlyOwner {
        uint256 operatorsLength = operators.length;
        for (uint256 i; i < operatorsLength; i = unchecked_inc(i)) {
            address operator = operators[i];
            require(
                s_depositAmount[operator] >= s_activationThreshold,
                LessThanActivationThreshold()
            );
            _activate(operator);
        }
    }

    function deactivate(address operator) external nonReentrant onlyOwner {
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
        require(activatedOperatorIndex != 0, OperatorNotActivated());
        _deactivate(activatedOperatorIndex, operator);
    }

    function deactivate(
        address[] calldata operators
    ) external nonReentrant onlyOwner {
        uint256 operatorsLength = operators.length;
        for (uint256 i; i < operatorsLength; i = unchecked_inc(i)) {
            address operator = operators[i];
            uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
            require(activatedOperatorIndex != 0, OperatorNotActivated());
            _deactivate(activatedOperatorIndex, operator);
        }
    }

    /// ** deposit and withdraw
    function deposit() external payable nonReentrant {
        s_depositAmount[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external nonReentrant {
        s_depositAmount[msg.sender] -= amount;
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        if (
            activatedOperatorIndex != 0 &&
            s_depositAmount[msg.sender] < s_activationThreshold
        ) _deactivate(activatedOperatorIndex, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    function _activate(address operator) private {
        require(s_activatedOperatorOrder[operator] == 0, AlreadyActivated());
        uint256 activatedOperatorLength = s_activatedOperators.length;
        require(
            activatedOperatorLength <= s_maxActivatedOperators,
            ActivatedOperatorsLimitReached()
        );
        s_activatedOperatorOrder[operator] = activatedOperatorLength;
        s_activatedOperators.push(operator);
        emit Activated(operator);
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
        s_activatedOperatorOrder[lastOperator] = activatedOperatorIndex;
        delete s_activatedOperatorOrder[operator];
        emit DeActivated(operator);
    }

    function _call(
        address target,
        bytes memory data,
        uint256 callbackGasLimit
    ) private returns (bool success) {
        assembly {
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
                revert(0, 0)
            }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := mload(add(data, 0x20))
        }
        return success;
    }
}
