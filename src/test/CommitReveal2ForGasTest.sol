// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitReveal2L2} from "../CommitReveal2L2.sol";

contract CommitReveal2ForGasTest is CommitReveal2L2 {
    constructor(
        uint256 activationThreshold,
        uint256 flatFee,
        string memory name,
        string memory version,
        uint256 offChainSubmissionPeriod,
        uint256 requestOrSubmitOrFailDecisionPeriod,
        uint256 onChainSubmissionPeriod,
        uint256 offChainSubmissionPeriodPerOperator,
        uint256 onChainSubmissionPeriodPerOperator
    )
        payable
        CommitReveal2L2(
            activationThreshold,
            flatFee,
            name,
            version,
            offChainSubmissionPeriod,
            requestOrSubmitOrFailDecisionPeriod,
            onChainSubmissionPeriod,
            offChainSubmissionPeriodPerOperator,
            onChainSubmissionPeriodPerOperator
        )
    {}

    function depositAndActivate() external payable override {
        assembly ("memory-safe") {
            mstore(0x00, caller())
            mstore(0x20, s_depositAmount.slot)
            let depositAmountSlot := keccak256(0x00, 0x40)
            let updatedDepositAmount := add(sload(depositAmountSlot), callvalue())
            if lt(updatedDepositAmount, sload(s_activationThreshold.slot)) {
                mstore(0x00, 0x5af30906) // `LessThanActivationThreshold()`.
                revert(0x1c, 0x04)
            }
            sstore(depositAmountSlot, updatedDepositAmount)
        }
        _activate();
    }
}
