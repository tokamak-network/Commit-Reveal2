// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../CommitReveal2.sol";

contract CommitReveal2L1 is CommitReveal2 {
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
    )
        CommitReveal2(
            activationThreshold,
            flatFee,
            maxActivatedOperators,
            name,
            version,
            phase1StartOffset,
            phase2StartOffset,
            phase3StartOffset,
            phase4StartOffset,
            phase5StartOffset,
            phase6StartOffset,
            phase7StartOffset,
            phase8StartOffset,
            phase9StartOffset,
            phase10StartOffset
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
