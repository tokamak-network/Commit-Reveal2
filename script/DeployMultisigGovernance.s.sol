// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {MultisigWallet} from "../src/governance/MultisigWallet.sol";
import {CommitReveal2L2} from "../src/CommitReveal2L2.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";

contract DeployMultisigGovernance is Script {
    struct GovernanceConfig {
        address[] signers;
        uint256 requiredConfirmations;
        uint256 minDelay;
    }
    
    function getGovernanceConfig() public pure returns (GovernanceConfig memory) {
        address[] memory signers = new address[](5);
        
        signers[0] = 0x1234567890123456789012345678901234567890;
        signers[1] = 0x2345678901234567890123456789012345678901; 
        signers[2] = 0x3456789012345678901234567890123456789012;
        signers[3] = 0x4567890123456789012345678901234567890123;
        signers[4] = 0x5678901234567890123456789012345678901234;
        
        return GovernanceConfig({
            signers: signers,
            requiredConfirmations: 3,
            minDelay: 48 hours
        });
    }
    
    function run() public returns (MultisigWallet multisigWallet, CommitReveal2L2 commitReveal2L2) {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        NetworkHelperConfig.NetworkConfig memory activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();
        GovernanceConfig memory govConfig = getGovernanceConfig();
        
        vm.startBroadcast(activeNetworkConfig.deployer);
        
        multisigWallet = new MultisigWallet(
            govConfig.signers,
            govConfig.requiredConfirmations,
            govConfig.minDelay
        );
        
        commitReveal2L2 = new CommitReveal2L2{value: activeNetworkConfig.activationThreshold}(
            activeNetworkConfig.activationThreshold,
            activeNetworkConfig.flatFee,
            activeNetworkConfig.name,
            activeNetworkConfig.version,
            activeNetworkConfig.offChainSubmissionPeriod,
            activeNetworkConfig.requestOrSubmitOrFailDecisionPeriod,
            activeNetworkConfig.onChainSubmissionPeriod,
            activeNetworkConfig.offChainSubmissionPeriodPerOperator,
            activeNetworkConfig.onChainSubmissionPeriodPerOperator,
            activeNetworkConfig.maxGasPrice,
            address(multisigWallet.timelock())
        );
        
        vm.stopBroadcast();
        
        console2.log("MultisigWallet deployed at:", address(multisigWallet));
        console2.log("Timelock deployed at:", address(multisigWallet.timelock()));
        console2.log("CommitReveal2L2 deployed at:", address(commitReveal2L2));
        console2.log("Required confirmations:", govConfig.requiredConfirmations);
        console2.log("Min delay (hours):", govConfig.minDelay / 3600);
        console2.log("Number of authorized signers:", govConfig.signers.length);
        
        for (uint256 i = 0; i < govConfig.signers.length; i++) {
            console2.log("Signer", i + 1, ":", govConfig.signers[i]);
        }
    }
}