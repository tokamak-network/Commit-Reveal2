// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OperatorDepositManager} from "./../../src/test/OperatorDepositManager.sol";
import {BaseTest} from "./../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";

contract OperatorDepositManagerTest is BaseTest {
    OperatorDepositManager public s_operatorDepositManager;

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(10 gwei);
        s_operatorDepositManager = new OperatorDepositManager(0.1 ether, 10);
    }

    function test_slashing() public {
        // *** 10 operators deposit 0.1 ether
        vm.stopPrank();
        for (uint256 i; i < 10; ++i) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_operatorDepositManager.deposit{value: 0.1 ether}();
            s_operatorDepositManager.activate();
            vm.stopPrank();
        }
        // 1 ether is deposited in total

        // *** 5 operators are slashed
        address[] memory slashedList = new address[](5);
        for (uint256 i; i < 5; ++i) {
            slashedList[i] = s_anvilDefaultAddresses[i];
        }
        s_operatorDepositManager.slash(slashedList);

        // *** check deposit amount
        // for (uint256 i; i < 10; i++) {
        //     vm.startPrank(s_anvilDefaultAddresses[i]);
        //     console2.log(s_operatorDepositManager.claimSlashReward());
        // }

        // *** 5 operators deposit and activate again
        for (uint256 i; i < 5; ++i) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_operatorDepositManager.depositAndActivate{value: 0.1 ether}();
            vm.stopPrank();
        }

        // 1.5 ether is deposited in total

        // *** 5 operators are slashed again
        for (uint256 i; i < 5; ++i) {
            slashedList[i] = s_anvilDefaultAddresses[i];
        }
        s_operatorDepositManager.slash(slashedList);

        // *** check deposit amount
        // for (uint256 i; i < 10; i++) {
        //     vm.startPrank(s_anvilDefaultAddresses[i]);
        //     console2.log(s_operatorDepositManager.withdraw());
        //     vm.stopPrank();
        // }

        // *** 5 operators deposit and activate again
        for (uint256 i; i < 5; ++i) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            s_operatorDepositManager.depositAndActivate{value: 0.1 ether}();
            vm.stopPrank();
        }
        // 2 ether is deposited in total

        // *** last 5 operators are slashed
        for (uint256 i = 5; i < 10; ++i) {
            slashedList[i - 5] = s_anvilDefaultAddresses[i];
        }
        s_operatorDepositManager.slash(slashedList);

        // *** check deposit amount
        for (uint256 i; i < 10; i++) {
            vm.startPrank(s_anvilDefaultAddresses[i]);
            console2.log(s_operatorDepositManager.withdraw());
            vm.stopPrank();
        }
    }
}
