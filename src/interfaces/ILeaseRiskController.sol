// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseQuote, LeaseTerms, ListingRecord, RiskParameter } from "../types/PalisadeTypes.sol";

interface ILeaseRiskController {
    event RiskParametersUpdated(RiskParameter parameters);
    event PaymentTokenUpdated(address indexed token, bool allowed);
    event PositionOverrideUpdated(
        uint256 indexed positionId, uint256 maxDuration, uint256 maxPrice
    );

    function riskParameters() external view returns (RiskParameter memory);
    function allowedPaymentToken(address token) external view returns (bool);
    function maxDurationOverride(uint256 positionId) external view returns (uint256);
    function maxPriceOverride(uint256 positionId) external view returns (uint256);

    function validateListing(
        ListingRecord calldata listing,
        uint256 totalPrincipalAfterListing,
        uint256 positionShares
    ) external view returns (bool);

    function validateQuote(LeaseQuote calldata quote, LeaseTerms calldata terms)
        external
        view
        returns (bool);
}
