// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseQuote, LeaseTerms, ListingRecord } from "../types/PalisadeTypes.sol";

interface ILeasePricingOracle {
    event UtilizationModelUpdated(
        uint256 baseUtilizationBps, uint256 slopeBps, uint256 maxPremiumBps
    );
    event DurationModelUpdated(
        uint40 targetDuration, uint16 shortPremiumBps, uint16 longDiscountBps
    );

    function quote(
        ListingRecord calldata listing,
        uint256 positionRewardWeight,
        uint40 duration,
        uint256 rewardIndex
    ) external view returns (LeaseQuote memory);

    function validateTerms(LeaseTerms calldata terms) external pure returns (bool);
}
