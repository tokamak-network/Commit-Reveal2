// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {IOVM_GasPriceOracle} from "./IOVM_GasPriceOracle.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

abstract contract OptimismL1Fees is Owned {
    /// @dev This is the padding size for unsigned RLP-encoded transaction without the signature data
    /// @dev The padding size was estimated based on hypothetical max RLP-encoded transaction size
    uint256 private constant L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE = 71;

    /// @dev OVM_GASPRICEORACLE_ADDR is the address of the OVM_GasPriceOracle precompile on Optimism.
    /// @dev reference: https://community.optimism.io/docs/developers/build/transaction-fees/#estimating-the-l1-data-fee
    address private constant OVM_GASPRICEORACLE_ADDR =
        address(0x420000000000000000000000000000000000000F);
    IOVM_GasPriceOracle private constant OVM_GASPRICEORACLE =
        IOVM_GasPriceOracle(OVM_GASPRICEORACLE_ADDR);

    /// @dev L1 fee coefficient can be applied to reduce possibly inflated gas price
    uint8 public s_l1FeeCoefficient = 100;

    error InvalidL1FeeCoefficient(uint8 coefficient);

    event L1FeeCalculationSet(uint8 coefficient);

    function setL1FeeCoefficient(uint8 coefficient) external virtual onlyOwner {
        _setL1FeeCoefficientInternal(coefficient);
    }

    function _setL1FeeCoefficientInternal(uint8 coefficient) internal {
        if (coefficient == 0 || coefficient > 100) {
            revert InvalidL1FeeCoefficient(coefficient);
        }
        s_l1FeeCoefficient = coefficient;
        emit L1FeeCalculationSet(coefficient);
    }

    function _getL1CostWeiForCalldataSize(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
        return
            (s_l1FeeCoefficient *
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                )) / 100;
    }
}
