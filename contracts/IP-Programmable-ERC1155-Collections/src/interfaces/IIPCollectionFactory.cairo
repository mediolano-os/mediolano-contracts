use starknet::{ClassHash, ContractAddress};

/// Public interface for the IPCollectionFactory contract.
///
/// The factory is the single deployment point for all IP ERC-1155 collections.
/// Anyone can deploy a new collection — the caller becomes its owner.
/// The factory is fully immutable and ownerless: the collection class hash is fixed
/// at deploy time. Protocol evolution = deploy a new factory, never mutate this one.
#[starknet::interface]
pub trait IIPCollectionFactory<TContractState> {
    /// Returns the class hash used to deploy new collections (immutable).
    fn collection_class_hash(self: @TContractState) -> ClassHash;

    /// Returns the immutable implementation version for this deployed factory class.
    fn version(self: @TContractState) -> ByteArray;

    /// Deploys a new IPCollection instance.
    ///
    /// Callable by anyone — the caller becomes the collection owner and IP creator.
    /// `name` and `symbol` must be non-empty.
    /// `base_uri` should point to the collection-level metadata JSON on IPFS (e.g.
    /// `ipfs://Qm…/collection.json`). May be empty if no collection metadata is available.
    /// Returns the address of the newly deployed collection.
    /// Emits `CollectionDeployed`.
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> ContractAddress;
}
