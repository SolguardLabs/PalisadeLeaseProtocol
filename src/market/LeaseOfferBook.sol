// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IPalisadeLeaseMarket } from "../interfaces/IPalisadeLeaseMarket.sol";
import { IPalisadeVault } from "../interfaces/IPalisadeVault.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { Pausable } from "../security/Pausable.sol";
import { ReentrancyGuard } from "../security/ReentrancyGuard.sol";

/// @title LeaseOfferBook
/// @notice Sidecar intent book for negotiated Palisade lease orders.
/// @dev The core market is still the settlement venue; this book records maker intent and escrowed
///      consideration for workflows where owners review bids before listing or renewing.
contract LeaseOfferBook is PalisadeAccess, Pausable, ReentrancyGuard {
    using SafeTransferLib for IERC20;

    enum OfferStatus {
        None,
        Open,
        Cancelled,
        Accepted,
        Expired,
        Refunded
    }

    struct Offer {
        uint256 id;
        uint256 positionId;
        address maker;
        address paymentToken;
        uint256 price;
        uint40 duration;
        uint40 createdAt;
        uint40 deadline;
        bytes32 termsHash;
        OfferStatus status;
    }

    error InvalidMarket();
    error InvalidVault();
    error InvalidPaymentToken();
    error InvalidOffer();
    error InvalidDuration();
    error InvalidDeadline();
    error NotOfferMaker(address caller, uint256 offerId);
    error NotPositionOwner(address caller, uint256 positionId);
    error OfferNotOpen(uint256 offerId);
    error OfferExpired(uint256 offerId);
    error RefundUnavailable(uint256 offerId);

    event OfferCreated(
        uint256 indexed offerId,
        uint256 indexed positionId,
        address indexed maker,
        address paymentToken,
        uint256 price,
        uint40 duration,
        uint40 deadline,
        bytes32 termsHash
    );
    event OfferCancelled(uint256 indexed offerId, address indexed maker);
    event OfferAccepted(
        uint256 indexed offerId,
        uint256 indexed positionId,
        address indexed owner,
        address maker,
        uint256 price
    );
    event OfferRefunded(uint256 indexed offerId, address indexed maker, uint256 amount);
    event MarketUpdated(address indexed previousMarket, address indexed newMarket);

    IPalisadeLeaseMarket public market;
    IPalisadeVault public vault;
    uint256 public nextOfferId = 1;

    mapping(uint256 offerId => Offer offer) private _offers;
    mapping(address maker => uint256[] offerIds) private _offersByMaker;
    mapping(uint256 positionId => uint256[] offerIds) private _offersByPosition;

    constructor(address market_, address vault_, address initialGovernor, address initialGuardian)
        PalisadeAccess(initialGovernor, initialGuardian)
    {
        if (market_ == address(0)) revert InvalidMarket();
        if (vault_ == address(0)) revert InvalidVault();
        market = IPalisadeLeaseMarket(market_);
        vault = IPalisadeVault(vault_);
    }

    function offerOf(uint256 offerId) external view returns (Offer memory) {
        return _offers[offerId];
    }

    function offersByMaker(address maker) external view returns (uint256[] memory) {
        return _offersByMaker[maker];
    }

    function offersByPosition(uint256 positionId) external view returns (uint256[] memory) {
        return _offersByPosition[positionId];
    }

    function createOffer(
        uint256 positionId,
        address paymentToken,
        uint256 price,
        uint40 duration,
        uint40 deadline,
        bytes32 termsHash
    ) external nonReentrant whenNotPaused returns (uint256 offerId) {
        if (paymentToken == address(0)) revert InvalidPaymentToken();
        if (price == 0) revert InvalidOffer();
        if (duration == 0) revert InvalidDuration();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), price);

        offerId = nextOfferId++;
        _offers[offerId] = Offer({
            id: offerId,
            positionId: positionId,
            maker: msg.sender,
            paymentToken: paymentToken,
            price: price,
            duration: duration,
            createdAt: uint40(block.timestamp),
            deadline: deadline,
            termsHash: termsHash,
            status: OfferStatus.Open
        });
        _offersByMaker[msg.sender].push(offerId);
        _offersByPosition[positionId].push(offerId);

        emit OfferCreated(
            offerId, positionId, msg.sender, paymentToken, price, duration, deadline, termsHash
        );
    }

    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = _offers[offerId];
        if (offer.id == 0) revert InvalidOffer();
        if (offer.maker != msg.sender) revert NotOfferMaker(msg.sender, offerId);
        if (offer.status != OfferStatus.Open) revert OfferNotOpen(offerId);

        offer.status = OfferStatus.Cancelled;
        IERC20(offer.paymentToken).safeTransfer(offer.maker, offer.price);
        emit OfferCancelled(offerId, msg.sender);
    }

    function acceptOffer(uint256 offerId, address proceedsReceiver)
        external
        nonReentrant
        whenNotPaused
        returns (Offer memory accepted)
    {
        Offer storage offer = _offers[offerId];
        if (offer.id == 0) revert InvalidOffer();
        if (offer.status != OfferStatus.Open) revert OfferNotOpen(offerId);
        if (block.timestamp > offer.deadline) {
            offer.status = OfferStatus.Expired;
            revert OfferExpired(offerId);
        }
        if (!vault.isPositionOwnerOrApproved(msg.sender, offer.positionId)) {
            revert NotPositionOwner(msg.sender, offer.positionId);
        }
        if (proceedsReceiver == address(0)) proceedsReceiver = msg.sender;

        offer.status = OfferStatus.Accepted;
        IERC20(offer.paymentToken).safeTransfer(proceedsReceiver, offer.price);
        accepted = offer;

        emit OfferAccepted(offerId, offer.positionId, proceedsReceiver, offer.maker, offer.price);
    }

    function refundExpired(uint256 offerId) external nonReentrant {
        Offer storage offer = _offers[offerId];
        if (offer.id == 0) revert InvalidOffer();
        if (offer.status == OfferStatus.Open && block.timestamp > offer.deadline) {
            offer.status = OfferStatus.Expired;
        }
        if (offer.status != OfferStatus.Expired) revert RefundUnavailable(offerId);
        if (msg.sender != offer.maker && msg.sender != governor && !isKeeper[msg.sender]) {
            revert RefundUnavailable(offerId);
        }

        offer.status = OfferStatus.Refunded;
        IERC20(offer.paymentToken).safeTransfer(offer.maker, offer.price);
        emit OfferRefunded(offerId, offer.maker, offer.price);
    }

    function markExpired(uint256 offerId) external returns (bool expired) {
        Offer storage offer = _offers[offerId];
        if (offer.id == 0) revert InvalidOffer();
        if (offer.status == OfferStatus.Open && block.timestamp > offer.deadline) {
            offer.status = OfferStatus.Expired;
            expired = true;
        }
    }

    function setMarket(address newMarket) external onlyGovernor {
        if (newMarket == address(0)) revert InvalidMarket();
        address previous = address(market);
        market = IPalisadeLeaseMarket(newMarket);
        emit MarketUpdated(previous, newMarket);
    }

    function setPaused(bool newPaused) external onlyGovernorOrGuardian {
        _setPaused(newPaused);
    }
}
