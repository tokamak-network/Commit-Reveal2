// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {BaseTest} from "./../test/shared/BaseTest.t.sol";
import {IOVM_GasPriceOracle} from "../src/IOVM_GasPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NetworkHelperConfig is Script, BaseTest {
    struct NetworkConfig {
        uint256 activationThreshold;
        uint256 flatFee;
        uint256 maxActivatedOperators;
        string name;
        string version;
        uint256[11] phaseDuration;
        address deployer;
    }

    NetworkConfig private activeNetworkConfig;

    constructor() {
        uint256 chainId = block.chainid;
        if (chainId == 111551119090)
            activeNetworkConfig = getThanosSepoliaConfig();
        else if (chainId == 31337) activeNetworkConfig = getAnvilConfig();
    }

    function getActiveNetworkConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return activeNetworkConfig;
    }

    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        uint256[11] memory phaseDuration;
        phaseDuration[0] = 60;
        phaseDuration[1] = 60;
        phaseDuration[2] = 60;
        phaseDuration[3] = 60;
        phaseDuration[4] = 60;
        phaseDuration[5] = 60;
        phaseDuration[6] = 60;
        phaseDuration[7] = 60;
        phaseDuration[8] = 60;
        phaseDuration[9] = 60;
        phaseDuration[10] = 60;
        return
            NetworkConfig({
                activationThreshold: 0.1 ether,
                flatFee: 0.01 ether,
                maxActivatedOperators: 10,
                name: "Commit Reveal2",
                version: "1",
                phaseDuration: phaseDuration,
                deployer: LEADERNODE
            });
    }

    function getThanosSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        uint256[11] memory phaseDuration;
        phaseDuration[0] = 60;
        phaseDuration[1] = 60;
        phaseDuration[2] = 60;
        phaseDuration[3] = 60;
        phaseDuration[4] = 60;
        phaseDuration[5] = 60;
        phaseDuration[6] = 60;
        phaseDuration[7] = 60;
        phaseDuration[8] = 60;
        phaseDuration[9] = 60;
        phaseDuration[10] = 60;
        return
            NetworkConfig({
                activationThreshold: 0.1 ether,
                flatFee: 0.01 ether,
                maxActivatedOperators: 10,
                name: "Commit Reveal2",
                version: "1",
                phaseDuration: phaseDuration,
                deployer: 0xB68AA9E398c054da7EBAaA446292f611CA0CD52B
            });
    }
}
