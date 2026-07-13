// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseRecord } from "../src/types/PalisadeTypes.sol";
import { PalisadeTestBase } from "./PalisadeTestBase.sol";

contract PalisadeLeaseMarketTest is PalisadeTestBase {
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

    function testRenewalContinuityPreservesPendingRewards() public {
        _listPosition();
        _approveMarket(BOB);
        _approveMarket(CAROL);

        vm.prank(BOB);
        uint256 oldLeaseId = market.openLease(positionId, 10 days, type(uint256).max);

        vm.warp(block.timestamp + 9 days);
        _harvest(120 * UNIT);

        assertEq(market.pendingRewards(oldLeaseId), 120 * UNIT);

        vm.prank(CAROL);
        uint256 newLeaseId = market.renewLease(oldLeaseId, 7 days, type(uint256).max);

        LeaseRecord memory oldLease = market.leaseOf(oldLeaseId);
        LeaseRecord memory newLease = market.leaseOf(newLeaseId);

        assertEq(oldLease.rewardDebt, 0);
        assertEq(newLease.rewardDebt, 120 * UNIT);
        assertEq(newLease.lessee, CAROL);
        assertEq(newLease.start, oldLease.end);
        assertLt(block.timestamp, newLease.start);

        uint256 beforeClaim = asset.balanceOf(CAROL);
        vm.prank(CAROL);
        uint256 claimed = market.claimRewards(newLeaseId, CAROL);

        assertEq(claimed, 120 * UNIT);
        assertEq(asset.balanceOf(CAROL) - beforeClaim, 120 * UNIT);
        assertEq(market.pendingRewards(oldLeaseId), 0);
    }

    function testChainedRenewalsPreservePendingRewardsAcrossContinuations() public {
        address dave = address(0xDA7E);
        asset.mint(dave, 2000 * UNIT);
        _listPosition();
        _approveMarket(BOB);
        _approveMarket(CAROL);
        vm.prank(dave);
        asset.approve(address(market), type(uint256).max);

        vm.prank(BOB);
        uint256 leaseId = market.openLease(positionId, 10 days, type(uint256).max);

        vm.warp(block.timestamp + 9 days);
        _harvest(90 * UNIT);

        vm.prank(dave);
        uint256 intermediateLease = market.renewLease(leaseId, 5 days, type(uint256).max);

        LeaseRecord memory intermediateRecord = market.leaseOf(intermediateLease);
        vm.warp(intermediateRecord.end - 1 days);
        vm.prank(CAROL);
        uint256 finalLease = market.renewLease(intermediateLease, 5 days, type(uint256).max);

        assertEq(market.pendingRewards(leaseId), 0);
        assertEq(market.pendingRewards(intermediateLease), 0);
        assertEq(market.pendingRewards(finalLease), 90 * UNIT);

        uint256 beforeClaim = asset.balanceOf(CAROL);
        vm.prank(CAROL);
        assertEq(market.claimRewards(finalLease, CAROL), 90 * UNIT);
        assertEq(asset.balanceOf(CAROL) - beforeClaim, 90 * UNIT);
    }
}
