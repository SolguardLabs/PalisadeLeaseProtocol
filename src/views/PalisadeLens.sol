// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseLedger } from "../accounting/LeaseLedger.sol";
import { IPalisadeLeaseMarket } from "../interfaces/IPalisadeLeaseMarket.sol";
import { IPalisadeVault } from "../interfaces/IPalisadeVault.sol";
import { IRewardEscrow } from "../interfaces/IRewardEscrow.sol";
import { PalisadePositionToken } from "../token/PalisadePositionToken.sol";
import {
    LeaseQuote,
    LeaseRecord,
    ListingRecord,
    PositionRecord,
    RewardState
} from "../types/PalisadeTypes.sol";

/// @title PalisadeLens
/// @notice Read-only aggregation helpers for frontends and operators.
contract PalisadeLens {
    struct PositionView {
        uint256 positionId;
        PositionRecord position;
        ListingRecord listing;
        LeaseRecord activeLease;
        uint256 pendingRewards;
        bool locked;
    }

    struct LeaseView {
        LeaseRecord lease;
        ListingRecord listing;
        uint256 pendingRewards;
        uint256 currentRewardIndex;
        bool activeNow;
        bool claimableByLessee;
    }

    struct MarketView {
        RewardState rewards;
        uint256 totalPrincipal;
        uint256 totalShares;
        uint256 totalRewardWeight;
        uint256 nextLeaseId;
        address vault;
        address market;
        address escrow;
    }

    IPalisadeVault public immutable vault;
    IPalisadeLeaseMarket public immutable market;
    IRewardEscrow public immutable escrow;
    PalisadePositionToken public immutable positionToken;
    LeaseLedger public immutable ledger;

    constructor(
        address vault_,
        address market_,
        address escrow_,
        address positionToken_,
        address ledger_
    ) {
        vault = IPalisadeVault(vault_);
        market = IPalisadeLeaseMarket(market_);
        escrow = IRewardEscrow(escrow_);
        positionToken = PalisadePositionToken(positionToken_);
        ledger = LeaseLedger(ledger_);
    }

    function marketView() external view returns (MarketView memory view_) {
        view_ = MarketView({
            rewards: escrow.rewardState(),
            totalPrincipal: vault.totalPrincipal(),
            totalShares: vault.totalShares(),
            totalRewardWeight: vault.totalRewardWeight(),
            nextLeaseId: _nextLeaseId(),
            vault: address(vault),
            market: address(market),
            escrow: address(escrow)
        });
    }

    function positionView(uint256 positionId) public view returns (PositionView memory view_) {
        uint256 activeLeaseId = market.activeLeaseFor(positionId);
        LeaseRecord memory activeLease;
        uint256 pending;
        if (activeLeaseId != 0) {
            activeLease = market.leaseOf(activeLeaseId);
            pending = market.pendingRewards(activeLeaseId);
        }

        view_ = PositionView({
            positionId: positionId,
            position: positionToken.position(positionId),
            listing: market.listingOf(positionId),
            activeLease: activeLease,
            pendingRewards: pending,
            locked: vault.isPositionLocked(positionId)
        });
    }

    function leaseView(uint256 leaseId) public view returns (LeaseView memory view_) {
        LeaseRecord memory lease = market.leaseOf(leaseId);
        ListingRecord memory listing;
        if (lease.positionId != 0) listing = market.listingOf(lease.positionId);
        uint256 pending = market.pendingRewards(leaseId);

        view_ = LeaseView({
            lease: lease,
            listing: listing,
            pendingRewards: pending,
            currentRewardIndex: escrow.rewardIndex(),
            activeNow: market.isLeaseActive(leaseId),
            claimableByLessee: lease.lessee != address(0) && pending != 0
        });
    }

    function quotePosition(uint256 positionId, uint40 duration)
        external
        view
        returns (LeaseQuote memory)
    {
        return market.quote(positionId, duration);
    }

    function positionsOf(address owner) external view returns (PositionView[] memory views) {
        uint256 count = positionToken.balanceOf(owner);
        views = new PositionView[](count);
        for (uint256 i; i < count; ++i) {
            uint256 tokenId = positionToken.tokenOfOwnerByIndex(owner, i);
            views[i] = positionView(tokenId);
        }
    }

    function leases(uint256 fromId, uint256 count)
        external
        view
        returns (LeaseView[] memory views)
    {
        views = new LeaseView[](count);
        for (uint256 i; i < count; ++i) {
            views[i] = leaseView(fromId + i);
        }
    }

    function withdrawable(address token, address account) external view returns (uint256) {
        return ledger.creditOf(token, account);
    }

    function _nextLeaseId() internal view returns (uint256 id) {
        (bool success, bytes memory data) =
            address(market).staticcall(abi.encodeWithSignature("nextLeaseId()"));
        if (success && data.length == 32) id = abi.decode(data, (uint256));
    }
}
