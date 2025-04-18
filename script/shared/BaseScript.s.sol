// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sort} from "../../test/shared/Sort.sol";

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Script, console2} from "forge-std/Script.sol";
import {CommitReveal2Helper, CommitReveal2Storage} from "./../../test/shared/CommitReveal2Helper.sol";
import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {NetworkHelperConfig} from "./../NetworkHelperConfig.s.sol";

contract BaseScript is Script, CommitReveal2Helper {
    uint256[2] public s_privateKeys;
    address[2] public s_operators;
    uint256 s_activationThreshold;

    function scriptSetUp() public {
        s_numOfOperators = 2;
        // *** Get the most recent deployment of CommitReveal2 ***
        // ** //////////////////////////////////////////////// **
        string memory contractName =
            (block.chainid == 31337 || block.chainid == 11155111) ? "CommitReveal2L1" : "CommitReveal2";
        s_commitReveal2 = CommitReveal2(DevOpsTools.get_most_recent_deployment(contractName, block.chainid));
        console2.log("commitReveal2", address(s_commitReveal2));

        // *** Get most recent deployment of ConsumerExample **
        // ** //////////////////////////////////////////////// **
        s_consumerExample =
            ConsumerExample(payable(DevOpsTools.get_most_recent_deployment("ConsumerExample", block.chainid)));
        console2.log("consumerExample", address(s_consumerExample));

        // *** Get accounts ***
        // ** //////////////////////////////////////////////// **
        string[2] memory keys = ["PRIVATE_KEY2", "PRIVATE_KEY3"];
        s_privateKeys = [uint256(vm.envBytes32(keys[0])), uint256(vm.envBytes32(keys[1]))];
        s_operators = [vm.addr(s_privateKeys[0]), vm.addr(s_privateKeys[1])];
        s_activationThreshold = s_commitReveal2.s_activationThreshold();
        console2.log("activationThreshold %e", s_activationThreshold);

        // *** Set CommitReveal2Helper states
        // ** //////////////////////////////////////////////// **
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        s_activeNetworkConfig = networkHelperConfig.getActiveNetworkConfig();
    }

    function generateSCoCv() public {
        // ** Off-chain: Cvi Submission
        // ** //////////////////////////////////////////////// **
        (, s_startTimestamp,,) = s_commitReveal2.s_requestInfo(s_commitReveal2.s_currentRound());

        s_secrets = new bytes32[](s_operators.length);
        s_cos = new bytes32[](s_operators.length);
        s_cvs = new bytes32[](s_operators.length);
        s_vs = new uint8[](s_operators.length);
        s_rs = new bytes32[](s_operators.length);
        s_ss = new bytes32[](s_operators.length);

        s_secretSigRSs = new CommitReveal2.SecretAndSigRS[](s_operators.length);
        s_packedVs = 0;
        s_packedRevealOrders = 0;

        for (uint256 i; i < s_operators.length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv();
            (s_vs[i], s_rs[i], s_ss[i]) = vm.sign(s_privateKeys[i], _getTypedDataHash(s_startTimestamp, s_cvs[i]));

            uint256 v = uint256(s_vs[i]);
            s_packedVs = s_packedVs | (v << (i * 8));
            s_secretSigRSs[i] = CommitReveal2Storage.SecretAndSigRS({
                secret: s_secrets[i],
                rs: CommitReveal2Storage.SigRS({r: s_rs[i], s: s_ss[i]})
            });
        }

        // *** Set Reveal Orders
        uint256[] memory diffs = new uint256[](s_operators.length);
        uint256[] memory revealOrders = new uint256[](s_operators.length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < s_operators.length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);
        for (uint256 i; i < s_operators.length; i++) {
            s_packedRevealOrders = s_packedRevealOrders | (revealOrders[i] << (i * 8));
        }
    }
}
