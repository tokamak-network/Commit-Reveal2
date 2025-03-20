// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface CommitReveal2ForDocs {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error ActivatedOperatorsLimitReached();
    error AlreadyActivated();
    error AlreadyInitialized();
    error AlreadyRefunded();
    error AlreadyRequestedToSubmitCv();
    error AlreadySubmittedMerkleRoot();
    error AlreadySubmittedS();
    error CoNotRequested();
    error CvNotRequested();
    error CvNotSubmitted(uint256 index);
    error ETHTransferFailed();
    error ExceedCallbackGasLimit();
    error InProcess();
    error InsufficientAmount();
    error InvalidCo();
    error InvalidL1FeeCoefficient(uint8 coefficient);
    error InvalidRevealOrder();
    error InvalidRound();
    error InvalidS();
    error InvalidSecretLength();
    error InvalidShortString();
    error InvalidSignature();
    error InvalidSignatureLength();
    error InvalidSignatureS();
    error LeaderLowDeposit();
    error LessThanActivationThreshold();
    error MerkleRootNotSubmitted();
    error MerkleVerificationFailed();
    error NewOwnerIsZeroAddress();
    error NoHandoverRequest();
    error NotActivatedOperator();
    error NotConsumer();
    error NotEnoughActivatedOperators();
    error NotHalted();
    error OnlyActivatedOperatorCanClaim();
    error OperatorNotActivated();
    error OwnerCannotActivate();
    error RevealNotInDescendingOrder();
    error SNotRequested();
    error ShouldNotBeZero();
    error StringTooLong(string str);
    error TooEarly();
    error TooLate();
    error TransferFailed();
    error Unauthorized();
    error ZeroLength();

    event Activated(address operator);
    event CoSubmitted(uint256 timestamp, bytes32 co, uint256 index);
    event CvSubmitted(uint256 timestamp, bytes32 cv, uint256 index);
    event DeActivated(address operator);
    event EIP712DomainChanged();
    event IsInProcess(uint256 isInProcess);
    event L1FeeCalculationSet(uint8 coefficient);
    event MerkleRootSubmitted(uint256 timestamp, bytes32 merkleRoot);
    event OwnershipHandoverCanceled(address indexed pendingOwner);
    event OwnershipHandoverRequested(address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber, bool callbackSuccess);
    event RandomNumberRequested(uint256 round, uint256 timestamp, address[] activatedOperators);
    event RequestedToSubmitCo(uint256 timestamp, uint256[] indices);
    event RequestedToSubmitCv(uint256 timestamp, uint256[] indices);
    event RequestedToSubmitSFromIndexK(uint256 timestamp, uint256 index);
    event SSubmitted(uint256 timestamp, bytes32 s, uint256 index);

    function activate() external;
    function cancelOwnershipHandover() external payable;
    function claimSlashReward() external;
    function completeOwnershipHandover(address pendingOwner) external payable;
    function deactivate() external;
    function deposit() external payable;
    function depositAndActivate() external payable;
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice, uint256 numOfOperators)
        external
        view
        returns (uint256);
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256);
    function failToRequestSOrGenerateRandomNumber() external;
    function failToRequestSubmitCvOrSubmitMerkleRoot() external;
    function failToSubmitCo() external;
    function failToSubmitCv() external;
    function failToSubmitMerkleRootAfterDispute() external;
    function failToSubmitS() external;
    function generateRandomNumber(
        bytes32[] memory secrets,
        uint8[] memory vs,
        bytes32[] memory rs,
        bytes32[] memory ss,
        uint256[] memory revealOrders
    ) external;
    function getActivatedOperators() external view returns (address[] memory);
    function getActivatedOperatorsLength() external view returns (uint256);
    function getDepositPlusSlashReward(address operator) external view returns (uint256);
    function getMessageHash(uint256 timestamp, bytes32 cv) external view returns (bytes32);
    function owner() external view returns (address result);
    function ownershipHandoverExpiresAt(address pendingOwner) external view returns (uint256 result);
    function refund(uint256 round) external;
    function renounceOwnership() external payable;
    function requestOwnershipHandover() external payable;
    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256 newRound);
    function requestToSubmitCo(
        uint256[] memory indices,
        bytes32[] memory cvs,
        uint8[] memory vs,
        bytes32[] memory rs,
        bytes32[] memory ss
    ) external;
    function requestToSubmitCv(uint256[] memory indices) external;
    function requestToSubmitS(
        bytes32[] memory cos,
        bytes32[] memory secrets,
        Signature[] memory signatures,
        uint256[] memory revealOrders
    ) external;
    function resume() external payable;
    function s_activatedOperatorIndex1Based(address operator) external view returns (uint256);
    function s_activationThreshold() external view returns (uint256);
    function s_currentRound() external view returns (uint256);
    function s_cvs(uint256 timestamp, uint256) external view returns (bytes32);
    function s_depositAmount(address operator) external view returns (uint256);
    function s_flatFee() external view returns (uint256);
    function s_isInProcess() external view returns (uint256);
    function s_isSubmittedMerkleRoot(uint256 timestamp) external view returns (bool);
    function s_l1FeeCoefficient() external view returns (uint8);
    function s_maxActivatedOperators() external view returns (uint256);
    function s_merkleRoot() external view returns (bytes32);
    function s_merkleRootSubmittedTimestamp() external view returns (uint256);
    function s_previousSSubmitTimestamp() external view returns (uint256);
    function s_requestCount() external view returns (uint256);
    function s_requestInfo(uint256 round)
        external
        view
        returns (address consumer, uint256 startTime, uint256 cost, uint256 callbackGasLimit);
    function s_requestToSubmitCoBitmap(uint256 timestamp) external view returns (uint256);
    function s_requestedToSubmitCoIndices(uint256) external view returns (uint256);
    function s_requestedToSubmitCoTimestamp() external view returns (uint256);
    function s_requestedToSubmitCvIndices(uint256) external view returns (uint256);
    function s_requestedToSubmitCvTimestamp() external view returns (uint256);
    function s_requestedToSubmitSFromIndexK() external view returns (uint256);
    function s_revealOrders(uint256) external view returns (uint256);
    function s_roundBitmap(uint248 wordPos) external view returns (uint256);
    function s_slashRewardPerOperator() external view returns (uint256);
    function s_slashRewardPerOperatorPaid(address) external view returns (uint256);
    function s_ss(uint256 timestamp, uint256) external view returns (bytes32);
    function setL1FeeCoefficient(uint8 coefficient) external;
    function submitCo(bytes32 co) external;
    function submitCv(bytes32 cv) external;
    function submitMerkleRoot(bytes32 merkleRoot) external;
    function submitMerkleRootAfterDispute(bytes32 merkleRoot) external;
    function submitS(bytes32 s) external;
    function transferOwnership(address newOwner) external payable;
    function withdraw() external;
}
