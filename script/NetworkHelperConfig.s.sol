// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IOVM_GasPriceOracle} from "../src/IOVM_GasPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NetworkHelperConfig is Script {
    struct NetworkConfig {
        uint256 activationThreshold;
        uint256 compensateAmount;
        uint256 flatFee;
        uint256 l1GasCostMode;
        uint256 gameExpiry;
        IERC20 tonToken;
        uint256 reward;
    }
    address private constant OVM_GASPRICEORACLE_ADDR =
        address(0x420000000000000000000000000000000000000F);
    IOVM_GasPriceOracle internal constant OVM_GASPRICEORACLE =
        IOVM_GasPriceOracle(OVM_GASPRICEORACLE_ADDR);
    /// @dev This is the padding size for unsigned RLP-encoded transaction without the signature data
    /// @dev The padding size was estimated based on hypothetical max RLP-encoded transaction size
    uint256 internal constant L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE = 71;
    /// @dev Signature data size used in the GasPriceOracle predeploy
    /// @dev reference: https://github.com/ethereum-optimism/optimism/blob/a96cbe7c8da144d79d4cec1303d8ae60a64e681e/packages/contracts-bedrock/contracts/L2/GasPriceOracle.sol#L145
    uint256 internal constant L1_TX_SIGNATURE_DATA_BYTES_SIZE = 68;

    NetworkConfig public activeNetworkConfig;

    uint256 internal constant ONECOMMIT_ONEREVEAL_GASUSED = 255877;
    uint256 internal constant ONECOMMIT_ONEREVEAL_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant MAX_REQUEST_REFUND_GASUSED = 702530;
    uint256 internal constant REQUEST_REFUND_CALLDATA_BYTES_SIZE = 214;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal s_l1FeeCoefficient = 100;

    constructor() {
        uint256 chainId = block.chainid;
        if (chainId == 55007) activeNetworkConfig = getTitanSepoliaConfig();
        else if (chainId == 55004) activeNetworkConfig = getTitanConfig();
        else if (chainId == 111551119090)
            activeNetworkConfig = getThanosSepoliaConfig();
        else if (chainId == 31337) activeNetworkConfig = getAnvilConfig();
    }

    /// @dev native token ETH, Legacy network
    function getTitanSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        //uint256 fixedL2GasPrice = 1;
        uint256 flatFee = 0.00001 ether;
        uint256 compensateAmount = 0.000005 ether;

        /// *** get L1 Gas
        // uint256 l1GasCost = _calculateLegacyL1DataFee(
        //     ONECOMMIT_ONEREVEAL_CALLDATA_BYTES_SIZE
        // );

        // l1GasCost += _calculateLegacyL1DataFee(
        //     REQUEST_REFUND_CALLDATA_BYTES_SIZE
        // );

        // uint256 activationThreshold = fixedL2GasPrice *
        //     (ONECOMMIT_ONEREVEAL_GASUSED +
        //         MAX_CALLBACK_GAS_LIMIT +
        //         MAX_REQUEST_REFUND_GASUSED) +
        //     l1GasCost +
        //     compensateAmount +
        //     flatFee;
        uint256 activationThreshold = 0.001 ether;

        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 2,
                gameExpiry: 60 * 60 * 24,
                tonToken: IERC20(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2),
                reward: 100 ether
            });
    }

    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        uint256 flatFee = 0.00025 ether;
        uint256 compensateAmount = 0.0005 ether;
        // uint256 activationThreshold = tx.gasprice *
        //     (ONECOMMIT_ONEREVEAL_GASUSED +
        //         MAX_CALLBACK_GAS_LIMIT +
        //         MAX_REQUEST_REFUND_GASUSED) +
        //     compensateAmount +
        //     flatFee;
        uint256 activationThreshold = 0.01 ether;

        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 3,
                gameExpiry: 3600,
                tonToken: IERC20(address(0)),
                reward: 1000 ether
            });
    }

    function getThanosSepoliaConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        uint256 fixedL2GasPrice = 1000552; // 1000252 + buffer
        uint256 flatFee = 0.00001 ether;
        uint256 compensateAmount = 0.000005 ether;

        /// *** get L1 Gas
        uint256 l1GasCost = _calculateOptimismL1DataFee(
            ONECOMMIT_ONEREVEAL_CALLDATA_BYTES_SIZE +
                L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
        );
        l1GasCost += _calculateOptimismL1DataFee(
            REQUEST_REFUND_CALLDATA_BYTES_SIZE +
                L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
        );

        uint256 activationThreshold = fixedL2GasPrice *
            (ONECOMMIT_ONEREVEAL_GASUSED +
                MAX_CALLBACK_GAS_LIMIT +
                MAX_REQUEST_REFUND_GASUSED) +
            l1GasCost +
            compensateAmount +
            flatFee;
        return
            NetworkConfig({
                activationThreshold: 0.001 ether,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 0,
                gameExpiry: 60 * 60 * 24,
                tonToken: IERC20(address(0)),
                reward: 1000 ether
            });
    }

    function getTitanConfig() public view returns (NetworkConfig memory) {
        uint256 fixedL2GasPrice = 1003000; // 1000000 + buffer
        uint256 flatFee = 0.00025 ether;
        uint256 compensateAmount = 0.00015 ether;

        /// *** get L1 Gas
        uint256 l1GasCost = _calculateLegacyL1DataFee(
            ONECOMMIT_ONEREVEAL_CALLDATA_BYTES_SIZE
        );
        l1GasCost += _calculateLegacyL1DataFee(
            REQUEST_REFUND_CALLDATA_BYTES_SIZE
        );

        uint256 activationThreshold = fixedL2GasPrice *
            (ONECOMMIT_ONEREVEAL_GASUSED +
                MAX_CALLBACK_GAS_LIMIT +
                MAX_REQUEST_REFUND_GASUSED) +
            l1GasCost +
            compensateAmount +
            flatFee;
        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 2,
                gameExpiry: 60 * 60 * 24,
                tonToken: IERC20(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2),
                reward: 1000 ether
            });
    }

    function _calculateLegacyL1DataFee(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        uint256 l1GasUsed = (calldataSizeBytes +
            L1_TX_SIGNATURE_DATA_BYTES_SIZE) *
            16 +
            OVM_GASPRICEORACLE.overhead();
        uint256 l1Fee = l1GasUsed * OVM_GASPRICEORACLE.l1BaseFee();
        uint256 divisor = 10 ** OVM_GASPRICEORACLE.decimals();
        uint256 unscaled = l1Fee * OVM_GASPRICEORACLE.scalar();
        uint256 scaled = unscaled / divisor;
        return scaled;
    }

    function _calculateOptimismL1DataFee(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        // reference: https://docs.optimism.io/stack/transactions/fees#ecotone
        // also: https://github.com/ethereum-optimism/specs/blob/main/specs/protocol/exec-engine.md#ecotone-l1-cost-fee-changes-eip-4844-da
        // we treat all bytes in the calldata payload as non-zero bytes (cost: 16 gas) because accurate estimation is too expensive
        // we also have to account for the signature data size
        uint256 l1GasUsed = (calldataSizeBytes +
            L1_TX_SIGNATURE_DATA_BYTES_SIZE) * 16;
        uint256 scaledBaseFee = OVM_GASPRICEORACLE.baseFeeScalar() *
            16 *
            OVM_GASPRICEORACLE.l1BaseFee();
        uint256 scaledBlobBaseFee = OVM_GASPRICEORACLE.blobBaseFeeScalar() *
            OVM_GASPRICEORACLE.blobBaseFee();
        uint256 fee = l1GasUsed * (scaledBaseFee + scaledBlobBaseFee);
        return
            (s_l1FeeCoefficient *
                (fee / (16 * 10 ** OVM_GASPRICEORACLE.decimals()))) / 100;
    }
}
