// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VRFV2PlusWrapperConsumerBase} from "./VRFV2PlusWrapperConsumerBase.sol";
import {VRFV2PlusClient} from "./libraries/VRFV2PlusClient.sol";

contract ConsumerExampleChainlink is VRFV2PlusWrapperConsumerBase {
    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    mapping(address requester => uint256[] requestIds) public s_requesterRequestIds;
    mapping(uint256 requestId => RequestStatus) public s_requests; /* requestId --> requestStatus */

    // * for testing
    uint256 public lastRequestId;

    // past requests Id.
    uint32 public constant CALLBACK_GAS_LIMIT = 90000;

    constructor(address wrapper) VRFV2PlusWrapperConsumerBase(wrapper) {}

    function requestRandomNumber() external payable {
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));
        (uint256 requestId,) = requestRandomnessPayInNative(CALLBACK_GAS_LIMIT, 3, 1, extraArgs);
        s_requesterRequestIds[msg.sender].push(requestId);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        s_requests[_requestId] = RequestStatus(true, _randomWords[0]);
        lastRequestId = _requestId;
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
