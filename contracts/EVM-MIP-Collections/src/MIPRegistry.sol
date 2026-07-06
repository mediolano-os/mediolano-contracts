// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MIPCollection} from "./MIPCollection.sol";

/// Permissionless registry of IP collections. Anyone can create a collection;
/// the caller becomes its owner. The registry itself has no owner, takes no
/// fees, and holds no rights over created collections. A protocol upgrade is a
/// fresh registry + implementation deployment.
contract MIPRegistry {
    struct CollectionRecord {
        address collection;
        address creator;
    }

    address private immutable _collectionImplementation;
    uint256 private _collectionCount;
    mapping(uint256 collectionId => CollectionRecord) private _collections;

    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed collection,
        address indexed creator,
        string name,
        string symbol,
        string baseUri
    );

    error MIPZeroImplementation();

    constructor(address implementation_) {
        if (implementation_ == address(0)) revert MIPZeroImplementation();
        _collectionImplementation = implementation_;
    }

    /// Deploys a new collection owned by the caller. `royaltyBps` sets the
    /// collection's ERC-2981 default royalty with the caller as receiver
    /// (0 = no royalty).
    function createCollection(
        string calldata name_,
        string calldata symbol_,
        string calldata baseUri_,
        uint96 royaltyBps
    ) external returns (uint256 collectionId, address collection) {
        collectionId = ++_collectionCount;
        collection = Clones.clone(_collectionImplementation);
        MIPCollection(collection).initialize(collectionId, msg.sender, name_, symbol_, baseUri_, royaltyBps);
        _collections[collectionId] = CollectionRecord({collection: collection, creator: msg.sender});
        emit CollectionCreated(collectionId, collection, msg.sender, name_, symbol_, baseUri_);
    }

    function getCollection(uint256 collectionId) external view returns (address collection, address creator) {
        CollectionRecord storage record = _collections[collectionId];
        return (record.collection, record.creator);
    }

    function collectionCount() external view returns (uint256) {
        return _collectionCount;
    }

    function isValidCollection(uint256 collectionId) external view returns (bool) {
        return _collections[collectionId].collection != address(0);
    }

    function collectionImplementation() external view returns (address) {
        return _collectionImplementation;
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
