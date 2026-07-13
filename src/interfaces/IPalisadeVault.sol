// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "./IERC20.sol";
import { IPalisadePositionToken } from "./IPalisadePositionToken.sol";
import { IRewardEscrow } from "./IRewardEscrow.sol";
import { VaultConfig } from "../types/PalisadeTypes.sol";

interface IPalisadeVault {
    event PositionDeposited(
        address indexed owner,
        uint256 indexed positionId,
        uint256 assets,
        uint256 shares,
        bytes32 metadataHash
    );
    event PositionIncreased(uint256 indexed positionId, uint256 assets, uint256 shares);
    event PositionWithdrawn(
        address indexed owner,
        uint256 indexed positionId,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event RewardsHarvested(
        address indexed caller, uint256 amount, uint256 fee, uint256 indexed index
    );
    event ConfigUpdated(VaultConfig config);
    event MarketUpdated(address indexed previousMarket, address indexed newMarket);

    function asset() external view returns (IERC20);
    function positionToken() external view returns (IPalisadePositionToken);
    function rewardEscrow() external view returns (IRewardEscrow);
    function market() external view returns (address);
    function totalPrincipal() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function totalRewardWeight() external view returns (uint256);
    function config() external view returns (VaultConfig memory);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function positionShares(uint256 positionId) external view returns (uint256);
    function positionPrincipal(uint256 positionId) external view returns (uint256);
    function positionRewardWeight(uint256 positionId) external view returns (uint256);
    function isPositionOwnerOrApproved(address account, uint256 positionId)
        external
        view
        returns (bool);
    function isPositionLocked(uint256 positionId) external view returns (bool);

    function deposit(uint256 assets, address receiver, bytes32 metadataHash)
        external
        returns (uint256 positionId, uint256 shares);
    function increasePosition(uint256 positionId, uint256 assets) external returns (uint256 shares);
    function withdrawPosition(uint256 positionId, uint256 shares, address receiver)
        external
        returns (uint256 assets);
    function harvestRewards(uint256 amount) external returns (uint256 distributed);
    function lockForLease(uint256 positionId) external;
    function unlockFromLease(uint256 positionId) external;
    function setMarket(address newMarket) external;
}
