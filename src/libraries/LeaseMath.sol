// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FeeSide, LeaseTerms } from "../types/PalisadeTypes.sol";
import { MathLib } from "./MathLib.sol";

library LeaseMath {
    using MathLib for uint256;

    uint256 internal constant ONE_DAY = 1 days;

    function priceForDuration(uint256 pricePerDay, uint256 duration)
        internal
        pure
        returns (uint256)
    {
        return MathLib.mulDivUp(pricePerDay, duration, ONE_DAY);
    }

    function protocolFee(uint256 grossPrice, uint256 feeBps) internal pure returns (uint256) {
        return grossPrice.bps(feeBps);
    }

    function ownerFee(uint256 grossPrice, uint256 feeBps) internal pure returns (uint256) {
        return grossPrice.bps(feeBps);
    }

    function splitPrice(uint256 grossPrice, LeaseTerms memory terms)
        internal
        pure
        returns (uint256 protocolAmount, uint256 ownerAmount, uint256 lesseeExtra)
    {
        protocolAmount = protocolFee(grossPrice, terms.protocolFeeBps);
        uint256 ownerSideFee = ownerFee(grossPrice, terms.ownerFeeBps);

        if (terms.feeSide == FeeSide.Owner) {
            ownerAmount = grossPrice - protocolAmount - ownerSideFee;
            lesseeExtra = 0;
        } else if (terms.feeSide == FeeSide.Lessee) {
            ownerAmount = grossPrice;
            lesseeExtra = protocolAmount + ownerSideFee;
        } else {
            uint256 halfProtocol = protocolAmount / 2;
            uint256 halfOwnerFee = ownerSideFee / 2;
            ownerAmount = grossPrice - halfProtocol - halfOwnerFee;
            lesseeExtra = protocolAmount - halfProtocol + ownerSideFee - halfOwnerFee;
        }
    }

    function earnedRewards(uint256 rewardWeight, uint256 indexDelta, uint256 precision)
        internal
        pure
        returns (uint256)
    {
        if (rewardWeight == 0 || indexDelta == 0) return 0;
        return MathLib.mulDivDown(rewardWeight, indexDelta, precision);
    }

    function utilizationPremium(
        uint256 rewardWeight,
        uint256 index,
        uint256 baseUtilizationBps,
        uint256 slopeBps,
        uint256 maxPremiumBps
    ) internal pure returns (uint256) {
        if (rewardWeight == 0 || index == 0) return 0;
        uint256 signal = MathLib.mulDivDown(MathLib.sqrt(rewardWeight), MathLib.sqrt(index), 1e18);
        uint256 premium = baseUtilizationBps + MathLib.mulDivDown(signal, slopeBps, 10_000);
        return MathLib.min(premium, maxPremiumBps);
    }

    function discountedPrice(uint256 basePrice, uint256 discountBps)
        internal
        pure
        returns (uint256)
    {
        if (discountBps == 0) return basePrice;
        if (discountBps >= MathLib.BPS) return 0;
        return basePrice - basePrice.bps(discountBps);
    }
}
