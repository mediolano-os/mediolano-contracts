// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// An edition collection: an ERC-1155 owned by its creator. Deployed as a
/// clone by MIPEditionsRegistry; the registry holds no rights after creation.
/// Editions are sequential ids; the first mint of each edition writes an
/// immutable registration record — metadata URI, original creator, timestamp —
/// and the owner can mint further supply of an existing edition. ERC-2981
/// royalties start at zero and are owner-managed (default and per-edition);
/// marketplaces bound any payout to the order's signed royalty cap, so a later
/// change cannot exceed what a seller agreed to at listing time.
contract MIPEditionCollection is
    Initializable,
    ERC1155Upgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable
{
    uint256 private constant MAX_NAME_LEN = 256;
    uint256 private constant MAX_SYMBOL_LEN = 64;
    uint256 private constant MAX_BASE_URI_LEN = 2048;
    uint256 private constant MAX_TOKEN_URI_LEN = 2048;

    string private _name;
    string private _symbol;
    uint256 private _collectionId;
    address private _registry;
    address private _collectionCreator;
    string private _baseUriValue;
    uint256 private _editionCount;
    mapping(uint256 editionId => string) private _editionUri;
    mapping(uint256 editionId => address) private _tokenCreator;
    mapping(uint256 editionId => uint64) private _tokenRegisteredAt;

    event EditionMinted(uint256 indexed editionId, address indexed to, uint256 value, string metadataUri);
    event SupplyAdded(uint256 indexed editionId, address indexed to, uint256 value);

    error MIPInvalidName();
    error MIPInvalidSymbol();
    error MIPInvalidBaseUri();
    error MIPInvalidTokenUri();
    error MIPLengthMismatch();
    error MIPZeroValue();
    error MIPUnknownEdition(uint256 editionId);
    error MIPEditionExists(uint256 editionId);

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
        __ERC1155_init("");
        __ERC2981_init();
        __Ownable_init(creator);
        _name = name_;
        _symbol = symbol_;
        _collectionId = collectionId_;
        _registry = msg.sender;
        _collectionCreator = creator;
        _baseUriValue = baseUri_;
    }

    /// Mints a new edition: the next sequential id with `value` units and its
    /// complete metadata URI. The collection owner is the only minter; the
    /// owner at mint time is recorded as the edition's creator, with the block
    /// timestamp as its registration date.
    function mintEdition(address to, uint256 value, string calldata metadataUri)
        external
        onlyOwner
        returns (uint256 editionId)
    {
        editionId = _mintEdition(to, value, metadataUri);
    }

    /// Mints one new edition per value/URI pair, all to a single recipient.
    /// Arrays must align.
    function batchMintEdition(address to, uint256[] calldata values, string[] calldata metadataUris)
        external
        onlyOwner
        returns (uint256[] memory editionIds)
    {
        if (values.length != metadataUris.length) revert MIPLengthMismatch();
        editionIds = new uint256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            editionIds[i] = _mintEdition(to, values[i], metadataUris[i]);
        }
    }

    /// Mints `value` further units of an existing edition to `to`. The
    /// edition's registration record is untouched.
    function addSupply(address to, uint256 editionId, uint256 value) external onlyOwner {
        if (_tokenCreator[editionId] == address(0)) revert MIPUnknownEdition(editionId);
        if (value == 0) revert MIPZeroValue();
        _mint(to, editionId, value, "");
        emit SupplyAdded(editionId, to, value);
    }

    /// Writes one edition's immutable registration record and mints its
    /// initial supply. A freshly allocated id must never already carry a
    /// record, so provenance can never be overwritten even if id allocation
    /// regresses.
    function _mintEdition(address to, uint256 value, string calldata metadataUri)
        private
        returns (uint256 editionId)
    {
        if (value == 0) revert MIPZeroValue();
        if (bytes(metadataUri).length == 0 || bytes(metadataUri).length > MAX_TOKEN_URI_LEN) {
            revert MIPInvalidTokenUri();
        }
        editionId = ++_editionCount;
        if (_tokenCreator[editionId] != address(0)) revert MIPEditionExists(editionId);
        _editionUri[editionId] = metadataUri;
        _tokenCreator[editionId] = owner();
        _tokenRegisteredAt[editionId] = uint64(block.timestamp);
        _mint(to, editionId, value, "");
        emit EditionMinted(editionId, to, value, metadataUri);
    }

    /// Per-edition URI if one has been minted, otherwise the collection-level
    /// base URI — supporting content-addressed per-edition URIs for IP
    /// provenance with a collection fallback.
    function uri(uint256 editionId) public view override returns (string memory) {
        string memory editionUri = _editionUri[editionId];
        if (bytes(editionUri).length > 0) {
            return editionUri;
        }
        return _baseUriValue;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function collectionId() external view returns (uint256) {
        return _collectionId;
    }

    function registry() external view returns (address) {
        return _registry;
    }

    /// The address that created this collection. Immutable — does not change
    /// if ownership is transferred.
    function collectionCreator() external view returns (address) {
        return _collectionCreator;
    }

    /// Collection-level metadata pointer, also the uri() fallback.
    function collectionBaseUri() external view returns (string memory) {
        return _baseUriValue;
    }

    function totalEditions() external view returns (uint256) {
        return _editionCount;
    }

    function tokenExists(uint256 editionId) external view returns (bool) {
        return _tokenCreator[editionId] != address(0);
    }

    function getTokenCreator(uint256 editionId) external view returns (address) {
        address tokenCreator = _tokenCreator[editionId];
        if (tokenCreator == address(0)) revert MIPUnknownEdition(editionId);
        return tokenCreator;
    }

    function getTokenRegisteredAt(uint256 editionId) external view returns (uint64) {
        if (_tokenCreator[editionId] == address(0)) revert MIPUnknownEdition(editionId);
        return _tokenRegisteredAt[editionId];
    }

    /// Returns the full registration record for an edition in a single call:
    /// metadata URI, original creator, registration timestamp.
    function getTokenData(uint256 editionId)
        external
        view
        returns (string memory metadataUri, address originalCreator, uint64 registeredAt)
    {
        originalCreator = _tokenCreator[editionId];
        if (originalCreator == address(0)) revert MIPUnknownEdition(editionId);
        metadataUri = _editionUri[editionId];
        registeredAt = _tokenRegisteredAt[editionId];
    }

    /// Royalty administration, owner-gated: a collection-wide default and
    /// per-edition overrides. Starts at zero.
    function setDefaultRoyalty(address receiver, uint96 royaltyBps) external onlyOwner {
        _setDefaultRoyalty(receiver, royaltyBps);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(uint256 editionId, address receiver, uint96 royaltyBps) external onlyOwner {
        _setTokenRoyalty(editionId, receiver, royaltyBps);
    }

    function resetTokenRoyalty(uint256 editionId) external onlyOwner {
        _resetTokenRoyalty(editionId);
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
