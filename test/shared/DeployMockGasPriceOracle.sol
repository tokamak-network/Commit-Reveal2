// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MockL1Block} from "../mocks/MockL1Block.sol";
import {MockGasPriceOracle} from "../mocks/MockGasPriceOracle.sol";
import {MockPredeploys} from "../mocks/MockPredeploys.sol";
import {Test} from "forge-std/Test.sol";

contract DeployMockGasPriceOracle is Test {
    function deployMockGasPriceOracle() public {
        vm.record();
        MockL1Block l1Block = new MockL1Block();
        (, bytes32[] memory writes) = vm.accesses(address(l1Block));
        vm.etch(MockPredeploys.L1_BLOCK_ATTRIBUTES, address(l1Block).code);
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(MockPredeploys.L1_BLOCK_ATTRIBUTES), slot, vm.load(address(l1Block), slot));
            }
        }

        vm.record();
        MockGasPriceOracle gasPriceOracle = new MockGasPriceOracle();
        (, bytes32[] memory writes2) = vm.accesses(address(gasPriceOracle));
        vm.etch(MockPredeploys.GAS_PRICE_ORACLE, address(gasPriceOracle).code);
        unchecked {
            for (uint256 i = 0; i < writes2.length; i++) {
                bytes32 slot = writes2[i];
                vm.store(address(MockPredeploys.GAS_PRICE_ORACLE), slot, vm.load(address(gasPriceOracle), slot));
            }
        }
    }
}
