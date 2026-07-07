// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// An edition collection: an ERC-1155 owned by its creator. Deployed as a
/// clone by MIPEditionsRegistry; the registry holds no rights after creation.
/// Editions are sequential ids carrying a complete per-edition metadata URI
/// and an initial supply; the owner can mint further supply of an existing
/// edition. ERC-2981 default royalty.
contract MIPEditionCollection is
    Initializable,
    ERC1155Upgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable
{
    string private _name;
    string private _symbol;
    uint256 private _collectionId;
    address private _registry;
    string private _baseUriValue;
    uint256 private _editionCount;
    mapping(uint256 editionId => string) private _editionUri;
    mapping(uint256 editionId => address) private _tokenCreator;

    event EditionMinted(uint256 indexed editionId, address indexed to, uint256 value, string metadataUri);
    event SupplyAdded(uint256 indexed editionId, address indexed to, uint256 value);

    error MIPLengthMismatch();
    error MIPZeroValue();
    error MIPUnknownEdition(uint256 editionId);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 collectionId_,
        address creator,
        string calldata name_,
        string calldata symbol_,
        string calldata baseUri_,
        uint96 royaltyBps
    ) external initializer {
        __ERC1155_init("");
        __ERC2981_init();
        __Ownable_init(creator);
        _name = name_;
        _symbol = symbol_;
        _collectionId = collectionId_;
        _registry = msg.sender;
        _baseUriValue = baseUri_;
        if (royaltyBps > 0) {
            _setDefaultRoyalty(creator, royaltyBps);
        }
    }

    /// Mints a new edition: the next sequential id with `value` units and its
    /// complete metadata URI. The collection owner is the only minter; the
    /// owner at mint time is recorded as the edition's creator.
    function mintEdition(address to, uint256 value, string calldata metadataUri)
        external
        onlyOwner
        returns (uint256 editionId)
    {
        editionId = _mintEdition(to, value, metadataUri);
    }

    /// Mints one new edition per recipient/value/URI triple. Arrays must align.
    function batchMintEdition(
        address[] calldata to,
        uint256[] calldata values,
        string[] calldata metadataUris
    ) external onlyOwner returns (uint256[] memory editionIds) {
        if (to.length != values.length || to.length != metadataUris.length) revert MIPLengthMismatch();
        editionIds = new uint256[](to.length);
        for (uint256 i = 0; i < to.length; i++) {
            editionIds[i] = _mintEdition(to[i], values[i], metadataUris[i]);
        }
    }

    /// Mints `value` further units of an existing edition to `to`.
    function addSupply(address to, uint256 editionId, uint256 value) external onlyOwner {
        if (editionId == 0 || editionId > _editionCount) revert MIPUnknownEdition(editionId);
        if (value == 0) revert MIPZeroValue();
        _mint(to, editionId, value, "");
        emit SupplyAdded(editionId, to, value);
    }

    function _mintEdition(address to, uint256 value, string calldata metadataUri)
        private
        returns (uint256 editionId)
    {
        if (value == 0) revert MIPZeroValue();
        editionId = ++_editionCount;
        _editionUri[editionId] = metadataUri;
        _tokenCreator[editionId] = owner();
        _mint(to, editionId, value, "");
        emit EditionMinted(editionId, to, value, metadataUri);
    }

    /// Complete per-edition URI set at mint; never prefixed.
    function uri(uint256 editionId) public view override returns (string memory) {
        return _editionUri[editionId];
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

    /// Collection-level metadata pointer; edition URIs are complete URIs.
    function collectionBaseUri() external view returns (string memory) {
        return _baseUriValue;
    }

    function totalEditions() external view returns (uint256) {
        return _editionCount;
    }

    function tokenExists(uint256 editionId) external view returns (bool) {
        return editionId != 0 && editionId <= _editionCount;
    }

    function getTokenCreator(uint256 editionId) external view returns (address) {
        return _tokenCreator[editionId];
    }

    function setDefaultRoyalty(address receiver, uint96 royaltyBps) external onlyOwner {
        _setDefaultRoyalty(receiver, royaltyBps);
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
