// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum LeaseStatus {
    None,
    Listed,
    Active,
    Expired,
    Settled,
    Cancelled,
    Defaulted
}

enum RenewalMode {
    Closed,
    LesseeOnly,
    PublicDutch,
    PublicFixed
}

enum FeeSide {
    Owner,
    Lessee,
    Split
}

struct PositionRecord {
    address vault;
    address owner;
    uint256 shares;
    uint256 principal;
    uint256 rewardWeight;
    uint40 createdAt;
    uint40 updatedAt;
    bytes32 metadataHash;
    bool frozen;
}

struct LeaseTerms {
    uint40 minDuration;
    uint40 maxDuration;
    uint40 renewalWindow;
    uint16 protocolFeeBps;
    uint16 ownerFeeBps;
    uint16 lateFeeBps;
    uint16 maxDiscountBps;
    RenewalMode renewalMode;
    FeeSide feeSide;
}

struct LeaseQuote {
    uint256 positionId;
    uint256 price;
    uint256 protocolFee;
    uint256 ownerProceeds;
    uint256 duration;
    uint256 rewardIndex;
    uint256 utilizationBps;
    bool renewable;
}

struct LeaseRecord {
    uint256 id;
    uint256 positionId;
    uint256 predecessorId;
    address owner;
    address lessee;
    address paymentToken;
    uint256 pricePaid;
    uint256 rewardIndexCheckpoint;
    uint256 rewardDebt;
    uint40 start;
    uint40 end;
    uint40 createdAt;
    uint16 renewalCount;
    LeaseStatus status;
}

struct ListingRecord {
    uint256 positionId;
    address owner;
    address paymentToken;
    uint256 basePricePerDay;
    uint256 minPricePerDay;
    uint40 listedAt;
    uint40 expiresAt;
    LeaseTerms terms;
    bool active;
}

struct RewardState {
    uint256 index;
    uint256 undistributed;
    uint256 totalFunded;
    uint256 totalPaid;
    uint40 lastUpdated;
}

struct AccountClaim {
    uint256 leaseId;
    uint256 positionId;
    address receiver;
    uint256 amount;
    uint40 claimedAt;
}

struct VaultConfig {
    uint256 minDeposit;
    uint256 maxPositionPrincipal;
    uint16 harvestFeeBps;
    uint16 reserveBps;
    address feeRecipient;
    bool depositsPaused;
    bool withdrawalsPaused;
    bool harvestPaused;
}

struct MarketConfig {
    uint40 minLeaseDuration;
    uint40 maxLeaseDuration;
    uint40 defaultRenewalWindow;
    uint16 protocolFeeBps;
    uint16 maxProtocolFeeBps;
    address feeRecipient;
    bool listingsPaused;
    bool leasesPaused;
    bool claimsPaused;
}

struct RiskParameter {
    uint256 maxTotalPrincipal;
    uint256 maxPositionShares;
    uint256 maxLeasePrice;
    uint16 maxOwnerFeeBps;
    uint16 maxLateFeeBps;
    uint40 maxClockSkew;
}
