// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {CommitReveal2Storage} from "./../../src/CommitReveal2Storage.sol";
import {Test} from "forge-std/Test.sol";

contract ForkTest is Test {
    address public s_sender = 0x96C0691Bed8BC1EBd9d49f985473017fd570102C;
    CommitReveal2 public s_commitReveal2 = CommitReveal2(0x61D472659cBceB6E9483d5d9B95d0dC6D50C950E);
    uint256 public s_sepoliaFork;
    // https://sepolia.etherscan.io/tx/0x260a4fcfe2d712f89ec3dc2e7e09d7443003beee8cc718738a34371257062148
    uint256 public s_blockNumber = 8517980;

    bytes32 public s_cv = 0xc30876c88e2946f47393236836e423fc9e289545107fad4f32b4b0a58e47377a;
    bytes32 public s_r = 0x1b083d77803f8a0938fd4d4764c13ca51e08645a05b6424bb949132d6a38c422;
    bytes32 public s_s = 0x5b84e8663781a3e7f0786559534e5f8467a86a8933504a755b6c920093bebe6e;
    uint256 public s_packedVs = 28;
    uint256 public s_indicesLength = 1;
    uint256 public s_packedIndicesFirstCvNotOnChainRestCvOnChain = 0;

    function setUp() public {
        string memory sepoliaRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        s_sepoliaFork = vm.createFork(sepoliaRpcUrl, s_blockNumber);
        vm.selectFork(s_sepoliaFork);
        vm.startPrank(s_sender);
    }

    function test_requestToSubmitCo() public {
        CommitReveal2Storage.CvAndSigRS[] memory cvAndSigRSs = new CommitReveal2Storage.CvAndSigRS[](1);
        cvAndSigRSs[0] = CommitReveal2Storage.CvAndSigRS({cv: s_cv, rs: CommitReveal2Storage.SigRS({r: s_r, s: s_s})});

        s_commitReveal2.requestToSubmitCo(
            cvAndSigRSs, s_packedVs, s_indicesLength, s_packedIndicesFirstCvNotOnChainRestCvOnChain
        );
    }
}
