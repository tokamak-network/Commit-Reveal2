// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {BaseTest} from "./../test/shared/BaseTest.t.sol";
import {IOVM_GasPriceOracle} from "../src/IOVM_GasPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract NetworkHelperConfig is Script, BaseTest {
    address public s_deployer;

    struct NetworkConfig {
        uint256 activationThreshold;
        uint256 flatFee;
        string name;
        string version;
        bytes32 nameHash;
        bytes32 versionHash;
        uint256 offChainSubmissionPeriod;
        uint256 requestOrSubmitOrFailDecisionPeriod;
        uint256 onChainSubmissionPeriod;
        uint256 offChainSubmissionPeriodPerOperator;
        uint256 onChainSubmissionPeriodPerOperator;
        address deployer;
    }

    NetworkConfig private activeNetworkConfig;

    constructor() {
        string memory key = "DEPLOYER";
        if (vm.envExists(key)) {
            s_deployer = vm.envAddress(key);
        } else {
            s_deployer = LEADERNODE;
            console2.log("You didn't set the DEPLOYER env variable, using default");
        }

        uint256 chainId = block.chainid;
        if (chainId == 111551119090) {
            activeNetworkConfig = getThanosSepoliaConfig();
        } else if (chainId == 31337) {
            vm.deal(s_deployer, 10000 ether);
            activeNetworkConfig = getAnvilConfig();
        } else if (chainId == 11155420) {
            activeNetworkConfig = getOpSepoliaConfig();
        } else if (chainId == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        }
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        string memory name = "Commit Reveal2";
        string memory version = "1";
        return NetworkConfig({
            activationThreshold: 0.01 ether,
            flatFee: 0.001 ether,
            name: name,
            version: version,
            nameHash: keccak256(bytes(name)),
            versionHash: keccak256(bytes(version)),
            offChainSubmissionPeriod: 80,
            requestOrSubmitOrFailDecisionPeriod: 60,
            onChainSubmissionPeriod: 120,
            offChainSubmissionPeriodPerOperator: 20,
            onChainSubmissionPeriodPerOperator: 40,
            deployer: LEADERNODE
        });
    }

    function getThanosSepoliaConfig() public view returns (NetworkConfig memory) {
        string memory name = "Commit Reveal2";
        string memory version = "1";
        return NetworkConfig({
            activationThreshold: 0.01 ether,
            flatFee: 0.001 ether,
            name: name,
            version: version,
            nameHash: keccak256(bytes(name)),
            versionHash: keccak256(bytes(version)),
            offChainSubmissionPeriod: 80,
            requestOrSubmitOrFailDecisionPeriod: 60,
            onChainSubmissionPeriod: 120,
            offChainSubmissionPeriodPerOperator: 20,
            onChainSubmissionPeriodPerOperator: 40,
            deployer: s_deployer
        });
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        string memory name = "Commit Reveal2";
        string memory version = "1";
        return NetworkConfig({
            activationThreshold: 0.01 ether,
            flatFee: 0.001 ether,
            name: name,
            version: version,
            nameHash: keccak256(bytes(name)),
            versionHash: keccak256(bytes(version)),
            offChainSubmissionPeriod: 80,
            requestOrSubmitOrFailDecisionPeriod: 60,
            onChainSubmissionPeriod: 120,
            offChainSubmissionPeriodPerOperator: 20,
            onChainSubmissionPeriodPerOperator: 40,
            deployer: s_deployer
        });
    }

    function getOpSepoliaConfig() public view returns (NetworkConfig memory) {
        string memory name = "Commit Reveal2";
        string memory version = "1";
        return NetworkConfig({
            activationThreshold: 0.01 ether,
            flatFee: 0.001 ether,
            name: name,
            version: version,
            nameHash: keccak256(bytes(name)),
            versionHash: keccak256(bytes(version)),
            offChainSubmissionPeriod: 80,
            requestOrSubmitOrFailDecisionPeriod: 60,
            onChainSubmissionPeriod: 120,
            offChainSubmissionPeriodPerOperator: 20,
            onChainSubmissionPeriodPerOperator: 40,
            deployer: s_deployer
        });
    }
}
