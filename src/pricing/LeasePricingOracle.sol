// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILeasePricingOracle } from "../interfaces/ILeasePricingOracle.sol";
import { LeaseMath } from "../libraries/LeaseMath.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { TimeWindowLib } from "../libraries/TimeWindowLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { LeaseQuote, LeaseTerms, ListingRecord, RenewalMode } from "../types/PalisadeTypes.sol";

/// @title LeasePricingOracle
/// @notice Deterministic pricing module for Palisade lease listings.
contract LeasePricingOracle is ILeasePricingOracle, PalisadeAccess {
    using MathLib for uint256;

    error InvalidTerms();
    error InvalidModel();

    uint256 public baseUtilizationBps;
    uint256 public slopeBps;
    uint256 public maxPremiumBps;
    uint40 public targetDuration;
    uint16 public shortPremiumBps;
    uint16 public longDiscountBps;

    constructor(address initialGovernor, address initialGuardian)
        PalisadeAccess(initialGovernor, initialGuardian)
    {
        baseUtilizationBps = 250;
        slopeBps = 150;
        maxPremiumBps = 2000;
        targetDuration = 7 days;
        shortPremiumBps = 400;
        longDiscountBps = 600;
    }

    function setUtilizationModel(
        uint256 newBaseUtilizationBps,
        uint256 newSlopeBps,
        uint256 newMaxPremiumBps
    ) external onlyGovernor {
        if (newBaseUtilizationBps > MathLib.BPS || newMaxPremiumBps > 5000) {
            revert InvalidModel();
        }
        baseUtilizationBps = newBaseUtilizationBps;
        slopeBps = newSlopeBps;
        maxPremiumBps = newMaxPremiumBps;
        emit UtilizationModelUpdated(newBaseUtilizationBps, newSlopeBps, newMaxPremiumBps);
    }

    function setDurationModel(
        uint40 newTargetDuration,
        uint16 newShortPremiumBps,
        uint16 newLongDiscountBps
    ) external onlyGovernor {
        if (newTargetDuration == 0 || newShortPremiumBps > 5000 || newLongDiscountBps > 9000) {
            revert InvalidModel();
        }
        targetDuration = newTargetDuration;
        shortPremiumBps = newShortPremiumBps;
        longDiscountBps = newLongDiscountBps;
        emit DurationModelUpdated(newTargetDuration, newShortPremiumBps, newLongDiscountBps);
    }

    function quote(
        ListingRecord calldata listing,
        uint256 positionRewardWeight,
        uint40 duration,
        uint256 rewardIndex
    ) external view override returns (LeaseQuote memory result) {
        TimeWindowLib.ensureDuration(duration, listing.terms.minDuration, listing.terms.maxDuration);

        uint256 pricePerDay = _durationAdjustedPrice(listing, duration);
        uint256 premiumBps = LeaseMath.utilizationPremium(
            positionRewardWeight, rewardIndex, baseUtilizationBps, slopeBps, maxPremiumBps
        );
        if (premiumBps != 0) {
            pricePerDay += pricePerDay.bps(premiumBps);
        }

        uint256 price = LeaseMath.priceForDuration(pricePerDay, duration);
        (uint256 protocolFee, uint256 ownerProceeds, uint256 lesseeExtra) =
            LeaseMath.splitPrice(price, listing.terms);

        result = LeaseQuote({
            positionId: listing.positionId,
            price: price + lesseeExtra,
            protocolFee: protocolFee,
            ownerProceeds: ownerProceeds,
            duration: duration,
            rewardIndex: rewardIndex,
            utilizationBps: premiumBps,
            renewable: listing.terms.renewalMode != RenewalMode.Closed
        });
    }

    function validateTerms(LeaseTerms calldata terms) external pure override returns (bool) {
        if (terms.minDuration == 0 || terms.maxDuration < terms.minDuration) return false;
        if (terms.protocolFeeBps > 2000) return false;
        if (terms.ownerFeeBps > 5000) return false;
        if (terms.lateFeeBps > 5000) return false;
        if (terms.maxDiscountBps > 9000) return false;
        return true;
    }

    function _durationAdjustedPrice(ListingRecord calldata listing, uint40 duration)
        internal
        view
        returns (uint256)
    {
        uint256 pricePerDay = listing.basePricePerDay;
        if (duration < targetDuration) {
            uint256 shortfall = targetDuration - duration;
            uint256 premium = MathLib.mulDivDown(shortPremiumBps, shortfall, targetDuration);
            pricePerDay += pricePerDay.bps(premium);
        } else if (duration > targetDuration) {
            uint256 excess = duration - targetDuration;
            uint256 discount = MathLib.mulDivDown(longDiscountBps, excess, duration);
            discount = MathLib.min(discount, listing.terms.maxDiscountBps);
            pricePerDay = LeaseMath.discountedPrice(pricePerDay, discount);
            pricePerDay = MathLib.max(pricePerDay, listing.minPricePerDay);
        }
        return pricePerDay;
    }
}
