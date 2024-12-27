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
        if (chainId == 111551119090)
            activeNetworkConfig = getThanosSepoliaConfig();
        else if (chainId == 11155420)
            activeNetworkConfig = getOptimismSepoliaConfig();
        else if (chainId == 11155111) activeNetworkConfig = getSepoliaConfig();
        else if (chainId == 31337) activeNetworkConfig = getAnvilConfig();
    }

    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        uint256 flatFee = 0.00025 ether;
        uint256 compensateAmount = 0.0005 ether;
        uint256 activationThreshold = 0.01 ether;

        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 3
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
        uint256 l1GasCost = _getL1CostWeiForcalldataSize2();

        // 345524 = (21119 * 10 + 134334)
        uint256 activationThreshold = fixedL2GasPrice *
            (MAX_CALLBACK_GAS_LIMIT + 345524) +
            l1GasCost +
            compensateAmount +
            flatFee;
        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 0
            });
    }

    function getOptimismSepoliaConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        uint256 maxL2GasPrice = 1000000000000; // 1000252 + buffer
        uint256 flatFee = 0.00001 ether;
        uint256 compensateAmount = 0.000005 ether;

        /// *** get L1 Gas
        uint256 l1GasCost = _getL1CostWeiForcalldataSize2();

        // 345524 = (21119 * 10 + 134334)
        uint256 activationThreshold = maxL2GasPrice *
            (MAX_CALLBACK_GAS_LIMIT + 345524) +
            l1GasCost +
            compensateAmount +
            flatFee;
        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 0
            });
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        uint256 flatFee = 0.00001 ether;
        uint256 compensateAmount = 0.000005 ether;
        uint256 activationThreshold = 0.01 ether;

        return
            NetworkConfig({
                activationThreshold: activationThreshold,
                compensateAmount: compensateAmount,
                flatFee: flatFee,
                l1GasCostMode: 3
            });
    }

    function _getL1CostWeiForcalldataSize2() private view returns (uint256) {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
        return
            OVM_GASPRICEORACLE.getL1FeeUpperBound(
                68 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
            ) +
            OVM_GASPRICEORACLE.getL1FeeUpperBound(
                1572 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
            ); // 1572 = 292 + (128 * 10)
    }
}
