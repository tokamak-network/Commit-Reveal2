// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {Owned} from "@solmate/src/auth/Owned.sol";
import {Ownable} from "@solady/src/auth/Ownable.sol";

contract OperatorManager is Ownable {
    // * State Variables
    /**
     * @notice Tracks each operator’s current deposit balance, including any ETH they have deposited or earned.
     *         The deposit can be used to meet `s_activationThreshold` or to pay slashing penalties.
     * @dev Keys are operator addresses, values are deposit amounts in wei.
     */
    mapping(address operator => uint256) public s_depositAmount;

    /**
     * @notice Maps each operator to an index (1-based) in the `s_activatedOperators` array.
     * @dev
     *   - `0` means the operator is not active.
     *   - A non-zero value indicates the position of the operator in `s_activatedOperators`.
     *   - This index is 1-based, so subtract 1 when accessing the array.
     */
    mapping(address operator => uint256) public s_activatedOperatorIndex1Based;

    /**
     * @notice Records how much slash reward is allocated per operator at the global level.
     * @dev
     *   - Each time an operator is slashed, a portion of its deposit is distributed to
     *     other operators (and the leader node if included).
     *   - `s_slashRewardPerOperatorPaid[operator]` tracks how much of this total an operator has already claimed.
     */
    uint256 public s_slashRewardPerOperator;

    /**
     * @notice Maps an operator to the amount of global slash reward they have already received.
     * @dev
     *   - This prevents double-counting of slash rewards when an operator withdraws or claims.
     *   - If `s_slashRewardPerOperator` is increased, each operator can claim the difference
     *     between the new global reward and what they have already been paid.
     */
    mapping(address => uint256) public s_slashRewardPerOperatorPaid;

    /**
     * @notice Indicates the current operational status:
     *   - `IN_PROGRESS = 1`
     *   - `COMPLETED = 2`
     *   - `HALTED = 3`
     * @dev Defaults to `COMPLETED` on contract creation, meaning there is no active round in process.
     */
    uint256 public s_isInProcess = COMPLETED;

    /**
     * @notice The minimum amount of ETH an operator (other than the leader) must deposit to become active.
     * @dev Operators must have `>= s_activationThreshold` in `s_depositAmount[operator]` to call `activate()`.
     */
    uint256 public s_activationThreshold;

    /**
     * @notice The maximum number of operators that can be simultaneously active.
     * @dev Enforced when an operator calls `activate()`, ensuring `s_activatedOperators.length <= s_maxActivatedOperators`.
     */
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

    /**
     * @notice Allows any address (owner or operator) to deposit ETH into their own account balance.
     * @dev
     *   - Increments `s_depositAmount[msg.sender]` by `msg.value`.
     *   - For operators to reach `s_activationThreshold`.
     *   - The deposited amount may later be withdrawn if the operator deactivates or if the owner so chooses.
     */
    function deposit() public payable {
        s_depositAmount[msg.sender] += msg.value;
    }

    /**
     * @notice Activates an operator, allowing them to participate in the protocol (e.g., commit/reveal^2 phases).
     * @dev
     *   - Must not be called while `s_isInProcess == IN_PROGRESS` (protected by {notInProcess}).
     *   - The owner (leader node) cannot activate as an operator (reverts with {OwnerCannotActivate}).
     *   - Requires the caller to have a deposit (`s_depositAmount[msg.sender]`) >= `s_activationThreshold`.
     *   - Ensures the operator is not already active (`s_activatedOperatorIndex1Based[msg.sender] == 0`).
     *   - Adds the operator’s address to `s_activatedOperators` and sets their 1-based index.
     *   - Enforces `s_activatedOperators.length <= s_maxActivatedOperators`.
     *   - Initializes the operator’s slash reward offset with `s_slashRewardPerOperatorPaid[msg.sender] = s_slashRewardPerOperator`.
     *   - Emits {Activated} upon success.
     */
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

    /**
     * @notice A convenience function to both deposit ETH and immediately activate as an operator in one call.
     * @dev
     *   - Simply calls {deposit()} to increase the caller’s `s_depositAmount[msg.sender]`,
     *     then calls {activate()} to attempt activation.
     *   - If the deposit plus any existing balance is >= `s_activationThreshold`,
     *     and there is still room under `s_maxActivatedOperators`, the caller becomes an active operator.
     */
    function depositAndActivate() external payable {
        deposit();
        activate();
    }

    /**
     * @notice Allows an operator or the owner to withdraw their total deposit (and slash rewards)
     *         when not currently in process.
     * @dev
     *   - Protected by {notInProcess}, so no active round can be ongoing.
     *   - If the caller is an activated operator:
     *       1) The caller is first deactivated by calling {_deactivate(...)}.
     *       2) Their withdrawable amount includes their `s_depositAmount[msg.sender]` plus any unclaimed
     *          slash rewards (`s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender]`).
     *   - If the caller is the owner (leader node), not an operator, they can still withdraw
     *     their deposit plus any accrued slash reward.
     *   - Otherwise, if the caller is neither the owner nor an active operator, they just withdraw
     *     their deposit without any slash reward.
     *   - Resets the caller’s deposit to `0` and transfers the calculated `amount` via low-level `call()`.
     *     If the call fails, reverts with `ETHTransferFailed()`.
     *   - Updates `s_slashRewardPerOperatorPaid[msg.sender]` to the current global slash reward
     *     to prevent re-claiming the same reward.
     */
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

    /**
     * @notice Allows an operator to voluntarily deactivate (leave) the system, provided it is not in process.
     * @dev
     *   - Protected by {notInProcess}, ensuring no active round is in progress.
     *   - Looks up the caller's 1-based index in `s_activatedOperators`, then calls {_deactivate(...)}.
     *   - Once deactivated, the operator can choose to withdraw their deposit (and slash rewards) by calling {withdraw()}.
     */
    function deactivate() external notInProcess {
        uint256 activatedOperatorIndex1Based = s_activatedOperatorIndex1Based[msg.sender];
        _deactivate(activatedOperatorIndex1Based - 1, msg.sender);
    }

    /**
     * @notice Allows an already-activated operator to claim any slash reward accrued so far.
     * @dev
     *   - Requires the caller to be an active operator (reverts with {OnlyActivatedOperatorCanClaim} if not).
     *   - Calculates the operator’s unclaimed slash reward by taking the difference
     *     `s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[msg.sender]`.
     *   - Resets `s_slashRewardPerOperatorPaid[msg.sender]` to the current global slash reward level
     *     so the operator cannot claim the same reward again.
     *   - Transfers the computed amount of ETH to the caller via a low-level `call`.
     *     If the transfer fails, reverts with {TransferFailed}.
     */
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
    /**
     * @notice Returns the array of currently activated operators.
     * @return An array of operator addresses, each of whom has called `activate()` and not yet been deactivated.
     */
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    /**
     * @notice Returns the current length of the `s_activatedOperators` array.
     * @dev Equivalent to `s_activatedOperators.length`.
     * @return The number of currently activated operators.
     */
    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length;
    }

    // ** For Testing
    /**
     * @notice Computes the total balance of `operator`, including any unclaimed slash rewards, if they are active or the owner.
     * @dev
     *   - If `operator` is not the owner and not currently active, returns only `s_depositAmount[operator]`.
     *   - Otherwise, returns the sum of `s_depositAmount[operator]` plus
     *     `(s_slashRewardPerOperator - s_slashRewardPerOperatorPaid[operator])`.
     *   - Useful for testing the operator’s effective total.
     * @param operator The address to query.
     * @return The deposit plus unclaimed slash rewards of the `operator`.
     */
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
