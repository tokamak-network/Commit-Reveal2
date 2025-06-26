// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ConsumerBase} from "./ConsumerBase.sol";

contract ConsumerExample is ConsumerBase {
    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    struct RequestInfo {
        uint256 requestBlockNumber;
        address requester;
        uint256 requestFee;
        uint256 fulfillBlockNumber;
    }

    error ETHTransferFailed(); // 0xb12d13eb

    mapping(address requester => uint256[] requestIds) public s_requesterRequestIds;
    mapping(uint256 requestId => RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 requestId => RequestInfo) public s_requestInfos;

    // * for testing
    uint256 public lastRequestId;

    // past requests Id.
    uint32 public constant CALLBACK_GAS_LIMIT = 90000;

    constructor(address coordinator) ConsumerBase(coordinator) {}

    function requestRandomNumber() external payable {
        (uint256 requestId, uint256 requestFee) = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        s_requesterRequestIds[msg.sender].push(requestId);
        s_requestInfos[requestId].requestBlockNumber = block.number;
        s_requestInfos[requestId].requestFee = requestFee;
        s_requestInfos[requestId].requester = msg.sender;
    }

    function refund(uint256 requestId) external {
        _refund(requestId);
    }

    function fulfillRandomRandomNumber(uint256 requestId, uint256 randomNumber) internal override {
        s_requests[requestId] = RequestStatus(true, randomNumber);
        s_requestInfos[requestId].fulfillBlockNumber = block.number;
        lastRequestId = requestId;
    }

    function getCommitReveal2Address() external view returns (address) {
        return address(s_commitreveal2);
    }

    function withdraw() external {
        assembly ("memory-safe") {
            if iszero(call(gas(), caller(), selfbalance(), 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }
}
