// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ConsumerBase} from "./ConsumerBase.sol";

contract ConsumerExample is ConsumerBase {
    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    mapping(address requester => uint256[] requestIds) public s_requesterRequestIds;
    mapping(uint256 requestId => RequestStatus) public s_requests; /* requestId --> requestStatus */

    // * for testing
    uint256 public lastRequestId;

    // past requests Id.
    uint32 public constant CALLBACK_GAS_LIMIT = 80000;

    constructor(address coordinator) ConsumerBase(coordinator) {}

    function requestRandomNumber() external payable {
        uint256 requestId = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        s_requesterRequestIds[msg.sender].push(requestId);
    }

    function fulfillRandomRandomNumber(uint256 requestId, uint256 randomNumber) internal override {
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomNumber = randomNumber;
        lastRequestId = requestId;
    }

    function getCommitReveal2Address() external view returns (address) {
        return address(i_commitreveal2);
    }

    function getYourRequests()
        external
        view
        returns (uint256[] memory requestIds, bool[] memory isFulFilled, uint256[] memory randomNumbers)
    {
        requestIds = s_requesterRequestIds[msg.sender];
        isFulFilled = new bool[](requestIds.length);
        randomNumbers = new uint256[](requestIds.length);
        for (uint256 i = 0; i < requestIds.length; i++) {
            RequestStatus memory request = s_requests[requestIds[i]];
            isFulFilled[i] = request.fulfilled;
            randomNumbers[i] = request.randomNumber;
        }
    }
}
