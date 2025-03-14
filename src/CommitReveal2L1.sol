// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./CommitReveal2.sol";

contract CommitReveal2L1 is CommitReveal2 {
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
    )
        payable
        CommitReveal2(
            activationThreshold,
            flatFee,
            maxActivatedOperators,
            name,
            version,
            offChainSubmissionPeriod,
            requestOrSubmitOrFailDecisionPeriod,
            onChainSubmissionPeriod,
            offChainSubmissionPeriodPerOperator,
            onChainSubmissionPeriodPerOperator
        )
    {}

    function _calculateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice,
        uint256 numOfOperators
    ) internal view override returns (uint256) {
        return
            (gasPrice *
                (callbackGasLimit + (21119 * numOfOperators + 134334))) +
            s_flatFee;
    }
}
