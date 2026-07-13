// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IPalisadePositionToken } from "../interfaces/IPalisadePositionToken.sol";
import { PositionRecord } from "../types/PalisadeTypes.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/// @title PalisadePositionToken
/// @notice ERC721-like representation of productive principal held by PalisadeVault.
contract PalisadePositionToken is IPalisadePositionToken, PalisadeAccess {
    error TokenDoesNotExist(uint256 tokenId);
    error NotTokenOwner(address caller, uint256 tokenId);
    error NotApprovedOrOwner(address caller, uint256 tokenId);
    error TransferToZeroAddress();
    error TransferFromIncorrectOwner(address from, uint256 tokenId);
    error TransferToNonReceiver(address to);
    error PositionFrozenForLease(uint256 tokenId);
    error CallerNotVault(address caller);
    error CallerNotMarket(address caller);
    error VaultAlreadySet(address existingVault);

    bytes4 private constant _ERC721_RECEIVED = IERC721Receiver.onERC721Received.selector;

    string public override name;
    string public override symbol;
    uint256 public override totalSupply;

    address public vault;
    address public market;

    mapping(uint256 tokenId => address owner) private _ownerOf;
    mapping(address owner => uint256 balance) private _balanceOf;
    mapping(uint256 tokenId => address approved) private _tokenApprovals;
    mapping(address owner => mapping(address operator => bool approved)) private _operatorApprovals;
    mapping(uint256 tokenId => PositionRecord record) private _positions;

    uint256[] private _allTokens;
    mapping(uint256 tokenId => uint256 index) private _allTokenIndex;
    mapping(address owner => uint256[] tokens) private _ownedTokens;
    mapping(uint256 tokenId => uint256 index) private _ownedTokenIndex;

    constructor(
        string memory name_,
        string memory symbol_,
        address initialGovernor,
        address initialGuardian
    ) PalisadeAccess(initialGovernor, initialGuardian) {
        name = name_;
        symbol = symbol_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert CallerNotVault(msg.sender);
        _;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert CallerNotMarket(msg.sender);
        _;
    }

    modifier onlyMarketOrVault() {
        if (msg.sender != market && msg.sender != vault) revert CallerNotMarket(msg.sender);
        _;
    }

    function setVault(address newVault) external onlyGovernor {
        if (newVault == address(0)) revert ZeroAddress();
        if (vault != address(0)) revert VaultAlreadySet(vault);
        vault = newVault;
    }

    function setMarket(address newMarket) external override onlyGovernor {
        address previous = market;
        market = newMarket;
        emit MarketUpdated(previous, newMarket);
    }

    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) return 0;
        return _balanceOf[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address owner) {
        owner = _ownerOf[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist(tokenId);
    }

    function getApproved(uint256 tokenId) external view override returns (address) {
        _requireExists(tokenId);
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator)
        external
        view
        override
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    function isApprovedOrOwner(address spender, uint256 tokenId)
        public
        view
        override
        returns (bool)
    {
        address owner = ownerOf(tokenId);
        return spender == owner || _tokenApprovals[tokenId] == spender
            || _operatorApprovals[owner][spender];
    }

    function exists(uint256 tokenId) external view override returns (bool) {
        return _ownerOf[tokenId] != address(0);
    }

    function position(uint256 tokenId) external view override returns (PositionRecord memory) {
        _requireExists(tokenId);
        return _positions[tokenId];
    }

    function sharesOf(uint256 tokenId) external view override returns (uint256) {
        _requireExists(tokenId);
        return _positions[tokenId].shares;
    }

    function principalOf(uint256 tokenId) external view override returns (uint256) {
        _requireExists(tokenId);
        return _positions[tokenId].principal;
    }

    function rewardWeightOf(uint256 tokenId) external view override returns (uint256) {
        _requireExists(tokenId);
        return _positions[tokenId].rewardWeight;
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        return _allTokens[index];
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        return _ownedTokens[owner][index];
    }

    function approve(address to, uint256 tokenId) external override {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) {
            revert NotTokenOwner(msg.sender, tokenId);
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (!isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotApprovedOrOwner(msg.sender, tokenId);
        }
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
    {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            bytes4 response = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data);
            if (response != _ERC721_RECEIVED) revert TransferToNonReceiver(to);
        }
    }

    function mint(address to, uint256 shares, uint256 principal, bytes32 metadataHash)
        external
        override
        onlyVault
        returns (uint256 tokenId)
    {
        if (to == address(0)) revert TransferToZeroAddress();

        tokenId = uint256(
            keccak256(
                abi.encodePacked(
                    block.chainid, address(this), to, totalSupply, shares, principal, metadataHash
                )
            )
        );
        while (_ownerOf[tokenId] != address(0)) {
            tokenId = uint256(keccak256(abi.encodePacked(tokenId, block.timestamp, totalSupply)));
        }

        _ownerOf[tokenId] = to;
        unchecked {
            _balanceOf[to] += 1;
            totalSupply += 1;
        }

        _positions[tokenId] = PositionRecord({
            vault: vault,
            owner: to,
            shares: shares,
            principal: principal,
            rewardWeight: shares,
            createdAt: uint40(block.timestamp),
            updatedAt: uint40(block.timestamp),
            metadataHash: metadataHash,
            frozen: false
        });

        _addTokenToAllTokensEnumeration(tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(address(0), to, tokenId);
        emit PositionMinted(to, tokenId, shares, principal, metadataHash);
    }

    function burn(uint256 tokenId) external override onlyVault {
        address owner = ownerOf(tokenId);

        _clearApproval(owner, tokenId);
        _removeTokenFromOwnerEnumeration(owner, tokenId);
        _removeTokenFromAllTokensEnumeration(tokenId);

        unchecked {
            _balanceOf[owner] -= 1;
            totalSupply -= 1;
        }
        delete _ownerOf[tokenId];
        delete _positions[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function updatePosition(
        uint256 tokenId,
        uint256 shares,
        uint256 principal,
        uint256 rewardWeight
    ) external override onlyVault {
        _requireExists(tokenId);
        PositionRecord storage record = _positions[tokenId];
        record.shares = shares;
        record.principal = principal;
        record.rewardWeight = rewardWeight;
        record.updatedAt = uint40(block.timestamp);
        emit PositionUpdated(tokenId, shares, principal, rewardWeight);
    }

    function freezePosition(uint256 tokenId, bool frozen) external override onlyMarketOrVault {
        _requireExists(tokenId);
        _positions[tokenId].frozen = frozen;
        _positions[tokenId].updatedAt = uint40(block.timestamp);
        emit PositionFrozen(tokenId, frozen);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert TransferToZeroAddress();
        address owner = ownerOf(tokenId);
        if (owner != from) revert TransferFromIncorrectOwner(from, tokenId);
        if (_positions[tokenId].frozen) revert PositionFrozenForLease(tokenId);

        _clearApproval(owner, tokenId);
        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        unchecked {
            _balanceOf[from] -= 1;
            _balanceOf[to] += 1;
        }
        _ownerOf[tokenId] = to;
        _positions[tokenId].owner = to;
        _positions[tokenId].updatedAt = uint40(block.timestamp);

        emit Transfer(from, to, tokenId);
    }

    function _clearApproval(address owner, uint256 tokenId) internal {
        if (_tokenApprovals[tokenId] != address(0)) {
            delete _tokenApprovals[tokenId];
            emit Approval(owner, address(0), tokenId);
        }
    }

    function _requireExists(uint256 tokenId) internal view {
        if (_ownerOf[tokenId] == address(0)) revert TokenDoesNotExist(tokenId);
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _ownedTokenIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastIndex = _ownedTokens[from].length - 1;
        uint256 tokenIndex = _ownedTokenIndex[tokenId];
        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokenIndex[lastTokenId] = tokenIndex;
        }
        _ownedTokens[from].pop();
        delete _ownedTokenIndex[tokenId];
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokenIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        uint256 lastIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokenIndex[tokenId];
        uint256 lastTokenId = _allTokens[lastIndex];
        _allTokens[tokenIndex] = lastTokenId;
        _allTokenIndex[lastTokenId] = tokenIndex;
        _allTokens.pop();
        delete _allTokenIndex[tokenId];
    }
}
