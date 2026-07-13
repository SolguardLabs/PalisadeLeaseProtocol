// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    LeaseQuote,
    LeaseRecord,
    LeaseStatus,
    LeaseTerms,
    ListingRecord,
    MarketConfig
} from "../types/PalisadeTypes.sol";

interface IPalisadeLeaseMarket {
    event Listed(
        uint256 indexed positionId,
        address indexed owner,
        address indexed paymentToken,
        uint256 basePricePerDay,
        uint40 expiresAt
    );
    event ListingCancelled(uint256 indexed positionId, address indexed owner);
    event LeaseOpened(
        uint256 indexed leaseId,
        uint256 indexed positionId,
        address indexed owner,
        address lessee,
        uint40 start,
        uint40 end,
        uint256 price
    );
    event LeaseRenewed(
        uint256 indexed previousLeaseId,
        uint256 indexed newLeaseId,
        uint256 indexed positionId,
        address lessee,
        uint40 start,
        uint40 end,
        uint256 inheritedRewardDebt
    );
    event LeaseCheckpointed(
        uint256 indexed leaseId,
        uint256 indexed positionId,
        uint256 rewardDelta,
        uint256 rewardDebt,
        uint256 rewardIndex
    );
    event LeaseRewardsClaimed(
        uint256 indexed leaseId, address indexed lessee, address indexed receiver, uint256 amount
    );
    event LeaseSettled(uint256 indexed leaseId, uint256 indexed positionId, LeaseStatus status);
    event ConfigUpdated(MarketConfig config);

    function config() external view returns (MarketConfig memory);
    function listingOf(uint256 positionId) external view returns (ListingRecord memory);
    function leaseOf(uint256 leaseId) external view returns (LeaseRecord memory);
    function activeLeaseFor(uint256 positionId) external view returns (uint256);
    function pendingRewards(uint256 leaseId) external view returns (uint256);
    function quote(uint256 positionId, uint40 duration) external view returns (LeaseQuote memory);
    function isLeaseActive(uint256 leaseId) external view returns (bool);

    function list(
        uint256 positionId,
        address paymentToken,
        uint256 basePricePerDay,
        uint256 minPricePerDay,
        uint40 expiresAt,
        LeaseTerms calldata terms
    ) external;
    function cancelListing(uint256 positionId) external;
    function openLease(uint256 positionId, uint40 duration, uint256 maxPrice)
        external
        returns (uint256 leaseId);
    function renewLease(uint256 leaseId, uint40 duration, uint256 maxPrice)
        external
        returns (uint256 newLeaseId);
    function checkpointLease(uint256 leaseId) external returns (uint256 rewardDebt);
    function claimRewards(uint256 leaseId, address receiver) external returns (uint256 amount);
    function settleExpiredLease(uint256 leaseId) external;
}
