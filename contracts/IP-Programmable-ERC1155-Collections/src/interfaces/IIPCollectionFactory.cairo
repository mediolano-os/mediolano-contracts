use starknet::{ClassHash, ContractAddress};

/// Public interface for the IPCollectionFactory contract.
///
/// The factory is the single deployment point for all IP ERC-1155 collections.
/// Anyone can deploy a new collection — the caller becomes its owner.
/// The factory owner can update the class hash used for future deployments
/// (e.g. after a protocol upgrade), without affecting existing collections.
#[starknet::interface]
pub trait IIPCollectionFactory<TContractState> {
    /// Returns the class hash used to deploy new collections.
    fn collection_class_hash(self: @TContractState) -> ClassHash;

    /// Returns the immutable implementation version for this deployed factory class.
    fn version(self: @TContractState) -> ByteArray;

    /// Updates the class hash for future collection deployments.
    /// Factory owner only. Does not affect already-deployed collections.
    /// Emits `CollectionClassHashUpdated`.
    fn update_collection_class_hash(ref self: TContractState, new_class_hash: ClassHash);

    /// Deploys a new IPCollection instance.
    ///
    /// Callable by anyone — the caller becomes the collection owner and IP creator.
    /// `name` and `symbol` must be non-empty.
    /// `base_uri` should point to the collection-level metadata JSON on IPFS (e.g.
    /// `ipfs://Qm…/collection.json`). May be empty if no collection metadata is available.
    /// Returns the address of the newly deployed collection.
    /// Emits `CollectionDeployed`.
    fn deploy_collection(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
    ) -> ContractAddress;
}
