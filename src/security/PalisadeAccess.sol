// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract PalisadeAccess {
    error ZeroAddress();
    error UnauthorizedGovernor(address caller);
    error UnauthorizedGuardian(address caller);
    error UnauthorizedKeeper(address caller);
    error UnauthorizedGovernorOrGuardian(address caller);
    error UnauthorizedGovernorOrKeeper(address caller);
    error NotPendingGovernor(address caller, address expected);
    error AlreadyGovernor(address account);
    error ArrayLengthMismatch();

    event GovernorTransferStarted(address indexed governor, address indexed pendingGovernor);
    event GovernorTransferCancelled(address indexed governor, address indexed candidate);
    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event KeeperUpdated(address indexed keeper, bool authorized);

    address public governor;
    address public pendingGovernor;
    address public guardian;

    mapping(address keeper => bool authorized) public isKeeper;

    constructor(address initialGovernor, address initialGuardian) {
        if (initialGovernor == address(0)) revert ZeroAddress();
        governor = initialGovernor;
        guardian = initialGuardian;

        emit GovernorTransferred(address(0), initialGovernor);
        emit GuardianUpdated(address(0), initialGuardian);
    }

    modifier onlyGovernor() {
        _checkGovernor();
        _;
    }

    modifier onlyGuardian() {
        _checkGuardian();
        _;
    }

    modifier onlyKeeper() {
        _checkKeeper();
        _;
    }

    modifier onlyGovernorOrGuardian() {
        _checkGovernorOrGuardian();
        _;
    }

    modifier onlyGovernorOrKeeper() {
        _checkGovernorOrKeeper();
        _;
    }

    function proposeGovernor(address newGovernor) external onlyGovernor {
        if (newGovernor == address(0)) revert ZeroAddress();
        if (newGovernor == governor) revert AlreadyGovernor(newGovernor);
        pendingGovernor = newGovernor;
        emit GovernorTransferStarted(governor, newGovernor);
    }

    function cancelGovernorTransfer() external onlyGovernor {
        address candidate = pendingGovernor;
        pendingGovernor = address(0);
        emit GovernorTransferCancelled(governor, candidate);
    }

    function acceptGovernor() external {
        address candidate = pendingGovernor;
        if (candidate == address(0) || msg.sender != candidate) {
            revert NotPendingGovernor(msg.sender, candidate);
        }
        address previous = governor;
        governor = candidate;
        pendingGovernor = address(0);
        emit GovernorTransferred(previous, candidate);
    }

    function setGuardian(address newGuardian) external onlyGovernor {
        address previous = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(previous, newGuardian);
    }

    function setKeeper(address keeper, bool authorized) external onlyGovernor {
        if (keeper == address(0)) revert ZeroAddress();
        isKeeper[keeper] = authorized;
        emit KeeperUpdated(keeper, authorized);
    }

    function setKeepers(address[] calldata keepers, bool[] calldata authorizations)
        external
        onlyGovernor
    {
        if (keepers.length != authorizations.length) revert ArrayLengthMismatch();
        for (uint256 i; i < keepers.length; ++i) {
            address keeper = keepers[i];
            if (keeper == address(0)) revert ZeroAddress();
            isKeeper[keeper] = authorizations[i];
            emit KeeperUpdated(keeper, authorizations[i]);
        }
    }

    function _checkGovernor() internal view {
        if (msg.sender != governor) revert UnauthorizedGovernor(msg.sender);
    }

    function _checkGuardian() internal view {
        if (msg.sender != guardian) revert UnauthorizedGuardian(msg.sender);
    }

    function _checkKeeper() internal view {
        if (!isKeeper[msg.sender]) revert UnauthorizedKeeper(msg.sender);
    }

    function _checkGovernorOrGuardian() internal view {
        if (msg.sender != governor && msg.sender != guardian) {
            revert UnauthorizedGovernorOrGuardian(msg.sender);
        }
    }

    function _checkGovernorOrKeeper() internal view {
        if (msg.sender != governor && !isKeeper[msg.sender]) {
            revert UnauthorizedGovernorOrKeeper(msg.sender);
        }
    }
}
