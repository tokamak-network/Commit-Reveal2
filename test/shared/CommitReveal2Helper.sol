// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommitReveal2} from "./../../src/CommitReveal2.sol";
import {CommitReveal2Storage} from "./../../src/CommitReveal2Storage.sol";
import {NetworkHelperConfig} from "./../../script/NetworkHelperConfig.s.sol";
import {console2, Test} from "forge-std/Test.sol";
import {Bitmap} from "../../src/libraries/Bitmap.sol";
import {ConsumerExample} from "./../../src/ConsumerExample.sol";
import {Sort} from "./Sort.sol";

contract CommitReveal2Helper is Test {
    // ** Contracts
    CommitReveal2 public s_commitReveal2;
    ConsumerExample public s_consumerExample;
    NetworkHelperConfig.NetworkConfig public s_activeNetworkConfig;
    NetworkHelperConfig public s_networkHelperConfig;

    uint256 private s_nonce;

    // ** Variables for Testing
    uint256 public s_requestFee;
    uint256 public s_startTimestamp;
    bytes32[] public s_secrets;
    bytes32[] public s_cos;
    bytes32[] public s_cvs;
    uint8[] public s_vs;
    bytes32[] public s_rs;
    bytes32[] public s_ss;
    uint256 public s_rv;
    bool public s_fulfilled;
    uint256 public s_randomNumber;
    address[] public s_activatedOperators;
    uint256[] public s_depositAmounts;
    address public s_anyAddress;
    uint256 public s_numOfOperators;

    // ** requestToSubmitS
    bytes32[] public s_secretsReceivedOffchainInRevealOrder;
    uint256 public s_packedVsForAllCvsNotOnChain;
    CommitReveal2.SigRS[] public s_sigRSsForAllCvsNotOnChain;

    // ** generate random number
    CommitReveal2.SecretAndSigRS[] public s_secretSigRSs;
    uint256 public s_packedVs;
    uint256 public s_packedRevealOrders;

    // ** requestToSubmitCo
    CommitReveal2.CvAndSigRS[] public s_cvRSsForCvsNotOnChainAndReqToSubmitCo;
    //uint256 public s_packedVsForAllCvsNotOnChain;
    uint256 s_indicesLength;
    uint256 s_indicesFirstCvNotOnChainRestCvOnChain;

    // ** requestToSubmitCv
    uint256 public s_packedIndices;

    // ** Variables for Dispute
    uint256[] public s_tempArray;
    uint256[] public s_indicesFirstCvNotOnChainRestCvOnChainArrayTemp;
    uint256[] public s_tempVs;

    uint256 public s_activatedOperatorsLength;
    uint256 public s_lastRequestId;
    uint256 public s_currentRound;
    uint256 public s_currentTrialNum;

    function _packArrayIntoUint256(uint256[] storage arr) internal view returns (uint256 packed) {
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; i++) {
            packed |= (arr[i] << (i * 8));
        }
    }

    function _createMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = _unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function _unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    function _efficientKeccak256(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _generateSCoCv(uint256 startTimestamp) internal returns (bytes32 s, bytes32 co, bytes32 cv) {
        s = keccak256(abi.encodePacked(s_nonce++, startTimestamp));
        co = keccak256(abi.encodePacked(s));
        cv = keccak256(abi.encodePacked(co));
    }

    function _setSCoCvRevealOrders(mapping(address => uint256) storage privatekeys)
        internal
        returns (uint256[] memory revealOrders)
    {
        s_startTimestamp = s_commitReveal2.getCurStartTime();
        s_activatedOperators = s_commitReveal2.getActivatedOperators();
        (s_currentRound, s_currentTrialNum) = s_commitReveal2.getCurRoundAndTrialNum();
        // *** Generate S, Co, Cv, Signatures
        uint256[] memory privateKeys = new uint256[](s_activatedOperators.length);
        for (uint256 i; i < s_activatedOperators.length; i++) {
            privateKeys[i] = privatekeys[s_activatedOperators[i]];
        }
        revealOrders = _setSCoCv(s_activatedOperators.length, privateKeys);
    }

    function _setSCoCv(uint256 length, uint256[] memory privatekeys) internal returns (uint256[] memory revealOrders) {
        s_secrets = new bytes32[](length);
        s_cos = new bytes32[](length);
        s_cvs = new bytes32[](length);
        s_vs = new uint8[](length);
        s_rs = new bytes32[](length);
        s_ss = new bytes32[](length);
        s_secretSigRSs = new CommitReveal2.SecretAndSigRS[](length);
        s_packedVs = 0;
        s_packedRevealOrders = 0;

        for (uint256 i; i < length; i++) {
            (s_secrets[i], s_cos[i], s_cvs[i]) = _generateSCoCv(s_startTimestamp);
            (s_vs[i], s_rs[i], s_ss[i]) =
                vm.sign(privatekeys[i], _getTypedDataHashV4(s_currentRound, s_currentTrialNum, s_cvs[i]));
            uint256 v = uint256(s_vs[i]);
            s_packedVs = s_packedVs | (v << (i * 8));
            s_secretSigRSs[i] = CommitReveal2Storage.SecretAndSigRS({
                secret: s_secrets[i],
                rs: CommitReveal2Storage.SigRS({r: s_rs[i], s: s_ss[i]})
            });
        }
        // *** Set Reveal Orders
        uint256[] memory diffs = new uint256[](length);
        revealOrders = new uint256[](length);
        s_rv = uint256(keccak256(abi.encodePacked(s_cos)));
        for (uint256 i; i < length; i++) {
            diffs[i] = _diff(s_rv, uint256(s_cvs[i]));
            revealOrders[i] = i;
        }
        Sort.sort(diffs, revealOrders);
        for (uint256 i; i < length; i++) {
            s_packedRevealOrders = s_packedRevealOrders | (revealOrders[i] << (i * 8));
        }
    }

    function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _nextRequestedRound(uint256 word, uint8 bitPos, uint256 round)
        internal
        pure
        returns (uint256 next, bool requested)
    {
        unchecked {
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = word & mask;
            // if there are no requested rounds to the left of the current round, return leftmost in the word
            requested = masked != 0;
            next = requested ? round + Bitmap.leastSignificantBit(masked) - bitPos : round + type(uint8).max - bitPos;
        }
    }

    function consoleDepositsAndSlashRewardAccumulated(
        CommitReveal2 commitReveal2,
        ConsumerExample consumerExample,
        address[] memory operators,
        address leaderNode,
        address extraAddress
    ) internal view {
        uint256 sum;
        // *** Deposit + SlashReward
        for (uint256 i = 0; i < operators.length; i++) {
            sum += commitReveal2.getDepositPlusSlashReward(operators[i]);
        }
        sum += commitReveal2.getDepositPlusSlashReward(leaderNode);
        sum += commitReveal2.getDepositPlusSlashReward(extraAddress);

        // *** accumulated request fees
        uint256 nextRequestedRound = commitReveal2.s_currentRound();
        bool requested;
        uint256 requestCount = commitReveal2.s_requestCount();
        uint256 lastfulfilledRound = consumerExample.lastRequestId();
        for (uint256 i; i < 10; i++) {
            // In the test, there are no more than 10 requests queued
            uint248 wordPos = uint248(nextRequestedRound >> 8);
            uint8 bitPos = uint8(nextRequestedRound & 0xff);
            uint256 word = commitReveal2.s_roundBitmap(wordPos);
            (nextRequestedRound, requested) = _nextRequestedRound(word, bitPos, nextRequestedRound);
            if (requested) {
                if (nextRequestedRound == lastfulfilledRound) {
                    break; // because it is already updated in s_depositAmount
                }
                (,, uint256 cost,) = commitReveal2.s_requestInfo(nextRequestedRound);
                sum += cost;
            }
            if (++nextRequestedRound >= requestCount) {
                break;
            }
        }
        console2.log("--------------------------------");
        console2.log("Calculated Deposit + SlashReward", sum);
        console2.log("Contract Balance", address(commitReveal2).balance);
        console2.log("Difference", _diff(sum, address(commitReveal2).balance));
        console2.log("--------------------");
    }

    function _getTypedDataHashV4(uint256 round, uint256 trialNum, bytes32 cv)
        internal
        view
        returns (bytes32 typedDataHash)
    {
        typedDataHash = keccak256(
            abi.encodePacked(
                hex"1901",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        s_activeNetworkConfig.nameHash,
                        s_activeNetworkConfig.versionHash,
                        block.chainid,
                        address(s_commitReveal2)
                    )
                ),
                keccak256(
                    abi.encode(
                        keccak256("Message(uint256 round,uint256 trialNum,bytes32 cv)"),
                        CommitReveal2Storage.Message({round: round, trialNum: trialNum, cv: cv})
                    )
                )
            )
        );
    }

    function _isSetBit(uint256 word, uint256 bitPos) internal pure returns (bool) {
        return (word & (1 << bitPos)) != 0;
    }

    function _getIndicesOfCvsNotOnChain() internal {
        uint256 zeroBitIfSubmittedCvBitmap = s_commitReveal2.getZeroBitIfSubmittedCvOnChainBitmap();
        uint256 activatedOperatorsLength = s_commitReveal2.getActivatedOperators().length;
        s_tempArray = new uint256[](0); // indices of the operators whose Cvs are not submitted on-chain
        for (uint256 i; i < activatedOperatorsLength; i++) {
            if (_isSetBit(zeroBitIfSubmittedCvBitmap, i)) {
                s_tempArray.push(i);
            }
        }
    }

    function _getIndicesFirstCvNotOnChainRestCvOnChain(uint256[] memory indicesToRequest)
        internal
        returns (uint256 lengthOfIndicesOfCvsNotOnChainAndReqToSubmitCo)
    {
        uint256 zeroBitIfSubmittedCvBitmap = s_commitReveal2.getZeroBitIfSubmittedCvOnChainBitmap();
        s_tempArray = new uint256[](indicesToRequest.length);
        uint256 CvNotOnChainIndex = 0;
        uint256 CvOnChainIndex = indicesToRequest.length - 1;
        for (uint256 i; i < indicesToRequest.length; i++) {
            if (_isSetBit(zeroBitIfSubmittedCvBitmap, indicesToRequest[i])) {
                s_tempArray[CvNotOnChainIndex++] = indicesToRequest[i];
            } else {
                s_tempArray[CvOnChainIndex] = indicesToRequest[i];
                unchecked {
                    CvOnChainIndex--;
                }
            }
        }
        lengthOfIndicesOfCvsNotOnChainAndReqToSubmitCo = CvNotOnChainIndex;
    }

    function _setParametersForGenerateRandomNumberWhenSomeCvsAreOnChain() internal {
        _getIndicesOfCvsNotOnChain();

        s_packedVsForAllCvsNotOnChain = 0;
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (i * 8));
        }
    }

    function _setParametersForRequestToSubmitCo(uint256[] memory indicesToRequest) internal {
        s_indicesLength = indicesToRequest.length;
        uint256 lengthOfIndicesOfCvsNotOnChainAndReqToSubmitCo =
            _getIndicesFirstCvNotOnChainRestCvOnChain(indicesToRequest);
        s_cvRSsForCvsNotOnChainAndReqToSubmitCo =
            new CommitReveal2.CvAndSigRS[](lengthOfIndicesOfCvsNotOnChainAndReqToSubmitCo);
        s_tempVs = new uint256[](lengthOfIndicesOfCvsNotOnChainAndReqToSubmitCo);
        for (uint256 i; i < lengthOfIndicesOfCvsNotOnChainAndReqToSubmitCo; i++) {
            s_cvRSsForCvsNotOnChainAndReqToSubmitCo[i] = CommitReveal2Storage.CvAndSigRS({
                cv: s_cvs[s_tempArray[i]],
                rs: CommitReveal2Storage.SigRS({r: s_rs[s_tempArray[i]], s: s_ss[s_tempArray[i]]})
            });
            s_tempVs[i] = s_vs[s_tempArray[i]];
        }
        s_indicesFirstCvNotOnChainRestCvOnChain = _packArrayIntoUint256(s_tempArray);
        s_packedVsForAllCvsNotOnChain = _packArrayIntoUint256(s_tempVs);
    }

    function _setParametersForRequestToSubmitS(uint256 k, uint256[] memory revealOrders) internal {
        _getIndicesOfCvsNotOnChain();
        s_sigRSsForAllCvsNotOnChain = new CommitReveal2.SigRS[](s_tempArray.length);
        s_packedVsForAllCvsNotOnChain = 0;
        for (uint256 i; i < s_tempArray.length; i++) {
            s_sigRSsForAllCvsNotOnChain[i].r = s_rs[s_tempArray[i]];
            s_sigRSsForAllCvsNotOnChain[i].s = s_ss[s_tempArray[i]];
            uint256 v = s_vs[s_tempArray[i]];
            s_packedVsForAllCvsNotOnChain = s_packedVsForAllCvsNotOnChain | (v << (i * 8));
        }
        s_secretsReceivedOffchainInRevealOrder = new bytes32[](k);
        for (uint256 i; i < s_secretsReceivedOffchainInRevealOrder.length; i++) {
            s_secretsReceivedOffchainInRevealOrder[i] = s_secrets[revealOrders[i]];
        }
    }
}
