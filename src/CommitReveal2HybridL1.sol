// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {CommitReveal2StorageHybridL1} from "./CommitReveal2StorageHybridL1.sol";
import {ConsumerBase} from "./ConsumerBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CommitReveal2HybridL1 is
    Ownable,
    EIP712,
    CommitReveal2StorageHybridL1
{
    constructor(
        uint256 activationThreshold,
        uint256 requestFee,
        string memory name,
        string memory version
    ) EIP712(name, version) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_requestFee = requestFee;
    }

    // *** For Consumers
    function requestRandomNumber() external payable {
        require(s_activatedOperators.length > 1, NotEnoughActivatedOperators());
        require(!s_isStarted);
        require(msg.value >= s_requestFee, InsufficientAmount());
        s_depositAmount[owner()] += msg.value;
        unchecked {
            ++s_round;
        }
        s_isStarted = true;
    }

    // *** For Operators
    function submitMerkleRoot(bytes32 merkleRoot) external {
        require(s_isStarted);
        require(s_activatedOperatorOrder[msg.sender] > 0);
        s_merkleRoot = merkleRoot;
    }

    function generateRandomNumber(
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint256[] calldata revealOrders
    ) external {
        uint256 secretsLength = secrets.length;
        require(secretsLength > 1, NotEnoughParticipatedOperators());

        bytes32[] memory cos = new bytes32[](secretsLength);
        uint256[] memory cvs = new uint256[](secretsLength);

        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            cos[i] = keccak256(abi.encodePacked(secrets[i]));
            cvs[i] = uint256(keccak256(abi.encodePacked(cos[i])));
        }
        uint256 rv = uint256(keccak256(abi.encodePacked(cos)));

        // ** verify reveal order
        for (uint256 i = 1; i < secretsLength; i = unchecked_inc(i)) {
            require(
                diff(rv, cvs[revealOrders[i - 1]]) <
                    diff(rv, cvs[revealOrders[i]]),
                RevealNotInAscendingOrder()
            );
        }

        // ** verify merkle root
        bytes32[] memory leaves;
        assembly ("memory-safe") {
            leaves := cvs
        }
        require(
            createMerkleRoot(leaves) == s_merkleRoot,
            MerkleVerificationFailed()
        );
        uint256 round = s_round;
        // ** verify signer
        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            // signature malleability prevention
            require(
                ss[i] <=
                    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
                InvalidSignatureS()
            );
            require(
                s_activatedOperatorOrder[
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
                ] > 0, // check if the operator was activated
                InvalidSignature()
            );
        }

        // ** create random number
        bytes32[] memory secretsInRevealOrder = new bytes32[](secretsLength);
        for (uint256 i; i < secretsLength; i = unchecked_inc(i))
            secretsInRevealOrder[i] = secrets[revealOrders[i]];
        s_randomNum[round] = uint256(
            keccak256(abi.encodePacked(secretsInRevealOrder))
        );
        s_isStarted = false;
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

    function diff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
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

    function activate(address operator) external onlyOwner {
        require(
            s_depositAmount[operator] >= s_activationThreshold,
            LessThanActivationThreshold()
        );
        _activate(operator);
    }

    function activate(address[] calldata operators) external onlyOwner {
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

    function deactivate(address operator) external onlyOwner {
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
        require(activatedOperatorIndex != 0, OperatorNotActivated());
        _deactivate(activatedOperatorIndex - 1, operator);
    }

    function deactivate(address[] calldata operators) external onlyOwner {
        uint256 operatorsLength = operators.length;
        for (uint256 i; i < operatorsLength; i = unchecked_inc(i)) {
            address operator = operators[i];
            uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
            require(activatedOperatorIndex != 0, OperatorNotActivated());
            _deactivate(activatedOperatorIndex - 1, operator);
        }
    }

    /// ** deposit and withdraw
    function deposit() external payable {
        s_depositAmount[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        s_depositAmount[msg.sender] -= amount;
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        if (
            activatedOperatorIndex != 0 &&
            s_depositAmount[msg.sender] < s_activationThreshold
        ) _deactivate(activatedOperatorIndex - 1, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    function _activate(address operator) private {
        require(s_activatedOperatorOrder[operator] == 0, AlreadyActivated());
        s_activatedOperators.push(operator);
        uint256 activatedOperatorLength = s_activatedOperators.length;
        s_activatedOperatorOrder[operator] = activatedOperatorLength;
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
        s_activatedOperatorOrder[lastOperator] = activatedOperatorIndex + 1;
        delete s_activatedOperatorOrder[operator];
    }

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }
}
