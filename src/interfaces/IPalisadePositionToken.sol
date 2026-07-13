// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PositionRecord } from "../types/PalisadeTypes.sol";

interface IPalisadePositionToken {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event PositionMinted(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 shares,
        uint256 principal,
        bytes32 metadataHash
    );
    event PositionUpdated(
        uint256 indexed tokenId, uint256 shares, uint256 principal, uint256 rewardWeight
    );
    event PositionFrozen(uint256 indexed tokenId, bool frozen);
    event MarketUpdated(address indexed previousMarket, address indexed newMarket);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
    function position(uint256 tokenId) external view returns (PositionRecord memory);
    function sharesOf(uint256 tokenId) external view returns (uint256);
    function principalOf(uint256 tokenId) external view returns (uint256);
    function rewardWeightOf(uint256 tokenId) external view returns (uint256);
    function exists(uint256 tokenId) external view returns (bool);

    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data)
        external;

    function mint(address to, uint256 shares, uint256 principal, bytes32 metadataHash)
        external
        returns (uint256 tokenId);
    function burn(uint256 tokenId) external;
    function updatePosition(
        uint256 tokenId,
        uint256 shares,
        uint256 principal,
        uint256 rewardWeight
    ) external;
    function freezePosition(uint256 tokenId, bool frozen) external;
    function setMarket(address newMarket) external;
}
