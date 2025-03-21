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
    /**
     * @notice Holds the list of currently active operator addresses.
     * @dev
     *   - Operators appear in this array once they call `activate()` successfully.
     *   - The 1-based index for each operator is stored in `s_activatedOperatorIndex1Based`.
     *   - When an operator is deactivated, it is removed from this array (replacing
     *     its slot with the last operator in the array).
     */
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

    /**
     * @notice Ensures that no actions can be taken while the contract is in an ongoing process.
     * @dev
     *   - Reverts with {InProcess} if `s_isInProcess == IN_PROGRESS`.
     *   - Commonly used to protect functions that should not execute while the system is ongoing
     *     with a round of operations or an uncompleted flow.
     */
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
        require(s_depositAmount[msg.sender] >= s_activationThreshold, LessThanActivationThreshold());
        require(s_activatedOperatorIndex1Based[msg.sender] == 0, AlreadyActivated());
        s_activatedOperators.push(msg.sender);
        uint256 activatedOperatorLength = s_activatedOperators.length;
        require(activatedOperatorLength <= s_maxActivatedOperators, ActivatedOperatorsLimitReached());
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
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[msg.sender];

        uint256 amount;
        uint256 currentSlashRewardPerOperator = s_slashRewardPerOperator;

        // If the caller is an active operator, deactivate them first and compute total owed.
        if (activatedOperatorIndex1Based > 0) {
            _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
            amount =
                s_depositAmount[msg.sender] + currentSlashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender];
        } else if (msg.sender == owner()) {
            // If the caller is the owner (leader node) but not an operator,
            // they can still withdraw deposit plus slash reward.
            amount =
                s_depositAmount[msg.sender] + currentSlashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender];
        } else {
            // Otherwise, withdraw only the caller’s deposit (no slash reward).
            // If they were an operator, the slash reward was already updated to s_depositAmount.
            amount = s_depositAmount[msg.sender];
        }

        // ** Mark the caller as having received all global slash rewards up to this point
        s_slashRewardPerOperatorPaid[msg.sender] = currentSlashRewardPerOperator;

        // Reset deposit to zero and attempt transfer
        s_depositAmount[msg.sender] = 0;
        assembly ("memory-safe") {
            // Transfer the ETH and check if it succeeded or not.
            if iszero(call(gas(), caller(), amount, 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    function deactivate() external notInProcess {
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[msg.sender];
        _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
    }

    function claimSlashReward() external {
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[msg.sender];
        require(activatedOperatorIndex1Based > 0, OnlyActivatedOperatorCanClaim());
        uint256 currentSlashRewardPerOperator = s_slashRewardPerOperator;
        uint256 amount = currentSlashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender];
        s_slashRewardPerOperatorPaid[msg.sender] = currentSlashRewardPerOperator;
        bool success;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), caller(), amount, 0, 0, 0, 0)
        }
        require(success, TransferFailed());
    }

    // ** getter
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length;
    }

    // ** For Testing

    function getDepositPlusSlashReward(address operator) external view returns (uint256) {
        if (owner() != operator && s_activatedOperatorIndex1Based[operator] == 0) {
            return s_depositAmount[operator];
        }
        return s_depositAmount[operator] + s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator];
    }

    /**
     * @notice Removes an operator from the `s_activatedOperators` array and resets their mapping indices.
     * @dev
     *   - Internal function used by either `deactivate()` or `withdraw()`.
     *   - Swaps the operator to remove with the last operator in the array, preserving continuous storage,
     *     then `pop()`s the array end.
     *   - Clears `s_activatedOperatorIndex1Based[operator]` to indicate the operator is no longer active.
     *   - Emits {DeActivated} with the removed operator’s address.
     * @param activatedOperatorIndex The zero-based index of the operator in `s_activatedOperators`.
     * @param operator The address of the operator to remove.
     */
    function _deactivate(uint256 activatedOperatorIndex, address operator) internal {
        address lastOperator = s_activatedOperators[s_activatedOperators.length - 1];
        if (lastOperator != operator) {
            s_activatedOperators[activatedOperatorIndex] = lastOperator;
            s_activatedOperatorIndex1Based[lastOperator] = activatedOperatorIndex + 1;
        }
        s_activatedOperators.pop();
        delete s_activatedOperatorIndex1Based[operator];
        emit DeActivated(operator);
    }
}
