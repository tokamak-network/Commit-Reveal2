// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {CommitReveal2} from "./../../src/CommitReveal2.sol";
// import {BaseTest} from "./../shared/BaseTest.t.sol";
// import {console2, Vm} from "forge-std/Test.sol";
// import {Sort} from "./../shared/Sort.sol";
// import {CommitReveal2Helper} from "./../shared/CommitReveal2Helper.sol";
// import {DeployCommitReveal2} from "./../../script/DeployCommitReveal2.s.sol";
// import {DeployConsumerExample} from "./../../script/DeployConsumerExample.s.sol";

// contract CommitReveal2FlowTest is BaseTest, CommitReveal2Helper {
//     function setUp() public override {
//         BaseTest.setUp(); // startPrank the LEADERNODE and deal it some ether
//         if (block.chainid == 31337) vm.txGasPrice(10 gwei);

//         vm.stopPrank();
//         address commitReveal2Address;
//         (commitReveal2Address, s_networkHelperConfig) = (new DeployCommitReveal2()).run();
//         s_commitReveal2 = CommitReveal2(commitReveal2Address);
//         s_activeNetworkConfig = s_networkHelperConfig.getActiveNetworkConfig();
//         s_consumerExample = (new DeployConsumerExample()).deployConsumerExampleUsingConfig(address(s_commitReveal2));

//         s_anyAddress = makeAddr("any");
//         vm.deal(s_anyAddress, 10000 ether);
//     }

//     function test_whenNoActivatedOperators() public {}
// }
