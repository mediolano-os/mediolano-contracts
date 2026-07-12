// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// An IP collection: an ERC-721 owned by its creator. Deployed as a clone by
/// MIPRegistry; the registry holds no rights over the collection after creation.
/// Each token carries an immutable registration record — metadata URI, original
/// creator, and registration timestamp — plus an immutable per-token ERC-2981
/// royalty set at mint with the minting owner as receiver.
contract MIPCollection is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable
{
    uint256 private constant MAX_NAME_LEN = 256;
    uint256 private constant MAX_SYMBOL_LEN = 64;
    uint256 private constant MAX_BASE_URI_LEN = 2048;
    uint256 private constant MAX_TOKEN_URI_LEN = 2048;

    uint256 private _collectionId;
    address private _registry;
    string private _baseUriValue;
    uint256 private _nextTokenId;
    mapping(uint256 tokenId => address) private _tokenCreator;
    mapping(uint256 tokenId => uint64) private _tokenRegisteredAt;
    mapping(uint256 tokenId => bool) private _archived;

    event TokenMinted(uint256 indexed tokenId, address indexed owner, string metadataUri, uint96 royaltyBps);
    event TokenMintedBatch(uint256[] tokenIds, address operator);
    event TokenArchived(uint256 indexed tokenId);

    error MIPInvalidName();
    error MIPInvalidSymbol();
    error MIPInvalidBaseUri();
    error MIPInvalidTokenUri();
    error MIPLengthMismatch();
    error MIPEmptyBatch();
    error MIPNotTokenOwner(uint256 tokenId);
    error MIPTokenArchived(uint256 tokenId);
    error MIPAlreadyArchived(uint256 tokenId);
    error MIPRenounceDisabled();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 collectionId_,
        address creator,
        string calldata name_,
        string calldata symbol_,
        string calldata baseUri_
    ) external initializer {
        if (bytes(name_).length == 0 || bytes(name_).length > MAX_NAME_LEN) revert MIPInvalidName();
        if (bytes(symbol_).length == 0 || bytes(symbol_).length > MAX_SYMBOL_LEN) revert MIPInvalidSymbol();
        if (bytes(baseUri_).length > MAX_BASE_URI_LEN) revert MIPInvalidBaseUri();
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __ERC2981_init();
        __Ownable_init(creator);
        _collectionId = collectionId_;
        _registry = msg.sender;
        _baseUriValue = baseUri_;
        _nextTokenId = 1;
    }

    /// Mints the next sequential token to `to` with its metadata URI. The
    /// collection owner is the only minter; the owner at mint time is recorded
    /// as the token's creator, with the block timestamp as its registration
    /// date. `royaltyBps` sets the token's immutable ERC-2981 royalty with the
    /// creator as receiver — never the (mutable) collection owner, so royalties
    /// cannot be redirected by a later ownership transfer. No setter exists.
    function mint(address to, string calldata metadataUri, uint96 royaltyBps)
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        tokenId = _nextTokenId;
        _nextTokenId = tokenId + 1;
        _mintRecord(to, tokenId, metadataUri, royaltyBps);
        emit TokenMinted(tokenId, to, metadataUri, royaltyBps);
    }

    /// Mints one token per recipient/URI/royalty triple. Arrays must align.
    function batchMint(address[] calldata to, string[] calldata metadataUris, uint96[] calldata royaltyBps)
        external
        onlyOwner
        returns (uint256[] memory tokenIds)
    {
        if (to.length == 0) revert MIPEmptyBatch();
        if (to.length != metadataUris.length || to.length != royaltyBps.length) revert MIPLengthMismatch();
        tokenIds = new uint256[](to.length);
        for (uint256 i = 0; i < to.length; i++) {
            uint256 tokenId = _nextTokenId;
            _nextTokenId = tokenId + 1;
            _mintRecord(to[i], tokenId, metadataUris[i], royaltyBps[i]);
            emit TokenMinted(tokenId, to[i], metadataUris[i], royaltyBps[i]);
            tokenIds[i] = tokenId;
        }
        emit TokenMintedBatch(tokenIds, owner());
    }

    /// Permanently freezes a token in its current wallet, preserving the
    /// registration record forever. Replaces destructive burn. Only the token's
    /// owner may archive it — archiving is the holder's right, not the
    /// collection owner's. Archived tokens cannot be transferred or burned.
    function archive(uint256 tokenId) external {
        address tokenOwner = _requireOwned(tokenId);
        if (tokenOwner != msg.sender) revert MIPNotTokenOwner(tokenId);
        if (_archived[tokenId]) revert MIPAlreadyArchived(tokenId);
        _archived[tokenId] = true;
        emit TokenArchived(tokenId);
    }

    function isArchived(uint256 tokenId) external view returns (bool) {
        return _archived[tokenId];
    }

    function collectionId() external view returns (uint256) {
        return _collectionId;
    }

    function registry() external view returns (address) {
        return _registry;
    }

    /// Collection-level metadata pointer. Token URIs are complete URIs set at
    /// mint and are never prefixed with this value.
    function collectionBaseUri() external view returns (string memory) {
        return _baseUriValue;
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function tokenExists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function getTokenCreator(uint256 tokenId) external view returns (address) {
        _requireOwned(tokenId);
        return _tokenCreator[tokenId];
    }

    function getTokenRegisteredAt(uint256 tokenId) external view returns (uint64) {
        _requireOwned(tokenId);
        return _tokenRegisteredAt[tokenId];
    }

    /// Returns the full registration record for a token in a single call:
    /// current owner, metadata URI, original creator, registration timestamp.
    function getFullTokenData(uint256 tokenId)
        external
        view
        returns (address tokenOwner, string memory metadataUri, address originalCreator, uint64 registeredAt)
    {
        tokenOwner = _requireOwned(tokenId);
        metadataUri = tokenURI(tokenId);
        originalCreator = _tokenCreator[tokenId];
        registeredAt = _tokenRegisteredAt[tokenId];
    }

    /// Ownership can move but never be abandoned: a collection with no owner
    /// could never mint again, and the registration records deserve a steward.
    function renounceOwnership() public pure override {
        revert MIPRenounceDisabled();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// Writes one token's immutable registration record and mints it. Uses
    /// _mint, never _safeMint: IP records can be minted to any account or
    /// contract without requiring an ERC-721 receiver callback, and the absence
    /// of that callback keeps minting reentrancy-free.
    function _mintRecord(address to, uint256 tokenId, string calldata metadataUri, uint96 royaltyBps) private {
        if (bytes(metadataUri).length == 0 || bytes(metadataUri).length > MAX_TOKEN_URI_LEN) {
            revert MIPInvalidTokenUri();
        }
        address creator = owner();
        _tokenCreator[tokenId] = creator;
        _tokenRegisteredAt[tokenId] = uint64(block.timestamp);
        _mint(to, tokenId);
        _setTokenURI(tokenId, metadataUri);
        if (royaltyBps > 0) {
            _setTokenRoyalty(tokenId, creator, royaltyBps);
        }
    }

    /// Transfers (and burns) of archived tokens revert; minting is unaffected
    /// because a token cannot be archived before it exists.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        if (_archived[tokenId]) revert MIPTokenArchived(tokenId);
        return super._update(to, tokenId, auth);
    }
}
