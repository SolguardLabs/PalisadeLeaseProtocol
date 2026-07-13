// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IRewardEscrow } from "../interfaces/IRewardEscrow.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { ReentrancyGuard } from "../security/ReentrancyGuard.sol";
import { RewardState } from "../types/PalisadeTypes.sol";

/// @title RewardEscrow
/// @notice Custodies funded yield and exposes a global index over productive position weight.
contract RewardEscrow is IRewardEscrow, PalisadeAccess, ReentrancyGuard {
    using SafeTransferLib for IERC20;

    error InvalidAsset();
    error CallerNotVault(address caller);
    error CallerNotMarket(address caller);
    error InvalidReceiver();
    error InsufficientRewardBalance(uint256 available, uint256 requested);
    error AmountOverflow();

    IERC20 public immutable override asset;
    address public override vault;
    address public override market;

    RewardState private _state;

    constructor(address initialGovernor, address initialGuardian, address asset_)
        PalisadeAccess(initialGovernor, initialGuardian)
    {
        if (asset_ == address(0)) revert InvalidAsset();
        asset = IERC20(asset_);
        _state.lastUpdated = uint40(block.timestamp);
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert CallerNotVault(msg.sender);
        _;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert CallerNotMarket(msg.sender);
        _;
    }

    function rewardIndex() external view override returns (uint256) {
        return _state.index;
    }

    function rewardState() external view override returns (RewardState memory) {
        return _state;
    }

    function availableRewards() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function fundedRewardsOutstanding() external view override returns (uint256) {
        return MathLib.saturatingSub(_state.totalFunded, _state.totalPaid);
    }

    function notifyReward(uint256 amount, uint256 rewardWeight)
        external
        override
        onlyVault
        returns (uint256 index)
    {
        uint256 distributable = amount + _state.undistributed;
        _state.totalFunded += amount;
        _state.lastUpdated = uint40(block.timestamp);

        if (distributable == 0) {
            emit RewardNotified(msg.sender, amount, rewardWeight, _state.index);
            return _state.index;
        }

        if (rewardWeight == 0) {
            _state.undistributed = distributable;
            emit RewardNotified(msg.sender, amount, rewardWeight, _state.index);
            return _state.index;
        }

        uint256 indexDelta = MathLib.mulDivDown(distributable, MathLib.RAY, rewardWeight);
        if (indexDelta == 0) {
            _state.undistributed = distributable;
            emit RewardNotified(msg.sender, amount, rewardWeight, _state.index);
            return _state.index;
        }

        uint256 indexedAssets = MathLib.mulDivDown(rewardWeight, indexDelta, MathLib.RAY);
        _state.index += indexDelta;
        _state.undistributed = distributable - indexedAssets;

        emit RewardNotified(msg.sender, amount, rewardWeight, _state.index);
        return _state.index;
    }

    function payReward(uint256 leaseId, uint256 positionId, address receiver, uint256 amount)
        external
        override
        onlyMarket
        nonReentrant
    {
        if (receiver == address(0)) revert InvalidReceiver();
        if (amount == 0) {
            emit RewardPaid(leaseId, positionId, receiver, 0);
            return;
        }

        uint256 available = asset.balanceOf(address(this));
        if (available < amount) revert InsufficientRewardBalance(available, amount);
        _state.totalPaid += amount;
        asset.safeTransfer(receiver, amount);
        emit RewardPaid(leaseId, positionId, receiver, amount);
    }

    function setVault(address newVault) external override onlyGovernor {
        if (newVault == address(0)) revert ZeroAddress();
        address previous = vault;
        vault = newVault;
        emit VaultUpdated(previous, newVault);
    }

    function setMarket(address newMarket) external override onlyGovernor {
        if (newMarket == address(0)) revert ZeroAddress();
        address previous = market;
        market = newMarket;
        emit MarketUpdated(previous, newMarket);
    }
}
