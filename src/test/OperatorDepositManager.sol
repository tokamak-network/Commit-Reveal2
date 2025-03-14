// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract OperatorDepositManager is Ownable2Step {
    uint256 public s_activationThreshold;
    uint256 public s_maxActivatedOperators;
    mapping(address => uint256) public s_depositAmount;
    mapping(address operator => uint256) public s_activatedOperatorIndex1Based;

    uint256 public s_slashRewardPerOperator;
    mapping(address => uint256) public s_slashRewardPerOperatorPaid;

    uint256 internal constant NOT_IN_PROGRESS = 1;
    uint256 internal constant IN_PROGRESS = 2;
    uint256 public s_isInProcess = NOT_IN_PROGRESS;

    address[] internal s_activatedOperators;

    event Activated(address operator);
    event DeActivated(address operator);

    error InProcess();
    error LessThanActivationThreshold();
    error AlreadyActivated();
    error ActivatedOperatorsLimitReached();
    error TransferFailed();

    constructor(
        uint256 activationThreshold,
        uint256 maxActivatedOperators
    ) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_maxActivatedOperators = maxActivatedOperators;
    }

    function setActivationThreshold(uint256 newAmount) external {
        s_activationThreshold = newAmount;
    }

    function depositAndActivate() external payable {
        deposit();
        activate();
    }

    function slash(address[] calldata slashedList) external {
        uint256 slashedListLength = slashedList.length;
        uint256 activationThreshold = s_activationThreshold;

        uint256 slashRewardPerOperator = s_slashRewardPerOperator;
        uint256 updatedSlashRewardPerOperator = slashRewardPerOperator +
            (activationThreshold * slashedListLength) /
            (s_activatedOperators.length - slashedListLength);
        s_slashRewardPerOperator = updatedSlashRewardPerOperator;

        // *** update slash reward
        for (uint256 i; i < slashedListLength; ++i) {
            // *** update slash reward
            uint256 accumulatedReward = slashRewardPerOperator -
                s_slashRewardPerOperatorPaid[slashedList[i]];

            s_slashRewardPerOperatorPaid[
                slashedList[i]
            ] = updatedSlashRewardPerOperator;

            // *** update deposit amount
            uint256 updatedDepositAmount = s_depositAmount[slashedList[i]] -
                activationThreshold +
                accumulatedReward;
            s_depositAmount[slashedList[i]] = updatedDepositAmount;

            // ** Deactivate
            uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
                    slashedList[i]
                ];
            if (activatedOperatorIndex1Based > 0)
                _deactivate(activatedOperatorIndex1Based - 1, slashedList[i]);
        }
    }

    function claimSlashReward() external returns (uint256 amount) {
        uint256 currentSlashRewardPerOperator = s_slashRewardPerOperator;
        amount =
            currentSlashRewardPerOperator -
            s_slashRewardPerOperatorPaid[msg.sender];
        s_slashRewardPerOperatorPaid[
            msg.sender
        ] = currentSlashRewardPerOperator;
        bool success;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), caller(), amount, 0, 0, 0, 0)
        }
        require(success, TransferFailed());
    }

    function deposit() public payable {
        s_depositAmount[msg.sender] += msg.value;
    }

    function withdraw() external returns (uint256 amount) {
        // *** Deactivate
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        if (activatedOperatorIndex1Based > 0)
            _deactivate(activatedOperatorIndex1Based - 1, msg.sender);

        // *** update slash reward
        uint256 currentSlashRewardPerOperator = s_slashRewardPerOperator;
        amount =
            s_depositAmount[msg.sender] +
            currentSlashRewardPerOperator -
            s_slashRewardPerOperatorPaid[msg.sender];
        s_slashRewardPerOperatorPaid[
            msg.sender
        ] = currentSlashRewardPerOperator;

        // *** Transfer
        s_depositAmount[msg.sender] = 0;
        bool success;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), caller(), amount, 0, 0, 0, 0)
        }
        require(success, TransferFailed());
    }

    function activate() public {
        require(s_isInProcess == NOT_IN_PROGRESS, InProcess());
        require(
            s_depositAmount[msg.sender] >= s_activationThreshold,
            LessThanActivationThreshold()
        );
        require(
            s_activatedOperatorIndex1Based[msg.sender] == 0,
            AlreadyActivated()
        );
        s_activatedOperators.push(msg.sender);
        uint256 activatedOperatorLength = s_activatedOperators.length;
        require(
            activatedOperatorLength <= s_maxActivatedOperators,
            ActivatedOperatorsLimitReached()
        );
        s_activatedOperatorIndex1Based[msg.sender] = activatedOperatorLength;
        s_slashRewardPerOperatorPaid[msg.sender] = s_slashRewardPerOperator;
        emit Activated(msg.sender);
    }

    function deactivate() external {
        require(s_isInProcess == NOT_IN_PROGRESS, InProcess());
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
    }

    function _deactivate(
        uint256 activatedOperatorIndex,
        address operator
    ) private {
        address lastOperator = s_activatedOperators[
            s_activatedOperators.length - 1
        ];
        s_activatedOperators[activatedOperatorIndex] = lastOperator;
        s_activatedOperators.pop();
        s_activatedOperatorIndex1Based[lastOperator] =
            activatedOperatorIndex +
            1;
        delete s_activatedOperatorIndex1Based[operator];
        emit DeActivated(operator);
    }
}
