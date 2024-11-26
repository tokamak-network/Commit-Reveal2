// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {DRBConsumerBase} from "./DRBConsumerBase.sol";

contract ConsumerExample is DRBConsumerBase {
    struct RequestStatus {
        bool requested; // whether the request has been made
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    uint32 public constant CALLBACK_GAS_LIMIT = 83011;

    constructor(address coordinator) DRBConsumerBase(coordinator) {}

    function requestRandomNumber() external payable {
        uint256 requestId = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        s_requests[requestId].requested = true;
        requestIds.push(requestId);
    }

    function fulfillRandomRandomNumber(
        uint256 requestId,
        uint256 hashedOmegaVal
    ) internal override {
        if (!s_requests[requestId].requested) {
            revert InvalidRequest(requestId);
        }
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomNumber = hashedOmegaVal;
    }

    function getRNGCoordinator() external view returns (address) {
        return address(i_commitreveal2);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool, bool, uint256) {
        RequestStatus memory request = s_requests[_requestId];
        return (request.requested, request.fulfilled, request.randomNumber);
    }

    function totalRequests() external view returns (uint256 requestCount) {
        requestCount = requestIds.length;
    }

    function lastRequestId() external view returns (uint256 requestId) {
        requestId = requestIds.length == 0
            ? 0
            : requestIds[requestIds.length - 1];
    }
}
