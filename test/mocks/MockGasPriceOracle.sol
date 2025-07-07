// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MockPredeploys} from "./MockPredeploys.sol";
import {IL1Block} from "./IL1Block.sol";

// https://github.com/ethereum-optimism/optimism/blob/14671690cd1fe79c5dc14127f80158d1d9ed301a/packages/contracts-bedrock/src/L2/GasPriceOracle.sol#L4
contract MockGasPriceOracle {
    /// @notice Indicates whether the network has gone through the Fjord upgrade.
    bool public isFjord = true;

    /// @notice Number of decimals used in the scalar.
    uint256 public constant DECIMALS = 6;

    /// @notice This is the intercept value for the linear regression used to estimate the final size of the
    ///         compressed transaction.
    int32 private constant COST_INTERCEPT = -42_585_600;

    /// @notice This is the coefficient value for the linear regression used to estimate the final size of the
    ///         compressed transaction.
    uint32 private constant COST_FASTLZ_COEF = 836_500;

    /// @notice This is the minimum bound for the fastlz to brotli size estimation. Any estimations below this
    ///         are set to this value.
    uint256 private constant MIN_TRANSACTION_SIZE = 100;

    /// @notice Retrieves the current base fee scalar.
    /// @return Current base fee scalar.
    function baseFeeScalar() public view returns (uint32) {
        return IL1Block(MockPredeploys.L1_BLOCK_ATTRIBUTES).baseFeeScalar();
    }

    /// @notice Retrieves the latest known L1 base fee.
    /// @return Latest known L1 base fee.
    function l1BaseFee() public view returns (uint256) {
        return IL1Block(MockPredeploys.L1_BLOCK_ATTRIBUTES).basefee();
    }

    /// @notice Retrieves the current blob base fee scalar.
    /// @return Current blob base fee scalar.
    function blobBaseFeeScalar() public view returns (uint32) {
        return IL1Block(MockPredeploys.L1_BLOCK_ATTRIBUTES).blobBaseFeeScalar();
    }

    /// @notice Retrieves the current blob base fee.
    /// @return Current blob base fee.
    function blobBaseFee() public view returns (uint256) {
        return IL1Block(MockPredeploys.L1_BLOCK_ATTRIBUTES).blobBaseFee();
    }

    /// @notice returns an upper bound for the L1 fee for a given transaction size.
    /// It is provided for callers who wish to estimate L1 transaction costs in the
    /// write path, and is much more gas efficient than `getL1Fee`.
    /// It assumes the worst case of fastlz upper-bound which covers %99.99 txs.
    /// @param _unsignedTxSize Unsigned fully RLP-encoded transaction size to get the L1 fee for.
    /// @return L1 estimated upper-bound fee that should be paid for the tx
    function getL1FeeUpperBound(uint256 _unsignedTxSize) external view returns (uint256) {
        require(isFjord, "GasPriceOracle: getL1FeeUpperBound only supports Fjord");

        // Add 68 to the size to account for unsigned tx:
        uint256 txSize = _unsignedTxSize + 68;
        // txSize / 255 + 16 is the practical fastlz upper-bound covers %99.99 txs.
        uint256 flzUpperBound = txSize + txSize / 255 + 16;

        return _fjordL1Cost(flzUpperBound);
    }

    /// @notice Fjord L1 cost based on the compressed and original tx size.
    /// @param _fastLzSize estimated compressed tx size.
    /// @return Fjord L1 fee that should be paid for the tx
    function _fjordL1Cost(uint256 _fastLzSize) internal view returns (uint256) {
        // Apply the linear regression to estimate the Brotli 10 size
        uint256 estimatedSize = _fjordLinearRegression(_fastLzSize);
        uint256 feeScaled = baseFeeScalar() * 16 * l1BaseFee() + blobBaseFeeScalar() * blobBaseFee();
        return estimatedSize * feeScaled / (10 ** (DECIMALS * 2));
    }

    /// @notice Takes the fastLz size compression and returns the estimated Brotli
    /// @param _fastLzSize fastlz compressed tx size.
    /// @return Number of bytes in the compressed transaction
    function _fjordLinearRegression(uint256 _fastLzSize) internal pure returns (uint256) {
        int256 estimatedSize = COST_INTERCEPT + int256(COST_FASTLZ_COEF * _fastLzSize);
        if (estimatedSize < int256(MIN_TRANSACTION_SIZE) * 1e6) {
            estimatedSize = int256(MIN_TRANSACTION_SIZE) * 1e6;
        }
        return uint256(estimatedSize);
    }
}
