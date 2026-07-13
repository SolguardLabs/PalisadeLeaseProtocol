// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseRecord, LeaseStatus, ListingRecord, RenewalMode } from "../types/PalisadeTypes.sol";

library LeaseLifecycleLib {
    function canClaim(LeaseRecord memory lease, address account) internal pure returns (bool) {
        return lease.id != 0 && lease.lessee == account
            && (lease.status == LeaseStatus.Active
                || lease.status == LeaseStatus.Expired
                || lease.status == LeaseStatus.Settled);
    }

    function canRenew(LeaseRecord memory lease, ListingRecord memory listing, address account)
        internal
        view
        returns (bool)
    {
        if (lease.id == 0 || lease.status != LeaseStatus.Active) return false;
        if (!listing.active || listing.terms.renewalMode == RenewalMode.Closed) return false;
        if (listing.terms.renewalMode == RenewalMode.LesseeOnly && account != lease.lessee) {
            return false;
        }
        if (block.timestamp >= lease.end) return true;
        uint256 window = listing.terms.renewalWindow;
        return window >= lease.end || block.timestamp >= lease.end - window;
    }

    function statusAt(LeaseRecord memory lease, uint256 timestamp)
        internal
        pure
        returns (LeaseStatus)
    {
        if (lease.id == 0) return LeaseStatus.None;
        if (lease.status != LeaseStatus.Active) return lease.status;
        if (timestamp < lease.start) return LeaseStatus.Active;
        if (timestamp >= lease.end) return LeaseStatus.Expired;
        return LeaseStatus.Active;
    }

    function economicStart(LeaseRecord memory lease) internal pure returns (uint256) {
        return lease.start;
    }

    function economicEnd(LeaseRecord memory lease) internal pure returns (uint256) {
        return lease.end;
    }

    function overlaps(LeaseRecord memory a, LeaseRecord memory b) internal pure returns (bool) {
        if (a.positionId != b.positionId) return false;
        if (a.end <= b.start) return false;
        if (b.end <= a.start) return false;
        return true;
    }
}
