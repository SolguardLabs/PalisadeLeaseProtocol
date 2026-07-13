// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "./IERC20.sol";
import { RewardState } from "../types/PalisadeTypes.sol";

interface IRewardEscrow {
    event RewardNotified(
        address indexed caller, uint256 amount, uint256 rewardWeight, uint256 indexed newIndex
    );
    event RewardPaid(
        uint256 indexed leaseId,
        uint256 indexed positionId,
        address indexed receiver,
        uint256 amount
    );
    event MarketUpdated(address indexed previousMarket, address indexed newMarket);
    event VaultUpdated(address indexed previousVault, address indexed newVault);

    function asset() external view returns (IERC20);
    function vault() external view returns (address);
    function market() external view returns (address);
    function rewardIndex() external view returns (uint256);
    function rewardState() external view returns (RewardState memory);
    function availableRewards() external view returns (uint256);
    function fundedRewardsOutstanding() external view returns (uint256);

    function notifyReward(uint256 amount, uint256 rewardWeight) external returns (uint256 index);
    function payReward(uint256 leaseId, uint256 positionId, address receiver, uint256 amount)
        external;
    function setVault(address newVault) external;
    function setMarket(address newMarket) external;
}
