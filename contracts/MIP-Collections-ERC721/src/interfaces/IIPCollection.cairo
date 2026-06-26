/// Interface for IP Collection contract, defining core collection and token management operations.
use starknet::ContractAddress;
use crate::types::{Collection, CollectionStats, TokenData};

#[starknet::interface]
pub trait IIPCollection<ContractState> {
    /// Creates a new collection with the given `name`, `symbol`, and `base_uri`.
    /// Deploys a new IPNft ERC-721 contract for the collection. The caller becomes the owner.
    /// Returns the new collection's `u256` id.
    fn create_collection(
        ref self: ContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> u256;

    /// Mints a new token in `collection_id` to `recipient`. Only the collection owner can mint.
    /// Token IDs start at 1. `token_uri` is stored permanently and must not be empty.
    /// `royalty_bps` sets the token's immutable EIP-2981 royalty (≤ 10_000), receiver = creator.
    /// Returns the minted token's `u256` id.
    fn mint(
        ref self: ContractState,
        collection_id: u256,
        recipient: ContractAddress,
        token_uri: ByteArray,
        royalty_bps: u128,
    ) -> u256;

    /// Batch mints tokens in `collection_id`. `recipients`, `token_uris`, and `royalty_bps`
    /// must be the same length (per-token royalty). Only the collection owner can batch mint.
    /// Returns a Span of the minted token IDs.
    fn batch_mint(
        ref self: ContractState,
        collection_id: u256,
        recipients: Array<ContractAddress>,
        token_uris: Array<ByteArray>,
        royalty_bps: Array<u128>,
    ) -> Span<u256>;

    /// Transfers collection ownership atomically (future mint authority only; existing token
    /// legal records are untouched).
    fn transfer_collection_ownership(
        ref self: ContractState, collection_id: u256, new_owner: ContractAddress,
    );

    /// Archives a token, preserving the on-chain provenance record permanently.
    /// Archived tokens cannot be transferred or re-archived. Only the token owner can archive.
    /// Replaces destructive burning — the legal record of IP creation is never deleted.
    fn archive(ref self: ContractState, collection_id: u256, token_id: u256);

    /// Archives multiple tokens (parallel `collection_ids` / `token_ids`, equal length).
    /// Caller must own every token in the batch.
    fn batch_archive(ref self: ContractState, collection_ids: Array<u256>, token_ids: Array<u256>);

    /// Transfers a token to `to`. The IPCollection contract must be approved for the token,
    /// and the caller must be the token owner or an approved operator. (`from` is derived
    /// from on-chain ownership.)
    fn transfer_token(
        ref self: ContractState, to: ContractAddress, collection_id: u256, token_id: u256,
    );

    /// Batch transfers tokens (parallel `collection_ids` / `token_ids`, equal length) to `to`.
    /// The sender is derived from on-chain ownership of the first token; the contract must be
    /// approved and the caller authorized for each token (a batch must share one owner).
    fn batch_transfer(
        ref self: ContractState,
        to: ContractAddress,
        collection_ids: Array<u256>,
        token_ids: Array<u256>,
    );

    /// Lists all token IDs owned by `user` in a specific `collection_id`.
    fn list_user_tokens_per_collection(
        self: @ContractState, collection_id: u256, user: ContractAddress,
    ) -> Span<u256>;

    /// Lists all collection IDs owned by `user`.
    fn list_user_collections(self: @ContractState, user: ContractAddress) -> Span<u256>;

    /// Retrieves the metadata of a collection by its `collection_id`.
    fn get_collection(self: @ContractState, collection_id: u256) -> Collection;

    /// Returns the total number of collections ever created.
    fn get_collection_count(self: @ContractState) -> u256;

    /// Returns the immutable implementation version for this deployed registry class.
    fn version(self: @ContractState) -> ByteArray;

    /// Checks if a `collection_id` exists.
    fn is_valid_collection(self: @ContractState, collection_id: u256) -> bool;

    /// Retrieves statistics for a collection by its `collection_id`.
    fn get_collection_stats(self: @ContractState, collection_id: u256) -> CollectionStats;

    /// Checks if `owner` owns the specified `collection_id`.
    fn is_collection_owner(
        self: @ContractState, collection_id: u256, owner: ContractAddress,
    ) -> bool;

    /// Retrieves the full token data including immutable legal record fields.
    /// Reverts if the collection is invalid or the token does not exist.
    fn get_token(self: @ContractState, collection_id: u256, token_id: u256) -> TokenData;

    /// Checks if a token is valid (exists in a valid collection).
    fn is_valid_token(self: @ContractState, collection_id: u256, token_id: u256) -> bool;

    /// Checks if a token exists and is not archived. Use for trade/transfer eligibility.
    fn is_transferable_token(self: @ContractState, collection_id: u256, token_id: u256) -> bool;
}
