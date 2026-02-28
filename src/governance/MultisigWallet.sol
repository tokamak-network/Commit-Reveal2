// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title MultisigWallet
 * @author Commit-Reveal2 Team
 * @notice A multisignature wallet that integrates with OpenZeppelin's TimelockController
 * @dev This contract implements a multi-signature wallet where multiple owners must confirm
 *      transactions before they can be scheduled and executed through a timelock mechanism.
 *      It's designed specifically for governance of the Commit-Reveal2 protocol.
 */
contract MultisigWallet {
    /**
     * @notice Represents a proposed transaction awaiting confirmations
     * @dev Uses a mapping for confirmations to efficiently track which owners have confirmed
     * @param target The contract address to call
     * @param value The amount of ETH to send with the transaction
     * @param data The encoded function call data
     * @param predecessor A bytes32 value that must be satisfied before execution (for timelock)
     * @param salt A unique identifier for the transaction (for timelock)
     * @param delay The minimum delay before the transaction can be executed (in seconds)
     * @param executed Whether the transaction has been executed
     * @param confirmationCount The number of owners who have confirmed this transaction
     * @param isConfirmed Mapping from owner address to their confirmation status
     */
    struct Transaction {
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
        bool executed;
        uint256 confirmationCount;
        mapping(address => bool) isConfirmed;
    }

    /// @notice The OpenZeppelin TimelockController instance used for delayed execution
    /// @dev This contract is the sole proposer and executor for the timelock
    TimelockController public immutable timelock;

    /// @notice Array of all authorized multisig owners
    /// @dev Used for iteration and to get the complete list of owners
    address[] public owners;

    /// @notice Mapping to quickly check if an address is an authorized owner
    /// @dev More gas-efficient than searching through the owners array
    mapping(address => bool) public isOwner;

    /// @notice The minimum number of owner confirmations required to schedule/execute transactions
    /// @dev This value is set during construction and cannot be changed
    uint256 public immutable requiredConfirmations;

    /// @notice Mapping from transaction ID to Transaction struct
    /// @dev Transaction IDs are auto-incrementing starting from 0
    mapping(uint256 => Transaction) public transactions;

    /// @notice The total number of transactions ever created
    /// @dev Also serves as the next transaction ID to be assigned
    uint256 public transactionCount;

    /// @notice Emitted when a new transaction is submitted for confirmation
    /// @param transactionId The unique ID assigned to the transaction
    /// @param submitter The address of the owner who submitted the transaction
    event TransactionSubmitted(uint256 indexed transactionId, address indexed submitter);

    /// @notice Emitted when an owner confirms a transaction
    /// @param transactionId The ID of the transaction being confirmed
    /// @param owner The address of the owner who confirmed the transaction
    event TransactionConfirmed(uint256 indexed transactionId, address indexed owner);

    /// @notice Emitted when an owner revokes their confirmation
    /// @param transactionId The ID of the transaction whose confirmation was revoked
    /// @param owner The address of the owner who revoked their confirmation
    event TransactionRevoked(uint256 indexed transactionId, address indexed owner);

    /// @notice Emitted when a transaction is scheduled in the timelock
    /// @param transactionId The ID of the transaction that was scheduled
    event TransactionScheduled(uint256 indexed transactionId);

    /// @notice Emitted when a transaction is successfully executed
    /// @param transactionId The ID of the transaction that was executed
    event TransactionExecuted(uint256 indexed transactionId);

    /// @notice Thrown when a non-owner attempts to perform an owner-only action
    error NotOwner();

    /// @notice Thrown when referencing a transaction ID that doesn't exist
    error TransactionNotExists();

    /// @notice Thrown when an owner tries to confirm a transaction they've already confirmed
    error TransactionAlreadyConfirmed();

    /// @notice Thrown when an owner tries to revoke a confirmation they haven't made
    error TransactionNotConfirmed();

    /// @notice Thrown when attempting to modify a transaction that has already been executed
    error TransactionAlreadyExecuted();

    /// @notice Thrown when trying to schedule/execute without enough confirmations
    error InsufficientConfirmations();

    /// @notice Thrown when trying to schedule a transaction that's already scheduled
    error TransactionAlreadyScheduled();

    /// @notice Thrown when constructor receives invalid required confirmations parameter
    error InvalidRequiredConfirmations();

    /// @notice Thrown when constructor receives empty owners array
    error NoOwners();

    /// @notice Thrown when constructor receives duplicate owner addresses
    error DuplicateOwner();

    /// @notice Thrown when constructor receives zero address as owner
    error ZeroAddress();

    /// @notice Restricts function access to authorized multisig owners only
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    /// @notice Ensures the referenced transaction ID exists
    /// @param _transactionId The transaction ID to validate
    modifier transactionExists(uint256 _transactionId) {
        if (_transactionId >= transactionCount) revert TransactionNotExists();
        _;
    }

    /// @notice Ensures the transaction hasn't been executed yet
    /// @param _transactionId The transaction ID to check
    modifier notExecuted(uint256 _transactionId) {
        if (transactions[_transactionId].executed) revert TransactionAlreadyExecuted();
        _;
    }

    /**
     * @notice Initializes the multisig wallet with owners, confirmation requirements, and timelock
     * @dev Creates a new TimelockController instance with this contract as the sole proposer/executor
     * @param _owners Array of addresses that will be authorized as multisig owners
     * @param _requiredConfirmations Minimum number of owner confirmations needed for transaction execution
     * @param _minDelay Minimum delay (in seconds) before scheduled transactions can be executed
     *
     * Requirements:
     * - _owners array must not be empty
     * - _requiredConfirmations must be > 0 and <= _owners.length
     * - No duplicate or zero addresses in _owners array
     *
     * Emits: MultisigSetup event (via TimelockController)
     */
    constructor(address[] memory _owners, uint256 _requiredConfirmations, uint256 _minDelay) {
        if (_owners.length == 0) revert NoOwners();
        if (_requiredConfirmations == 0 || _requiredConfirmations > _owners.length) {
            revert InvalidRequiredConfirmations();
        }

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) revert ZeroAddress();
            if (isOwner[owner]) revert DuplicateOwner();

            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredConfirmations = _requiredConfirmations;

        address[] memory proposers = new address[](1);
        proposers[0] = address(this);

        address[] memory executors = new address[](1);
        executors[0] = address(this);

        timelock = new TimelockController(
            _minDelay,
            proposers,
            executors,
            address(0) // no admin
        );
    }

    /**
     * @notice Submits a new transaction proposal for multisig confirmation
     * @dev The submitting owner automatically confirms the transaction upon submission
     * @param _target The contract address to call when the transaction is executed
     * @param _value The amount of ETH (in wei) to send with the transaction
     * @param _data The encoded function call data to execute
     * @param _predecessor A dependency that must be satisfied before execution (timelock feature)
     * @param _salt A unique identifier to prevent transaction hash collisions
     * @param _delay The minimum delay (in seconds) before this transaction can be executed
     * @return transactionId The unique identifier assigned to this transaction
     *
     * Requirements:
     * - Caller must be an authorized owner
     *
     * Emits: TransactionSubmitted and TransactionConfirmed events
     */
    function submitTransaction(
        address _target,
        uint256 _value,
        bytes memory _data,
        bytes32 _predecessor,
        bytes32 _salt,
        uint256 _delay
    ) external onlyOwner returns (uint256 transactionId) {
        transactionId = transactionCount;

        Transaction storage txn = transactions[transactionId];
        txn.target = _target;
        txn.value = _value;
        txn.data = _data;
        txn.predecessor = _predecessor;
        txn.salt = _salt;
        txn.delay = _delay;
        txn.executed = false;
        txn.confirmationCount = 0;

        transactionCount++;

        emit TransactionSubmitted(transactionId, msg.sender);

        // Auto-confirm for submitter
        _confirmTransaction(transactionId);

        return transactionId;
    }

    /**
     * @notice Confirms a pending transaction, adding the caller's signature
     * @dev Each owner can only confirm a transaction once
     * @param _transactionId The ID of the transaction to confirm
     *
     * Requirements:
     * - Caller must be an authorized owner
     * - Transaction must exist and not be executed
     * - Caller must not have already confirmed this transaction
     *
     * Emits: TransactionConfirmed event
     */
    function confirmTransaction(uint256 _transactionId)
        external
        onlyOwner
        transactionExists(_transactionId)
        notExecuted(_transactionId)
    {
        Transaction storage txn = transactions[_transactionId];
        if (txn.isConfirmed[msg.sender]) revert TransactionAlreadyConfirmed();

        _confirmTransaction(_transactionId);
    }

    function _confirmTransaction(uint256 _transactionId) internal {
        Transaction storage txn = transactions[_transactionId];
        txn.isConfirmed[msg.sender] = true;
        txn.confirmationCount++;

        emit TransactionConfirmed(_transactionId, msg.sender);
    }

    /**
     * @notice Revokes a previously given confirmation for a transaction
     * @dev Allows owners to change their mind before a transaction is executed
     * @param _transactionId The ID of the transaction to revoke confirmation for
     *
     * Requirements:
     * - Caller must be an authorized owner
     * - Transaction must exist and not be executed
     * - Caller must have previously confirmed this transaction
     *
     * Emits: TransactionRevoked event
     */
    function revokeConfirmation(uint256 _transactionId)
        external
        onlyOwner
        transactionExists(_transactionId)
        notExecuted(_transactionId)
    {
        Transaction storage txn = transactions[_transactionId];
        if (!txn.isConfirmed[msg.sender]) revert TransactionNotConfirmed();

        txn.isConfirmed[msg.sender] = false;
        txn.confirmationCount--;

        emit TransactionRevoked(_transactionId, msg.sender);
    }

    /**
     * @notice Schedules a transaction for execution in the timelock after sufficient confirmations
     * @dev This function queues the transaction in the TimelockController for delayed execution
     * @param _transactionId The ID of the transaction to schedule
     *
     * Requirements:
     * - Caller must be an authorized owner
     * - Transaction must exist and not be executed
     * - Transaction must have at least `requiredConfirmations` confirmations
     * - Transaction must not already be scheduled in the timelock
     *
     * Emits: TransactionScheduled event
     */
    function scheduleTransaction(uint256 _transactionId)
        external
        onlyOwner
        transactionExists(_transactionId)
        notExecuted(_transactionId)
    {
        Transaction storage txn = transactions[_transactionId];
        if (txn.confirmationCount < requiredConfirmations) {
            revert InsufficientConfirmations();
        }

        bytes32 id = timelock.hashOperation(txn.target, txn.value, txn.data, txn.predecessor, txn.salt);

        if (timelock.isOperationPending(id) || timelock.isOperationDone(id)) {
            revert TransactionAlreadyScheduled();
        }

        timelock.schedule(txn.target, txn.value, txn.data, txn.predecessor, txn.salt, txn.delay);

        emit TransactionScheduled(_transactionId);
    }

    /**
     * @notice Executes a transaction after the timelock delay has passed
     * @dev This function calls the TimelockController to execute the previously scheduled transaction
     * @param _transactionId The ID of the transaction to execute
     *
     * Requirements:
     * - Caller must be an authorized owner
     * - Transaction must exist and not be executed
     * - Transaction must have at least `requiredConfirmations` confirmations
     * - Transaction must be ready for execution (timelock delay passed)
     *
     * Emits: TransactionExecuted event
     */
    function executeTransaction(uint256 _transactionId)
        external
        onlyOwner
        transactionExists(_transactionId)
        notExecuted(_transactionId)
    {
        Transaction storage txn = transactions[_transactionId];
        if (txn.confirmationCount < requiredConfirmations) {
            revert InsufficientConfirmations();
        }

        txn.executed = true;

        emit TransactionExecuted(_transactionId);

        timelock.execute(txn.target, txn.value, txn.data, txn.predecessor, txn.salt);
    }

    /**
     * @notice Returns the complete list of multisig owners
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice Returns the number of confirmations for a specific transaction
     * @param _transactionId The ID of the transaction to query
     * @return The current confirmation count for the transaction
     *
     * Requirements:
     * - Transaction must exist
     */
    function getConfirmationCount(uint256 _transactionId)
        external
        view
        transactionExists(_transactionId)
        returns (uint256)
    {
        return transactions[_transactionId].confirmationCount;
    }

    /**
     * @notice Checks if a specific owner has confirmed a transaction
     * @param _transactionId The ID of the transaction to query
     * @param _owner The address of the owner to check
     * @return True if the owner has confirmed the transaction, false otherwise
     *
     * Requirements:
     * - Transaction must exist
     */
    function isConfirmed(uint256 _transactionId, address _owner)
        external
        view
        transactionExists(_transactionId)
        returns (bool)
    {
        return transactions[_transactionId].isConfirmed[_owner];
    }

    /**
     * @notice Returns complete transaction information
     * @param _transactionId The ID of the transaction to query
     * @return target The target contract address
     * @return value The ETH value to send
     * @return data The encoded function call data
     * @return predecessor The timelock predecessor requirement
     * @return salt The unique transaction salt
     * @return delay The minimum execution delay
     * @return executed Whether the transaction has been executed
     * @return confirmationCount The current number of confirmations
     *
     * Requirements:
     * - Transaction must exist
     */
    function getTransaction(uint256 _transactionId)
        external
        view
        transactionExists(_transactionId)
        returns (
            address target,
            uint256 value,
            bytes memory data,
            bytes32 predecessor,
            bytes32 salt,
            uint256 delay,
            bool executed,
            uint256 confirmationCount
        )
    {
        Transaction storage txn = transactions[_transactionId];
        return
            (txn.target, txn.value, txn.data, txn.predecessor, txn.salt, txn.delay, txn.executed, txn.confirmationCount);
    }
}
