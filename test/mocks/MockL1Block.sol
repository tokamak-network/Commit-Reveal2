// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// The initial L1 context values
// https://github.com/ethereum-optimism/optimism/blob/14671690cd1fe79c5dc14127f80158d1d9ed301a/packages/contracts-bedrock/test/L2/GasPriceOracle.t.sol#L18-L31
contract MockL1Block {
    /// @notice The scalar value applied to the L1 blob base fee portion of the blob-capable L1 cost func.
    uint32 public blobBaseFeeScalar = 15;

    /// @notice The scalar value applied to the L1 base fee portion of the blob-capable L1 cost func.
    uint32 public baseFeeScalar = 20;

    /// @notice The latest L1 base fee.
    uint256 public basefee = 2 * (10 ** 6);

    /// @notice The latest L1 blob base fee.
    uint256 public blobBaseFee = 3 * (10 ** 6);
}
