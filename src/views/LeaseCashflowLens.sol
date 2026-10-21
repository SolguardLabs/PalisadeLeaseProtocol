// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { MathLib } from "../libraries/MathLib.sol";
import { LeaseQuote } from "../types/PalisadeTypes.sol";

/// @title LeaseCashflowLens
/// @notice Read-only lease economics for user interfaces and operator forecasts.
/// @dev Forecast inputs are assumptions, not guaranteed or claimable balances.
contract LeaseCashflowLens {
    error InvalidQuote();
    error InvalidRetention();
    error InvalidPrincipal();

    struct Forecast {
        uint256 quotedRent;
        uint256 ownerProceeds;
        uint256 expectedRewards;
        uint256 stressedRewards;
        uint256 lesseeSurplus;
        uint256 lesseeShortfall;
        uint256 coverageBps;
        uint256 breakEvenRewardForecast;
    }

    function forecast(LeaseQuote calldata leaseQuote, uint256 expectedRewards, uint16 retentionBps)
        external
        pure
        returns (Forecast memory result)
    {
        if (leaseQuote.price == 0 || leaseQuote.ownerProceeds > leaseQuote.price) {
            revert InvalidQuote();
        }
        if (retentionBps == 0 || retentionBps > MathLib.BPS) revert InvalidRetention();

        uint256 stressed = MathLib.mulDivDown(expectedRewards, retentionBps, MathLib.BPS);
        uint256 surplus = MathLib.saturatingSub(stressed, leaseQuote.price);
        uint256 shortfall = MathLib.saturatingSub(leaseQuote.price, stressed);

        result = Forecast({
            quotedRent: leaseQuote.price,
            ownerProceeds: leaseQuote.ownerProceeds,
            expectedRewards: expectedRewards,
            stressedRewards: stressed,
            lesseeSurplus: surplus,
            lesseeShortfall: shortfall,
            coverageBps: MathLib.mulDivDown(stressed, MathLib.BPS, leaseQuote.price),
            breakEvenRewardForecast: MathLib.mulDivUp(leaseQuote.price, MathLib.BPS, retentionBps)
        });
    }

    function annualizedOwnerYieldBps(uint256 ownerProceeds, uint256 principal, uint40 duration)
        external
        pure
        returns (uint256)
    {
        if (principal == 0 || duration == 0) revert InvalidPrincipal();
        return MathLib.mulDivDown(ownerProceeds, 365 days * MathLib.BPS, principal) / duration;
    }
}
