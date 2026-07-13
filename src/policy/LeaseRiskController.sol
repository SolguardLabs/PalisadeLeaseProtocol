// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILeaseRiskController } from "../interfaces/ILeaseRiskController.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { LeaseQuote, LeaseTerms, ListingRecord, RiskParameter } from "../types/PalisadeTypes.sol";

/// @title LeaseRiskController
/// @notice Optional policy module used by integrators to gate listings and quoted leases.
contract LeaseRiskController is ILeaseRiskController, PalisadeAccess {
    error InvalidRiskParameter();
    error TokenNotAllowed(address token);
    error PrincipalLimitExceeded(uint256 totalPrincipal, uint256 limit);
    error PositionSharesExceeded(uint256 shares, uint256 limit);
    error OwnerFeeExceeded(uint256 feeBps, uint256 limit);
    error LateFeeExceeded(uint256 feeBps, uint256 limit);
    error PriceExceeded(uint256 price, uint256 limit);
    error DurationExceeded(uint256 duration, uint256 limit);

    RiskParameter private _parameters;
    mapping(address token => bool allowed) public override allowedPaymentToken;
    mapping(uint256 positionId => uint256 maxDuration) public override maxDurationOverride;
    mapping(uint256 positionId => uint256 maxPrice) public override maxPriceOverride;

    constructor(
        address initialGovernor,
        address initialGuardian,
        RiskParameter memory initialParameters
    ) PalisadeAccess(initialGovernor, initialGuardian) {
        _setRiskParameters(initialParameters);
    }

    function riskParameters() external view override returns (RiskParameter memory) {
        return _parameters;
    }

    function setRiskParameters(RiskParameter calldata newParameters) external onlyGovernor {
        _setRiskParameters(newParameters);
    }

    function setPaymentToken(address token, bool allowed) external onlyGovernor {
        if (token == address(0)) revert InvalidRiskParameter();
        allowedPaymentToken[token] = allowed;
        emit PaymentTokenUpdated(token, allowed);
    }

    function setPositionOverride(uint256 positionId, uint256 maxDuration, uint256 maxPrice)
        external
        onlyGovernorOrKeeper
    {
        maxDurationOverride[positionId] = maxDuration;
        maxPriceOverride[positionId] = maxPrice;
        emit PositionOverrideUpdated(positionId, maxDuration, maxPrice);
    }

    function validateListing(
        ListingRecord calldata listing,
        uint256 totalPrincipalAfterListing,
        uint256 positionShares
    ) external view override returns (bool) {
        if (!allowedPaymentToken[listing.paymentToken]) {
            revert TokenNotAllowed(listing.paymentToken);
        }
        if (
            _parameters.maxTotalPrincipal != 0
                && totalPrincipalAfterListing > _parameters.maxTotalPrincipal
        ) {
            revert PrincipalLimitExceeded(totalPrincipalAfterListing, _parameters.maxTotalPrincipal);
        }
        if (_parameters.maxPositionShares != 0 && positionShares > _parameters.maxPositionShares) {
            revert PositionSharesExceeded(positionShares, _parameters.maxPositionShares);
        }
        _validateTerms(listing.terms);
        return true;
    }

    function validateQuote(LeaseQuote calldata quote, LeaseTerms calldata terms)
        external
        view
        override
        returns (bool)
    {
        uint256 durationLimit = maxDurationOverride[quote.positionId];
        if (durationLimit == 0) durationLimit = terms.maxDuration;
        if (durationLimit != 0 && quote.duration > durationLimit) {
            revert DurationExceeded(quote.duration, durationLimit);
        }

        uint256 priceLimit = maxPriceOverride[quote.positionId];
        if (priceLimit == 0) priceLimit = _parameters.maxLeasePrice;
        if (priceLimit != 0 && quote.price > priceLimit) {
            revert PriceExceeded(quote.price, priceLimit);
        }
        _validateTerms(terms);
        return true;
    }

    function maxUtilizationBps(uint256 leasedWeight, uint256 totalWeight)
        external
        pure
        returns (uint256)
    {
        if (totalWeight == 0) return 0;
        return MathLib.mulDivDown(leasedWeight, MathLib.BPS, totalWeight);
    }

    function healthyDuration(uint256 duration, LeaseTerms calldata terms)
        external
        pure
        returns (bool)
    {
        return duration >= terms.minDuration && duration <= terms.maxDuration;
    }

    function _setRiskParameters(RiskParameter memory newParameters) internal {
        if (newParameters.maxOwnerFeeBps > 5000 || newParameters.maxLateFeeBps > 5000) {
            revert InvalidRiskParameter();
        }
        _parameters = newParameters;
        emit RiskParametersUpdated(newParameters);
    }

    function _validateTerms(LeaseTerms calldata terms) internal view {
        if (terms.ownerFeeBps > _parameters.maxOwnerFeeBps) {
            revert OwnerFeeExceeded(terms.ownerFeeBps, _parameters.maxOwnerFeeBps);
        }
        if (terms.lateFeeBps > _parameters.maxLateFeeBps) {
            revert LateFeeExceeded(terms.lateFeeBps, _parameters.maxLateFeeBps);
        }
    }
}
