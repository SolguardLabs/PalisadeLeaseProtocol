// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { ILeasePricingOracle } from "../interfaces/ILeasePricingOracle.sol";
import { IPalisadeLeaseMarket } from "../interfaces/IPalisadeLeaseMarket.sol";
import { IPalisadePositionToken } from "../interfaces/IPalisadePositionToken.sol";
import { IPalisadeVault } from "../interfaces/IPalisadeVault.sol";
import { IRewardEscrow } from "../interfaces/IRewardEscrow.sol";
import { LeaseLedger } from "../accounting/LeaseLedger.sol";
import { LeaseMath } from "../libraries/LeaseMath.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { TimeWindowLib } from "../libraries/TimeWindowLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { Pausable } from "../security/Pausable.sol";
import { ReentrancyGuard } from "../security/ReentrancyGuard.sol";
import {
    LeaseQuote,
    LeaseRecord,
    LeaseStatus,
    LeaseTerms,
    ListingRecord,
    MarketConfig,
    RenewalMode
} from "../types/PalisadeTypes.sol";

/// @title PalisadeLeaseMarket
/// @notice Marketplace where owners lease the reward rights of productive vault positions.
/// @dev Renewal accounting checkpoints the outgoing lease before opening its continuation.
contract PalisadeLeaseMarket is IPalisadeLeaseMarket, PalisadeAccess, Pausable, ReentrancyGuard {
    using SafeTransferLib for IERC20;
    using MathLib for uint256;

    error InvalidVault();
    error InvalidPositionToken();
    error InvalidRewardEscrow();
    error InvalidPricingOracle();
    error InvalidLedger();
    error InvalidPaymentToken();
    error InvalidPrice();
    error InvalidListing();
    error InvalidLease();
    error ListingPaused();
    error LeasingPaused();
    error ClaimsPaused();
    error ListingNotActive(uint256 positionId);
    error LeaseNotActive(uint256 leaseId);
    error LeaseStillActive(uint256 leaseId);
    error ExistingLease(uint256 positionId, uint256 leaseId);
    error NotPositionOwner(address caller, uint256 positionId);
    error NotLeaseLessee(address caller, uint256 leaseId);
    error RenewalClosed(uint256 leaseId);
    error RenewalRestricted(uint256 leaseId, address expectedLessee);
    error PriceTooHigh(uint256 quoted, uint256 maximum);
    error FeeTooHigh(uint256 requested, uint256 maximum);

    uint256 public constant REWARD_INDEX_PRECISION = MathLib.RAY;

    IPalisadeVault public immutable vault;
    IPalisadePositionToken public immutable positionToken;
    IRewardEscrow public immutable rewardEscrow;
    ILeasePricingOracle public pricingOracle;
    LeaseLedger public ledger;

    uint256 public nextLeaseId = 1;

    MarketConfig private _config;
    mapping(uint256 positionId => ListingRecord listing) private _listings;
    mapping(uint256 leaseId => LeaseRecord lease) private _leases;
    mapping(uint256 positionId => uint256 leaseId) private _activeLeaseFor;

    constructor(
        address vault_,
        address positionToken_,
        address rewardEscrow_,
        address pricingOracle_,
        address ledger_,
        address initialGovernor,
        address initialGuardian,
        MarketConfig memory initialConfig
    ) PalisadeAccess(initialGovernor, initialGuardian) {
        if (vault_ == address(0)) revert InvalidVault();
        if (positionToken_ == address(0)) revert InvalidPositionToken();
        if (rewardEscrow_ == address(0)) revert InvalidRewardEscrow();
        if (pricingOracle_ == address(0)) revert InvalidPricingOracle();
        if (ledger_ == address(0)) revert InvalidLedger();

        vault = IPalisadeVault(vault_);
        positionToken = IPalisadePositionToken(positionToken_);
        rewardEscrow = IRewardEscrow(rewardEscrow_);
        pricingOracle = ILeasePricingOracle(pricingOracle_);
        ledger = LeaseLedger(ledger_);
        _config = initialConfig;
        if (_config.feeRecipient == address(0)) _config.feeRecipient = initialGovernor;
        if (_config.maxProtocolFeeBps == 0) _config.maxProtocolFeeBps = 2000;
    }

    function config() external view override returns (MarketConfig memory) {
        return _config;
    }

    function listingOf(uint256 positionId) external view override returns (ListingRecord memory) {
        return _listings[positionId];
    }

    function leaseOf(uint256 leaseId) external view override returns (LeaseRecord memory) {
        return _leases[leaseId];
    }

    function activeLeaseFor(uint256 positionId) external view override returns (uint256) {
        return _activeLeaseFor[positionId];
    }

    function isLeaseActive(uint256 leaseId) public view override returns (bool) {
        LeaseRecord memory lease = _leases[leaseId];
        return lease.status == LeaseStatus.Active && block.timestamp >= lease.start
            && block.timestamp < lease.end;
    }

    function pendingRewards(uint256 leaseId) public view override returns (uint256) {
        LeaseRecord memory lease = _leases[leaseId];
        if (lease.id == 0) return 0;
        uint256 currentIndex = rewardEscrow.rewardIndex();
        uint256 debt = lease.rewardDebt;
        if (currentIndex > lease.rewardIndexCheckpoint) {
            uint256 weight = vault.positionRewardWeight(lease.positionId);
            debt += LeaseMath.earnedRewards(
                weight, currentIndex - lease.rewardIndexCheckpoint, REWARD_INDEX_PRECISION
            );
        }
        return debt;
    }

    function quote(uint256 positionId, uint40 duration)
        public
        view
        override
        returns (LeaseQuote memory)
    {
        ListingRecord memory listing = _listings[positionId];
        if (!listing.active) revert ListingNotActive(positionId);
        return pricingOracle.quote(
            listing, vault.positionRewardWeight(positionId), duration, rewardEscrow.rewardIndex()
        );
    }

    function list(
        uint256 positionId,
        address paymentToken,
        uint256 basePricePerDay,
        uint256 minPricePerDay,
        uint40 expiresAt,
        LeaseTerms calldata terms
    ) external override whenNotPaused {
        if (_config.listingsPaused) revert ListingPaused();
        if (paymentToken == address(0)) revert InvalidPaymentToken();
        if (basePricePerDay == 0 || minPricePerDay > basePricePerDay) revert InvalidPrice();
        if (!vault.isPositionOwnerOrApproved(msg.sender, positionId)) {
            revert NotPositionOwner(msg.sender, positionId);
        }
        if (!pricingOracle.validateTerms(terms)) revert InvalidListing();
        if (terms.protocolFeeBps > _config.maxProtocolFeeBps) {
            revert FeeTooHigh(terms.protocolFeeBps, _config.maxProtocolFeeBps);
        }
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidListing();

        uint256 activeLeaseId = _activeLeaseFor[positionId];
        if (activeLeaseId != 0 && _leases[activeLeaseId].status == LeaseStatus.Active) {
            revert ExistingLease(positionId, activeLeaseId);
        }

        _listings[positionId] = ListingRecord({
            positionId: positionId,
            owner: positionToken.ownerOf(positionId),
            paymentToken: paymentToken,
            basePricePerDay: basePricePerDay,
            minPricePerDay: minPricePerDay,
            listedAt: uint40(block.timestamp),
            expiresAt: expiresAt,
            terms: terms,
            active: true
        });

        emit Listed(
            positionId, positionToken.ownerOf(positionId), paymentToken, basePricePerDay, expiresAt
        );
    }

    function cancelListing(uint256 positionId) external override {
        ListingRecord storage listing = _listings[positionId];
        if (!listing.active) revert ListingNotActive(positionId);
        if (msg.sender != listing.owner && !vault.isPositionOwnerOrApproved(msg.sender, positionId))
        {
            revert NotPositionOwner(msg.sender, positionId);
        }

        listing.active = false;
        emit ListingCancelled(positionId, msg.sender);
    }

    function openLease(uint256 positionId, uint40 duration, uint256 maxPrice)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 leaseId)
    {
        if (_config.leasesPaused) revert LeasingPaused();
        ListingRecord storage listing = _listings[positionId];
        if (!listing.active) revert ListingNotActive(positionId);
        TimeWindowLib.ensureListingLive(listing.expiresAt);

        uint256 activeLeaseId = _activeLeaseFor[positionId];
        if (activeLeaseId != 0 && _leases[activeLeaseId].status == LeaseStatus.Active) {
            revert ExistingLease(positionId, activeLeaseId);
        }

        LeaseQuote memory leaseQuote = quote(positionId, duration);
        if (leaseQuote.price > maxPrice) revert PriceTooHigh(leaseQuote.price, maxPrice);

        _collectLeasePayment(listing, leaseQuote);
        vault.lockForLease(positionId);

        uint40 start = uint40(block.timestamp);
        uint40 end = uint40(block.timestamp + duration);
        leaseId = _createLease(
            positionId,
            0,
            listing.owner,
            msg.sender,
            listing.paymentToken,
            leaseQuote.price,
            rewardEscrow.rewardIndex(),
            start,
            end,
            0
        );
        _activeLeaseFor[positionId] = leaseId;

        emit LeaseOpened(
            leaseId, positionId, listing.owner, msg.sender, start, end, leaseQuote.price
        );
    }

    function renewLease(uint256 leaseId, uint40 duration, uint256 maxPrice)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 newLeaseId)
    {
        if (_config.leasesPaused) revert LeasingPaused();
        LeaseRecord storage previousLease = _leases[leaseId];
        if (previousLease.id == 0) revert InvalidLease();
        if (previousLease.status != LeaseStatus.Active) revert LeaseNotActive(leaseId);

        ListingRecord storage listing = _listings[previousLease.positionId];
        if (!listing.active) revert ListingNotActive(previousLease.positionId);
        if (listing.terms.renewalMode == RenewalMode.Closed) revert RenewalClosed(leaseId);
        if (
            listing.terms.renewalMode == RenewalMode.LesseeOnly
                && msg.sender != previousLease.lessee
        ) {
            revert RenewalRestricted(leaseId, previousLease.lessee);
        }
        TimeWindowLib.ensureRenewalWindow(previousLease.end, listing.terms.renewalWindow);

        uint256 inheritedDebt = _checkpointLease(previousLease);
        LeaseQuote memory leaseQuote = quote(previousLease.positionId, duration);
        if (leaseQuote.price > maxPrice) revert PriceTooHigh(leaseQuote.price, maxPrice);

        _collectLeasePayment(listing, leaseQuote);

        previousLease.status = LeaseStatus.Settled;

        uint40 start =
            block.timestamp < previousLease.end ? previousLease.end : uint40(block.timestamp);
        uint40 end = uint40(uint256(start) + duration);

        newLeaseId = _createLease(
            previousLease.positionId,
            leaseId,
            previousLease.owner,
            msg.sender,
            previousLease.paymentToken,
            leaseQuote.price,
            rewardEscrow.rewardIndex(),
            start,
            end,
            inheritedDebt
        );
        _leases[newLeaseId].renewalCount = previousLease.renewalCount + 1;
        _activeLeaseFor[previousLease.positionId] = newLeaseId;

        // The settled lease is closed after its accounting has been rolled into the continuation.
        previousLease.rewardDebt = 0;

        emit LeaseRenewed(
            leaseId, newLeaseId, previousLease.positionId, msg.sender, start, end, inheritedDebt
        );
    }

    function checkpointLease(uint256 leaseId) external override returns (uint256 rewardDebt) {
        LeaseRecord storage lease = _leases[leaseId];
        if (lease.id == 0) revert InvalidLease();
        return _checkpointLease(lease);
    }

    function claimRewards(uint256 leaseId, address receiver)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 amount)
    {
        if (_config.claimsPaused) revert ClaimsPaused();
        LeaseRecord storage lease = _leases[leaseId];
        if (lease.id == 0) revert InvalidLease();
        if (msg.sender != lease.lessee) revert NotLeaseLessee(msg.sender, leaseId);

        _checkpointLease(lease);
        amount = lease.rewardDebt;
        lease.rewardDebt = 0;
        if (amount != 0) {
            rewardEscrow.payReward(leaseId, lease.positionId, receiver, amount);
        }

        emit LeaseRewardsClaimed(leaseId, msg.sender, receiver, amount);
    }

    function settleExpiredLease(uint256 leaseId) external override nonReentrant {
        LeaseRecord storage lease = _leases[leaseId];
        if (lease.id == 0) revert InvalidLease();
        if (lease.status != LeaseStatus.Active) revert LeaseNotActive(leaseId);
        if (block.timestamp < lease.end) revert LeaseStillActive(leaseId);

        _checkpointLease(lease);
        lease.status = LeaseStatus.Expired;

        if (_activeLeaseFor[lease.positionId] == leaseId) {
            delete _activeLeaseFor[lease.positionId];
            vault.unlockFromLease(lease.positionId);
        }

        emit LeaseSettled(leaseId, lease.positionId, LeaseStatus.Expired);
    }

    function setConfig(MarketConfig calldata newConfig) external onlyGovernor {
        if (newConfig.protocolFeeBps > newConfig.maxProtocolFeeBps) {
            revert FeeTooHigh(newConfig.protocolFeeBps, newConfig.maxProtocolFeeBps);
        }
        _config = newConfig;
        if (_config.feeRecipient == address(0)) _config.feeRecipient = governor;
        emit ConfigUpdated(_config);
    }

    function setPricingOracle(address newPricingOracle) external onlyGovernor {
        if (newPricingOracle == address(0)) revert InvalidPricingOracle();
        pricingOracle = ILeasePricingOracle(newPricingOracle);
    }

    function setLedger(address newLedger) external onlyGovernor {
        if (newLedger == address(0)) revert InvalidLedger();
        ledger = LeaseLedger(newLedger);
    }

    function setPaused(bool newPaused) external onlyGovernorOrGuardian {
        _setPaused(newPaused);
    }

    function _collectLeasePayment(ListingRecord storage listing, LeaseQuote memory leaseQuote)
        internal
    {
        IERC20 token = IERC20(listing.paymentToken);
        token.safeTransferFrom(msg.sender, address(ledger), leaseQuote.price);

        uint256 protocolFee = leaseQuote.protocolFee;
        uint256 ownerAmount = leaseQuote.price - protocolFee;
        ledger.creditPayment(
            listing.paymentToken, listing.owner, _config.feeRecipient, ownerAmount, protocolFee
        );
    }

    function _createLease(
        uint256 positionId,
        uint256 predecessorId,
        address owner,
        address lessee,
        address paymentToken,
        uint256 pricePaid,
        uint256 rewardIndexCheckpoint,
        uint40 start,
        uint40 end,
        uint256 rewardDebt
    ) internal returns (uint256 leaseId) {
        leaseId = nextLeaseId++;
        _leases[leaseId] = LeaseRecord({
            id: leaseId,
            positionId: positionId,
            predecessorId: predecessorId,
            owner: owner,
            lessee: lessee,
            paymentToken: paymentToken,
            pricePaid: pricePaid,
            rewardIndexCheckpoint: rewardIndexCheckpoint,
            rewardDebt: rewardDebt,
            start: start,
            end: end,
            createdAt: uint40(block.timestamp),
            renewalCount: 0,
            status: LeaseStatus.Active
        });
    }

    function _checkpointLease(LeaseRecord storage lease) internal returns (uint256 rewardDebt) {
        uint256 currentIndex = rewardEscrow.rewardIndex();
        uint256 previousIndex = lease.rewardIndexCheckpoint;
        uint256 rewardDelta;

        if (currentIndex > previousIndex) {
            uint256 weight = vault.positionRewardWeight(lease.positionId);
            rewardDelta = LeaseMath.earnedRewards(
                weight, currentIndex - previousIndex, REWARD_INDEX_PRECISION
            );
            lease.rewardDebt += rewardDelta;
            lease.rewardIndexCheckpoint = currentIndex;
        }

        rewardDebt = lease.rewardDebt;
        emit LeaseCheckpointed(
            lease.id, lease.positionId, rewardDelta, rewardDebt, lease.rewardIndexCheckpoint
        );
    }
}
