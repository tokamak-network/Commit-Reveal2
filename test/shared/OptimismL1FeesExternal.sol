// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OptimismL1Fees} from "../../src/OptimismL1Fees.sol";

contract OptimismL1FeesExternal is OptimismL1Fees {
    constructor() Ownable(msg.sender) {}

    function getL1CostWeiForCalldataSize(
        uint256 calldataSize
    ) external view returns (uint256) {
        return _getL1CostWeiForCalldataSize(calldataSize);
    }

    function getL1CostLegacy(
        uint256 calldataSize
    ) external view returns (uint256) {
        return _calculateLegacyL1DataFee(calldataSize);
    }
}
