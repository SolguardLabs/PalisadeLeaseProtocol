// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseRecord, LeaseStatus, ListingRecord } from "../src/types/PalisadeTypes.sol";
import { PalisadeTestBase } from "./PalisadeTestBase.sol";

contract PalisadeLeaseMarketTest is PalisadeTestBase {
    function testListingRecordsOwnerTermsAndPriceBounds() public {
        _listPosition();

        ListingRecord memory listing = market.listingOf(positionId);
        assertTrue(listing.active);
        assertEq(listing.owner, OWNER);
        assertEq(listing.basePricePerDay, 10 * UNIT);
        assertEq(listing.minPricePerDay, 5 * UNIT);

        uint256 shortPrice = market.quote(positionId, 3 days).price;
        uint256 longPrice = market.quote(positionId, 10 days).price;
        assertGt(shortPrice, 0);
        assertGt(longPrice, shortPrice);
    }

    function testLeaseCanClaimRewardsFromItsOwnPeriod() public {
        _listPosition();
        _approveMarket(BOB);

        vm.prank(BOB);
        uint256 leaseId = market.openLease(positionId, 7 days, type(uint256).max);

        _harvest(100 * UNIT);
        assertEq(market.pendingRewards(leaseId), 100 * UNIT);

        uint256 beforeClaim = asset.balanceOf(BOB);
        vm.prank(BOB);
        uint256 claimed = market.claimRewards(leaseId, BOB);

        assertEq(claimed, 100 * UNIT);
        assertEq(asset.balanceOf(BOB) - beforeClaim, 100 * UNIT);
        assertEq(market.pendingRewards(leaseId), 0);
    }

    function testOpenLeaseRequiresAcceptableQuote() public {
        _listPosition();
        _approveMarket(BOB);

        vm.prank(BOB);
        vm.expectRevert();
        market.openLease(positionId, 7 days, 0);

        uint256 quote = market.quote(positionId, 7 days).price;
        vm.prank(BOB);
        uint256 leaseId = market.openLease(positionId, 7 days, quote);
        LeaseRecord memory lease = market.leaseOf(leaseId);
        assertEq(lease.lessee, BOB);
        assertEq(lease.pricePaid, quote);
        assertEq(market.activeLeaseFor(positionId), leaseId);
        assertTrue(vault.isPositionLocked(positionId));
    }

    function testRenewalCreatesScheduledContinuation() public {
        _listPosition();
        _approveMarket(BOB);
        _approveMarket(CAROL);

        vm.prank(BOB);
        uint256 originalId = market.openLease(positionId, 10 days, type(uint256).max);
        LeaseRecord memory original = market.leaseOf(originalId);

        vm.warp(original.end - 1 days);
        vm.prank(CAROL);
        uint256 continuationId = market.renewLease(originalId, 7 days, type(uint256).max);
        LeaseRecord memory continuation = market.leaseOf(continuationId);

        assertEq(continuation.predecessorId, originalId);
        assertEq(continuation.lessee, CAROL);
        assertEq(continuation.start, original.end);
        assertEq(continuation.end, original.end + 7 days);
        assertEq(market.activeLeaseFor(positionId), continuationId);
        assertEq(uint256(market.leaseOf(originalId).status), uint256(LeaseStatus.Settled));

        vm.warp(continuation.start + 1);
        _harvest(70 * UNIT);
        vm.prank(CAROL);
        assertEq(market.claimRewards(continuationId, CAROL), 70 * UNIT);
    }

    function testExpiredLeaseUnlocksPosition() public {
        _listPosition();
        _approveMarket(BOB);

        vm.prank(BOB);
        uint256 leaseId = market.openLease(positionId, 7 days, type(uint256).max);
        LeaseRecord memory lease = market.leaseOf(leaseId);
        vm.warp(lease.end);

        market.settleExpiredLease(leaseId);
        assertEq(market.activeLeaseFor(positionId), 0);
        assertFalse(vault.isPositionLocked(positionId));
        assertEq(uint256(market.leaseOf(leaseId).status), uint256(LeaseStatus.Expired));
    }
}
