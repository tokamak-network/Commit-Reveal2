// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// import {BaseScript, console2} from "./shared/BaseScript.s.sol";
// import {Sort} from "./../test/shared/Sort.sol";
// import {CommitReveal2} from "./../src/CommitReveal2.sol";

// contract OperatorsActivateAndDeposit is BaseScript {
//     function run() public {
//         BaseScript.scriptSetUp();
//         for (uint256 i; i < s_numOfOperators; i++) {
//             console2.log("operator ", i);
//             console2.log("balance %e", s_operators[i].balance);
//             uint256 depositAmount = s_commitReveal2.s_depositAmount(s_operators[i]);
//             uint256 requiredDeposit = s_activationThreshold - depositAmount;
//             require(s_operators[i].balance >= requiredDeposit, "Insufficient balance");
//             if (depositAmount < s_activationThreshold) {
//                 console2.log("depositing %e...", requiredDeposit);
//                 vm.startBroadcast(s_privateKeys[i]);
//                 s_commitReveal2.depositAndActivate{value: requiredDeposit}();
//                 vm.stopBroadcast();
//                 console2.log("Deposit and activate successful");
//                 console2.log("----");
//             }
//         }
//     }
// }

// contract Withdraw is BaseScript {
//     function run() public {
//         BaseScript.scriptSetUp();
//         s_commitReveal2 = CommitReveal2(address(0xA87c2DE14Fc3F91e9E53854f3707b5e86cF7C3F7));
//         vm.startBroadcast();
//         s_commitReveal2.withdraw();
//         vm.stopBroadcast();
//         for (uint256 i; i < s_numOfOperators; i++) {
//             vm.startBroadcast(s_privateKeys[i]);
//             s_commitReveal2.withdraw();
//             vm.stopBroadcast();
//         }
//     }
// }

// contract SuccessfulPaths is BaseScript {
//     function run() public {
//         BaseScript.scriptSetUp();
//         // * a. 1 -> 2 -> 12
//         uint256 requestFee = s_commitReveal2.estimateRequestPrice(s_consumerExample.CALLBACK_GAS_LIMIT(), tx.gasprice);
//         console2.log("current gas fee:", tx.gasprice);
//         console2.log("requestFee %e", requestFee);

//         vm.startBroadcast();
//         s_consumerExample.requestRandomNumber{value: requestFee}();
//         vm.stopBroadcast();

//         // ** Off-chain: Cvi Submission
//         // ** //////////////////////////////////////////////// **
//         BaseScript.generateSCoCv();

//         // ** 2. submitMerkleRoot()
//         // ** //////////////////////////////////////////////// **
//         bytes32 merkleRoot = _createMerkleRoot(s_cvs);
//         vm.startBroadcast();
//         s_commitReveal2.submitMerkleRoot(merkleRoot);
//         vm.stopBroadcast();
//     }

//     function generateRandomNumber() public {
//         BaseScript.scriptSetUp();
//         BaseScript.generateSCoCv();
//         uint256[] memory diffs = new uint256[](s_operators.length);
//         uint256[] memory revealOrders = new uint256[](s_operators.length);
//         s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
//         for (uint256 i; i < s_operators.length; i++) {
//             diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
//             revealOrders[i] = i;
//         }
//         Sort.sort(diffs, revealOrders);
//         console2.log(s_startTimestamp, s_commitReveal2.s_isSubmittedMerkleRoot(s_startTimestamp));
//         // ** 12. generateRandomNumber();
//         // ** //////////////////////////////////////////////// **
//         vm.startBroadcast();
//         s_commitReveal2.generateRandomNumber(s_secrets, s_v, s_rs, s_ss, s_revealOrder);
//         vm.stopBroadcast();
//     }
// }
