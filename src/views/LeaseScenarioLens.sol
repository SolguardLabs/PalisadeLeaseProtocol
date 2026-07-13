// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IPalisadeLeaseMarket } from "../interfaces/IPalisadeLeaseMarket.sol";
import { IPalisadeVault } from "../interfaces/IPalisadeVault.sol";
import { IRewardEscrow } from "../interfaces/IRewardEscrow.sol";
import { RewardAttributionLib } from "../libraries/RewardAttributionLib.sol";
import { LeaseRecord } from "../types/PalisadeTypes.sol";

/// @title LeaseScenarioLens
/// @notice Builds reward attribution scenarios for a position's lease chain.
contract LeaseScenarioLens {
    using RewardAttributionLib for RewardAttributionLib.Segment[];

    struct Scenario {
        uint256 positionId;
        uint256 currentIndex;
        uint256 rewardWeight;
        uint256 marketPendingRewards;
        RewardAttributionLib.Segment[] segments;
    }

    IPalisadeLeaseMarket public immutable market;
    IPalisadeVault public immutable vault;
    IRewardEscrow public immutable escrow;

    constructor(address market_, address vault_, address escrow_) {
        market = IPalisadeLeaseMarket(market_);
        vault = IPalisadeVault(vault_);
        escrow = IRewardEscrow(escrow_);
    }

    function buildTwoLeaseScenario(uint256 oldLeaseId, uint256 newLeaseId)
        external
        view
        returns (Scenario memory scenario)
    {
        LeaseRecord memory oldLease = market.leaseOf(oldLeaseId);
        LeaseRecord memory newLease = market.leaseOf(newLeaseId);
        uint256 currentIndex = escrow.rewardIndex();
        uint256 weight = vault.positionRewardWeight(newLease.positionId);

        RewardAttributionLib.Segment[] memory segments = new RewardAttributionLib.Segment[](2);
        segments[0] = RewardAttributionLib.Segment({
            beneficiary: oldLease.lessee,
            startIndex: oldLease.rewardIndexCheckpoint,
            endIndex: newLease.rewardIndexCheckpoint,
            weight: weight,
            startTime: oldLease.start,
            endTime: oldLease.end
        });
        segments[1] = RewardAttributionLib.Segment({
            beneficiary: newLease.lessee,
            startIndex: newLease.rewardIndexCheckpoint,
            endIndex: currentIndex,
            weight: weight,
            startTime: newLease.start,
            endTime: newLease.end
        });

        scenario = Scenario({
            positionId: newLease.positionId,
            currentIndex: currentIndex,
            rewardWeight: weight,
            marketPendingRewards: market.pendingRewards(newLeaseId),
            segments: segments
        });
    }

    function expectedRewardsFor(RewardAttributionLib.Segment[] memory segments, address account)
        external
        pure
        returns (uint256 rewards, uint256 matchedSegments)
    {
        return RewardAttributionLib.rewardsFor(segments, account);
    }

    function totalExpectedRewards(RewardAttributionLib.Segment[] memory segments)
        external
        pure
        returns (uint256)
    {
        return RewardAttributionLib.totalRewards(segments);
    }

    function mergeScenario(RewardAttributionLib.Segment[] memory segments)
        external
        pure
        returns (RewardAttributionLib.Segment[] memory)
    {
        return RewardAttributionLib.mergeAdjacent(segments);
    }
}
