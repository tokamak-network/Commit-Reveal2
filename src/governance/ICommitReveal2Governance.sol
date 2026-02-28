// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ICommitReveal2Governance {
    function setEconomicParameters(uint256 activationThreshold, uint256 flatFee) external;

    function setPeriods(
        uint256 offChainSubmissionPeriod,
        uint256 requestOrSubmitOrFailDecisionPeriod,
        uint256 onChainSubmissionPeriod,
        uint256 offChainSubmissionPeriodPerOperator,
        uint256 onChainSubmissionPeriodPerOperator
    ) external;

    function setGasParameters(
        uint128 gasUsedMerkleRootSubAndGenRandNumA,
        uint128 gasUsedMerkleRootSubAndGenRandNumBWithLeaderOverhead,
        uint256 maxCallbackGasLimit,
        uint48 getL1UpperBoundGasUsedWhenCalldataSize4,
        uint48 failToRequestCvOrSubmitMerkleRootGasUsed,
        uint48 failToSubmitMerkleRootAfterDisputeGasUsed,
        uint48 failToRequestSOrGenerateRandomNumberGasUsed,
        uint48 failToSubmitSGasUsed,
        uint32 failToSubmitCoGasUsedBaseA,
        uint32 failToSubmitCvGasUsedBaseA,
        uint32 failToSubmitGasUsedBaseB,
        uint32 perOperatorIncreaseGasUsedA,
        uint32 perOperatorIncreaseGasUsedB,
        uint32 perAdditionalDidntSubmitGasUsedA,
        uint32 perAdditionalDidntSubmitGasUsedB,
        uint32 perRequestedIncreaseGasUsed,
        uint256 maxGasPrice
    ) external;
}

interface ICommitReveal2L2Governance {
    function setL1FeeCoefficient(uint256 coefficient) external;
}
