// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseLedger } from "../accounting/LeaseLedger.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IPalisadeLeaseMarket } from "../interfaces/IPalisadeLeaseMarket.sol";
import { IPalisadeVault } from "../interfaces/IPalisadeVault.sol";
import { IRewardEscrow } from "../interfaces/IRewardEscrow.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { LeaseRecord, LeaseStatus, RewardState } from "../types/PalisadeTypes.sol";

/// @title PalisadeInvariantLens
/// @notice Helper checks used by auditors and invariant tests.
contract PalisadeInvariantLens {
    struct RewardSolvency {
        uint256 funded;
        uint256 paid;
        uint256 escrowBalance;
        uint256 sampledPending;
        uint256 requiredForSample;
        uint256 deficitForSample;
        bool solventForSample;
    }

    struct LeaseContinuity {
        uint256 leaseId;
        uint256 predecessorId;
        uint256 positionId;
        uint256 previousEnd;
        uint256 currentStart;
        bool hasGap;
        bool overlaps;
        bool predecessorSettled;
    }

    struct PrincipalConservation {
        uint256 vaultPrincipal;
        uint256 vaultShares;
        uint256 vaultRewardWeight;
        uint256 sampledPositionPrincipal;
        uint256 sampledPositionShares;
        uint256 sampledPositionWeight;
    }

    IPalisadeVault public immutable vault;
    IPalisadeLeaseMarket public immutable market;
    IRewardEscrow public immutable escrow;
    LeaseLedger public immutable ledger;

    constructor(address vault_, address market_, address escrow_, address ledger_) {
        vault = IPalisadeVault(vault_);
        market = IPalisadeLeaseMarket(market_);
        escrow = IRewardEscrow(escrow_);
        ledger = LeaseLedger(ledger_);
    }

    function rewardSolvency(uint256[] calldata leaseIds)
        external
        view
        returns (RewardSolvency memory solvency)
    {
        RewardState memory state = escrow.rewardState();
        uint256 sampledPendingTotal;
        for (uint256 i; i < leaseIds.length; ++i) {
            sampledPendingTotal += market.pendingRewards(leaseIds[i]);
        }

        uint256 outstanding = MathLib.saturatingSub(state.totalFunded, state.totalPaid);
        uint256 balance = escrow.asset().balanceOf(address(escrow));
        uint256 required = sampledPendingTotal;
        uint256 deficit = required > balance ? required - balance : 0;

        solvency = RewardSolvency({
            funded: state.totalFunded,
            paid: state.totalPaid,
            escrowBalance: balance,
            sampledPending: sampledPendingTotal,
            requiredForSample: required,
            deficitForSample: deficit,
            solventForSample: balance >= required && outstanding >= sampledPendingTotal
        });
    }

    function leaseContinuity(uint256 leaseId)
        external
        view
        returns (LeaseContinuity memory result)
    {
        LeaseRecord memory current = market.leaseOf(leaseId);
        LeaseRecord memory previous;
        if (current.predecessorId != 0) previous = market.leaseOf(current.predecessorId);

        result = LeaseContinuity({
            leaseId: leaseId,
            predecessorId: current.predecessorId,
            positionId: current.positionId,
            previousEnd: previous.end,
            currentStart: current.start,
            hasGap: current.predecessorId != 0 && previous.end < current.start,
            overlaps: current.predecessorId != 0 && previous.end > current.start,
            predecessorSettled: current.predecessorId == 0 || previous.status == LeaseStatus.Settled
        });
    }

    function principalConservation(uint256[] calldata positionIds)
        external
        view
        returns (PrincipalConservation memory result)
    {
        uint256 sampledPrincipal;
        uint256 sampledShares;
        uint256 sampledWeight;
        for (uint256 i; i < positionIds.length; ++i) {
            sampledPrincipal += vault.positionPrincipal(positionIds[i]);
            sampledShares += vault.positionShares(positionIds[i]);
            sampledWeight += vault.positionRewardWeight(positionIds[i]);
        }

        result = PrincipalConservation({
            vaultPrincipal: vault.totalPrincipal(),
            vaultShares: vault.totalShares(),
            vaultRewardWeight: vault.totalRewardWeight(),
            sampledPositionPrincipal: sampledPrincipal,
            sampledPositionShares: sampledShares,
            sampledPositionWeight: sampledWeight
        });
    }

    function paymentLedgerSolvent(address token) external view returns (bool, uint256, uint256) {
        uint256 tracked = ledger.totalCredits(token);
        uint256 balance = IERC20(token).balanceOf(address(ledger));
        return (balance >= tracked, balance, tracked);
    }

    function rewardDebtDelta(uint256 olderLeaseId, uint256 newerLeaseId)
        external
        view
        returns (int256)
    {
        uint256 older = market.pendingRewards(olderLeaseId);
        uint256 newer = market.pendingRewards(newerLeaseId);
        if (newer >= older) return int256(newer - older);
        return -int256(older - newer);
    }

    function sampledPending(uint256 fromLeaseId, uint256 count)
        external
        view
        returns (uint256 sum)
    {
        for (uint256 i; i < count; ++i) {
            sum += market.pendingRewards(fromLeaseId + i);
        }
    }

    function leaseStatusVector(uint256 fromLeaseId, uint256 count)
        external
        view
        returns (LeaseStatus[] memory statuses)
    {
        statuses = new LeaseStatus[](count);
        for (uint256 i; i < count; ++i) {
            statuses[i] = market.leaseOf(fromLeaseId + i).status;
        }
    }
}
