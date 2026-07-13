// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IPalisadePositionToken } from "../interfaces/IPalisadePositionToken.sol";
import { IPalisadeVault } from "../interfaces/IPalisadeVault.sol";
import { IRewardEscrow } from "../interfaces/IRewardEscrow.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { Pausable } from "../security/Pausable.sol";
import { ReentrancyGuard } from "../security/ReentrancyGuard.sol";
import { VaultConfig } from "../types/PalisadeTypes.sol";

/// @title ProductiveVault
/// @notice Custodies principal and mints transferable productive positions.
contract ProductiveVault is IPalisadeVault, PalisadeAccess, Pausable, ReentrancyGuard {
    using SafeTransferLib for IERC20;
    using MathLib for uint256;

    error InvalidAsset();
    error InvalidPositionToken();
    error InvalidRewardEscrow();
    error InvalidReceiver();
    error InvalidAmount();
    error DepositTooSmall(uint256 assets, uint256 minimum);
    error PositionTooLarge(uint256 principal, uint256 maximum);
    error PositionLocked(uint256 positionId);
    error CallerNotMarket(address caller);
    error NotOwnerOrApproved(address caller, uint256 positionId);
    error DepositsPaused();
    error WithdrawalsPaused();
    error HarvestPaused();
    error InsufficientPositionShares(uint256 available, uint256 requested);

    IERC20 public immutable override asset;
    IPalisadePositionToken public immutable override positionToken;
    IRewardEscrow public immutable override rewardEscrow;

    address public override market;
    uint256 public override totalPrincipal;
    uint256 public override totalShares;
    uint256 public override totalRewardWeight;

    VaultConfig private _config;
    mapping(uint256 positionId => bool locked) private _lockedForLease;

    constructor(
        address asset_,
        address positionToken_,
        address rewardEscrow_,
        address initialGovernor,
        address initialGuardian,
        VaultConfig memory initialConfig
    ) PalisadeAccess(initialGovernor, initialGuardian) {
        if (asset_ == address(0)) revert InvalidAsset();
        if (positionToken_ == address(0)) revert InvalidPositionToken();
        if (rewardEscrow_ == address(0)) revert InvalidRewardEscrow();

        asset = IERC20(asset_);
        positionToken = IPalisadePositionToken(positionToken_);
        rewardEscrow = IRewardEscrow(rewardEscrow_);
        _config = initialConfig;
        if (_config.feeRecipient == address(0)) _config.feeRecipient = initialGovernor;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert CallerNotMarket(msg.sender);
        _;
    }

    function config() external view override returns (VaultConfig memory) {
        return _config;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        if (totalShares == 0 || totalPrincipal == 0) return assets;
        return MathLib.mulDivDown(assets, totalShares, totalPrincipal);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        if (totalShares == 0 || totalPrincipal == 0) return shares;
        return MathLib.mulDivDown(shares, totalPrincipal, totalShares);
    }

    function positionShares(uint256 positionId) public view override returns (uint256) {
        return positionToken.sharesOf(positionId);
    }

    function positionPrincipal(uint256 positionId) public view override returns (uint256) {
        return positionToken.principalOf(positionId);
    }

    function positionRewardWeight(uint256 positionId) public view override returns (uint256) {
        return positionToken.rewardWeightOf(positionId);
    }

    function isPositionOwnerOrApproved(address account, uint256 positionId)
        public
        view
        override
        returns (bool)
    {
        return positionToken.isApprovedOrOwner(account, positionId);
    }

    function isPositionLocked(uint256 positionId) external view override returns (bool) {
        return _lockedForLease[positionId];
    }

    function deposit(uint256 assets, address receiver, bytes32 metadataHash)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 positionId, uint256 shares)
    {
        if (_config.depositsPaused) revert DepositsPaused();
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets == 0) revert InvalidAmount();
        if (assets < _config.minDeposit) revert DepositTooSmall(assets, _config.minDeposit);

        shares = previewDeposit(assets);
        if (shares == 0) revert InvalidAmount();
        if (_config.maxPositionPrincipal != 0 && assets > _config.maxPositionPrincipal) {
            revert PositionTooLarge(assets, _config.maxPositionPrincipal);
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);

        totalPrincipal += assets;
        totalShares += shares;
        totalRewardWeight += shares;

        positionId = positionToken.mint(receiver, shares, assets, metadataHash);
        emit PositionDeposited(receiver, positionId, assets, shares, metadataHash);
    }

    function increasePosition(uint256 positionId, uint256 assets)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (_config.depositsPaused) revert DepositsPaused();
        if (assets == 0) revert InvalidAmount();
        _requireOwnerOrApproved(msg.sender, positionId);
        _requireUnlocked(positionId);

        shares = previewDeposit(assets);
        if (shares == 0) revert InvalidAmount();

        uint256 newPrincipal = positionToken.principalOf(positionId) + assets;
        if (_config.maxPositionPrincipal != 0 && newPrincipal > _config.maxPositionPrincipal) {
            revert PositionTooLarge(newPrincipal, _config.maxPositionPrincipal);
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);

        uint256 newShares = positionToken.sharesOf(positionId) + shares;
        totalPrincipal += assets;
        totalShares += shares;
        totalRewardWeight += shares;
        positionToken.updatePosition(positionId, newShares, newPrincipal, newShares);

        emit PositionIncreased(positionId, assets, shares);
    }

    function withdrawPosition(uint256 positionId, uint256 shares, address receiver)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (_config.withdrawalsPaused) revert WithdrawalsPaused();
        if (receiver == address(0)) revert InvalidReceiver();
        if (shares == 0) revert InvalidAmount();
        _requireOwnerOrApproved(msg.sender, positionId);
        _requireUnlocked(positionId);

        uint256 currentShares = positionToken.sharesOf(positionId);
        if (currentShares < shares) revert InsufficientPositionShares(currentShares, shares);

        assets = previewRedeem(shares);
        uint256 currentPrincipal = positionToken.principalOf(positionId);
        uint256 newShares = currentShares - shares;
        uint256 newPrincipal = MathLib.saturatingSub(currentPrincipal, assets);

        totalPrincipal = MathLib.saturatingSub(totalPrincipal, assets);
        totalShares = MathLib.saturatingSub(totalShares, shares);
        totalRewardWeight = MathLib.saturatingSub(totalRewardWeight, shares);

        if (newShares == 0) {
            positionToken.burn(positionId);
        } else {
            positionToken.updatePosition(positionId, newShares, newPrincipal, newShares);
        }

        asset.safeTransfer(receiver, assets);
        emit PositionWithdrawn(msg.sender, positionId, receiver, assets, shares);
    }

    function harvestRewards(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 distributed)
    {
        if (_config.harvestPaused) revert HarvestPaused();
        if (amount == 0) revert InvalidAmount();

        uint256 fee = amount.bps(_config.harvestFeeBps);
        distributed = amount - fee;

        if (fee != 0) asset.safeTransferFrom(msg.sender, _config.feeRecipient, fee);
        asset.safeTransferFrom(msg.sender, address(rewardEscrow), distributed);
        uint256 newIndex = rewardEscrow.notifyReward(distributed, totalRewardWeight);

        emit RewardsHarvested(msg.sender, distributed, fee, newIndex);
    }

    function lockForLease(uint256 positionId) external override onlyMarket {
        _requireUnlocked(positionId);
        _lockedForLease[positionId] = true;
        positionToken.freezePosition(positionId, true);
    }

    function unlockFromLease(uint256 positionId) external override onlyMarket {
        _lockedForLease[positionId] = false;
        positionToken.freezePosition(positionId, false);
    }

    function setMarket(address newMarket) external override onlyGovernor {
        if (newMarket == address(0)) revert ZeroAddress();
        address previous = market;
        market = newMarket;
        emit MarketUpdated(previous, newMarket);
    }

    function setConfig(VaultConfig calldata newConfig) external onlyGovernor {
        _config = newConfig;
        if (_config.feeRecipient == address(0)) _config.feeRecipient = governor;
        emit ConfigUpdated(_config);
    }

    function setPaused(bool newPaused) external onlyGovernorOrGuardian {
        _setPaused(newPaused);
    }

    function _requireOwnerOrApproved(address account, uint256 positionId) internal view {
        if (!positionToken.isApprovedOrOwner(account, positionId)) {
            revert NotOwnerOrApproved(account, positionId);
        }
    }

    function _requireUnlocked(uint256 positionId) internal view {
        if (_lockedForLease[positionId]) revert PositionLocked(positionId);
    }
}
