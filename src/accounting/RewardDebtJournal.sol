// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PalisadeAccess } from "../security/PalisadeAccess.sol";

/// @title RewardDebtJournal
/// @notice Append-only journal that indexers can use to mirror lease reward debt transitions.
contract RewardDebtJournal is PalisadeAccess {
    struct Entry {
        uint256 leaseId;
        uint256 positionId;
        address actor;
        uint256 previousDebt;
        uint256 newDebt;
        uint256 rewardIndex;
        uint40 timestamp;
        bytes32 reason;
    }

    error CallerNotMarket(address caller);
    error InvalidMarket();
    error InvalidEntry();

    event MarketUpdated(address indexed previousMarket, address indexed newMarket);
    event EntryRecorded(
        uint256 indexed entryId,
        uint256 indexed leaseId,
        uint256 indexed positionId,
        address actor,
        uint256 previousDebt,
        uint256 newDebt,
        uint256 rewardIndex,
        bytes32 reason
    );

    address public market;
    Entry[] private _entries;
    mapping(uint256 leaseId => uint256[] entryIds) private _entriesByLease;
    mapping(uint256 positionId => uint256[] entryIds) private _entriesByPosition;

    constructor(address initialGovernor, address initialGuardian)
        PalisadeAccess(initialGovernor, initialGuardian)
    { }

    modifier onlyMarket() {
        if (msg.sender != market) revert CallerNotMarket(msg.sender);
        _;
    }

    function setMarket(address newMarket) external onlyGovernor {
        if (newMarket == address(0)) revert InvalidMarket();
        address previous = market;
        market = newMarket;
        emit MarketUpdated(previous, newMarket);
    }

    function record(
        uint256 leaseId,
        uint256 positionId,
        address actor,
        uint256 previousDebt,
        uint256 newDebt,
        uint256 rewardIndex,
        bytes32 reason
    ) external onlyMarket returns (uint256 entryId) {
        if (leaseId == 0 || positionId == 0 || actor == address(0)) {
            revert InvalidEntry();
        }
        entryId = _entries.length;
        _entries.push(
            Entry({
                leaseId: leaseId,
                positionId: positionId,
                actor: actor,
                previousDebt: previousDebt,
                newDebt: newDebt,
                rewardIndex: rewardIndex,
                timestamp: uint40(block.timestamp),
                reason: reason
            })
        );
        _entriesByLease[leaseId].push(entryId);
        _entriesByPosition[positionId].push(entryId);

        emit EntryRecorded(
            entryId, leaseId, positionId, actor, previousDebt, newDebt, rewardIndex, reason
        );
    }

    function entryCount() external view returns (uint256) {
        return _entries.length;
    }

    function entry(uint256 entryId) external view returns (Entry memory) {
        return _entries[entryId];
    }

    function entriesByLease(uint256 leaseId) external view returns (uint256[] memory) {
        return _entriesByLease[leaseId];
    }

    function entriesByPosition(uint256 positionId) external view returns (uint256[] memory) {
        return _entriesByPosition[positionId];
    }
}
