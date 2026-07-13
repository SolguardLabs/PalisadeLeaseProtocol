// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library TimeWindowLib {
    error InvalidDuration(uint256 duration, uint256 minDuration, uint256 maxDuration);
    error ListingExpired(uint256 nowTime, uint256 expiresAt);
    error NotInRenewalWindow(uint256 nowTime, uint256 windowStart, uint256 leaseEnd);

    function ensureDuration(uint256 duration, uint256 minDuration, uint256 maxDuration)
        internal
        pure
    {
        if (duration < minDuration || duration > maxDuration) {
            revert InvalidDuration(duration, minDuration, maxDuration);
        }
    }

    function ensureListingLive(uint256 expiresAt) internal view {
        if (expiresAt != 0 && block.timestamp > expiresAt) {
            revert ListingExpired(block.timestamp, expiresAt);
        }
    }

    function inRenewalWindow(uint256 nowTime, uint256 leaseEnd, uint256 renewalWindow)
        internal
        pure
        returns (bool)
    {
        if (nowTime >= leaseEnd) return true;
        if (renewalWindow >= leaseEnd) return true;
        return nowTime >= leaseEnd - renewalWindow;
    }

    function ensureRenewalWindow(uint256 leaseEnd, uint256 renewalWindow) internal view {
        uint256 windowStart = renewalWindow >= leaseEnd ? 0 : leaseEnd - renewalWindow;
        if (!inRenewalWindow(block.timestamp, leaseEnd, renewalWindow)) {
            revert NotInRenewalWindow(block.timestamp, windowStart, leaseEnd);
        }
    }

    function remaining(uint256 end) internal view returns (uint256) {
        return block.timestamp >= end ? 0 : end - block.timestamp;
    }

    function elapsed(uint256 start) internal view returns (uint256) {
        return block.timestamp <= start ? 0 : block.timestamp - start;
    }
}
