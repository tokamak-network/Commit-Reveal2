// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {Owned} from "@solmate/src/auth/Owned.sol";
import {Ownable} from "@solady/src/auth/Ownable.sol";

contract OperatorManager is Ownable {
    // * State Variables
    mapping(address operator => uint256) public s_depositAmount;
    mapping(address operator => uint256) public s_activatedOperatorIndex1Based;
    uint256 public s_slashRewardPerOperator;
    mapping(address => uint256) public s_slashRewardPerOperatorPaid;
    uint256 public s_isInProcess = COMPLETED;
    uint256 public s_activationThreshold;
    uint256 public s_maxActivatedOperators;

    // ** internal variables
    address[] internal s_activatedOperators;

    // ** constants
    uint256 internal constant IN_PROGRESS = 1;
    uint256 internal constant COMPLETED = 2;
    uint256 internal constant HALTED = 3;

    // ** Events
    event Activated(address operator);
    event DeActivated(address operator);

    // * Errors
    error TransferFailed();
    error InProcess();
    error OnlyActivatedOperatorCanClaim();
    error OwnerCannotActivate();
    error LessThanActivationThreshold();
    error AlreadyActivated();
    error ActivatedOperatorsLimitReached();

    constructor() {
        _initializeOwner(msg.sender);
    }

    modifier notInProcess() {
        require(s_isInProcess != IN_PROGRESS, InProcess());
        _;
    }

    function deposit() public payable {
        s_depositAmount[msg.sender] += msg.value;
    }

    function activate() public notInProcess {
        // *** leaderNode doesn't activate
        require(msg.sender != owner(), OwnerCannotActivate());
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

        // ** initialize slashRewardPerOperatorPaid
        s_slashRewardPerOperatorPaid[msg.sender] = s_slashRewardPerOperator;
        emit Activated(msg.sender);
    }

    function depositAndActivate() external payable {
        deposit();
        activate();
    }

    function withdraw() external notInProcess {
        // *** Deactivate
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        if (activatedOperatorIndex1Based > 0)
            _deactivate(activatedOperatorIndex1Based - 1, msg.sender);

        // *** update slash reward
        uint256 currentSlashRewardPerOperator = s_slashRewardPerOperator;
        uint256 amount = s_depositAmount[msg.sender] +
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

    function deactivate() external notInProcess {
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
    }

    function claimSlashReward() external {
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[
            msg.sender
        ];
        require(
            activatedOperatorIndex1Based > 0,
            OnlyActivatedOperatorCanClaim()
        );
        uint256 currentSlashRewardPerOperator = s_slashRewardPerOperator;
        uint256 amount = currentSlashRewardPerOperator -
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

    // ** getter
    // s_activatedOperators
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length;
    }

    function _deactivate(
        uint256 activatedOperatorIndex,
        address operator
    ) internal {
        address lastOperator = s_activatedOperators[
            s_activatedOperators.length - 1
        ];
        if (lastOperator != operator) {
            s_activatedOperators[activatedOperatorIndex] = lastOperator;
            s_activatedOperatorIndex1Based[lastOperator] =
                activatedOperatorIndex +
                1;
        }
        s_activatedOperators.pop();
        delete s_activatedOperatorIndex1Based[operator];
        emit DeActivated(operator);
    }
}
