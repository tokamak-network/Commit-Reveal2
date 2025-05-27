// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ConsumerBase} from "./ConsumerBase.sol";

contract ConsumerExampleV2 is ConsumerBase {
    struct MainInfo {
        uint256 requestId;
        address requester;
        uint256 fulfillBlockNumber;
        uint256 randomNumber;
        bool isRefunded;
    }

    struct DetailInfo {
        uint256 requestBlockNumber;
        uint256 requestFee;
    }

    uint32 public constant CALLBACK_GAS_LIMIT = 85000;
    MainInfo[100] public s_mainInfos;
    DetailInfo[100] public s_detailInfos;
    mapping(uint256 requestId => uint256 index) public s_requestIdToIndexPlusOne;
    uint256 public s_requestCount;

    constructor(address coordinator) ConsumerBase(coordinator) {}

    function requestRandomNumber() external payable {
        (uint256 requestId, uint256 requestFee) = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        uint256 index = s_requestCount++ % 100;
        s_requestIdToIndexPlusOne[requestId] = index + 1;
        MainInfo storage mainInfo = s_mainInfos[index];
        mainInfo.requestId = requestId;
        mainInfo.requester = msg.sender;
        DetailInfo storage detailInfo = s_detailInfos[index];
        detailInfo.requestBlockNumber = block.number;
        detailInfo.requestFee = requestFee;
    }

    function fulfillRandomRandomNumber(uint256 requestId, uint256 randomNumber) internal override {
        uint256 index = s_requestIdToIndexPlusOne[requestId] - 1;
        MainInfo storage mainInfo = s_mainInfos[index];
        mainInfo.fulfillBlockNumber = block.number;
        mainInfo.randomNumber = randomNumber;
    }

    function refund(uint256 requestId) external {
        _refund(requestId);
        uint256 index = s_requestIdToIndexPlusOne[requestId] - 1;
        s_mainInfos[index].isRefunded = true;
    }

    function withdraw() external {
        assembly ("memory-safe") {
            if iszero(call(gas(), caller(), selfbalance(), 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    // ** getters

    function getCommitReveal2Address() external view returns (address) {
        return address(s_commitreveal2);
    }

    function getMainInfos() external view returns (uint256 requestCount, MainInfo[100] memory) {
        return (s_requestCount, s_mainInfos);
    }

    function getDetailInfo(uint256 requestId)
        external
        view
        returns (
            address requester,
            uint256 requestFee,
            uint256 requestBlockNumber,
            uint256 fulfillBlockNumber,
            uint256 randomNumber
        )
    {
        uint256 index = s_requestIdToIndexPlusOne[requestId] - 1;
        MainInfo storage mainInfo = s_mainInfos[index];
        DetailInfo storage detailInfo = s_detailInfos[index];
        return (
            mainInfo.requester,
            detailInfo.requestFee,
            detailInfo.requestBlockNumber,
            mainInfo.fulfillBlockNumber,
            mainInfo.randomNumber
        );
    }
}
