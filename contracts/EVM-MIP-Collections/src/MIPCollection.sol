// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// An IP collection: an ERC-721 owned by its creator. Deployed as a clone by
/// MIPRegistry; the registry holds no rights over the collection after creation.
/// Tokens carry per-token metadata URIs and an ERC-2981 default royalty.
contract MIPCollection is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable
{
    uint256 private _collectionId;
    address private _registry;
    string private _baseUriValue;
    uint256 private _nextTokenId;
    mapping(uint256 tokenId => address) private _tokenCreator;

    event TokenMinted(uint256 indexed tokenId, address indexed owner, string metadataUri);

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
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __ERC2981_init();
        __Ownable_init(creator);
        _collectionId = collectionId_;
        _registry = msg.sender;
        _baseUriValue = baseUri_;
        _nextTokenId = 1;
        if (royaltyBps > 0) {
            _setDefaultRoyalty(creator, royaltyBps);
        }
    }

    /// Mints the next sequential token to `to` with its metadata URI. The
    /// collection owner is the only minter; the owner at mint time is recorded
    /// as the token's creator.
    function mint(address to, string calldata metadataUri) external onlyOwner returns (uint256 tokenId) {
        tokenId = _nextTokenId;
        _nextTokenId = tokenId + 1;
        _tokenCreator[tokenId] = owner();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataUri);
        emit TokenMinted(tokenId, to, metadataUri);
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
        return _tokenCreator[tokenId];
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
}
