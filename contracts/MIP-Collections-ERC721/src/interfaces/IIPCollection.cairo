/// Interface for IP Collection contract, defining core collection and token management operations.
use starknet::ContractAddress;
use crate::types::{Collection, CollectionStats, TokenData};

#[starknet::interface]
pub trait IIPCollection<ContractState> {
    /// Creates a new collection with the given `name`, `symbol`, and `base_uri`.
    /// Deploys a new IPNft ERC-721 contract for the collection.
    /// The caller becomes the collection owner.
    ///
    /// # Arguments
    /// * `name` - The name of the collection (must be non-empty).
    /// * `symbol` - The symbol of the collection (must be non-empty).
    /// * `base_uri` - The base URI for the collection's metadata.
    ///
    /// # Returns
    /// The unique identifier (`u256`) of the created collection.
    fn create_collection(
        ref self: ContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> u256;

    /// Mints a new token in the specified `collection_id` and assigns it to the `recipient`.
    /// Only the collection owner can mint.
    /// Token IDs start at 1. The `token_uri` is stored permanently and must not be empty.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection to mint in.
    /// * `recipient` - The address to receive the newly minted token.
    /// * `token_uri` - The immutable metadata URI/string for the token.
    ///
    /// # Returns
    /// The unique identifier (`u256`) of the minted token.
    fn mint(
        ref self: ContractState,
        collection_id: u256,
        recipient: ContractAddress,
        token_uri: ByteArray,
    ) -> u256;

    /// Mints tokens in batch for the specified `collection_id`.
    /// `recipients` and `token_uris` must be the same length.
    /// Only the collection owner can batch mint.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection to mint in.
    /// * `recipients` - Array of addresses to receive the newly minted tokens.
    /// * `token_uris` - Array of immutable metadata URI strings for each token.
    ///
    /// # Returns
    /// A Span of token IDs (`u256`) for the minted tokens.
    fn batch_mint(
        ref self: ContractState,
        collection_id: u256,
        recipients: Array<ContractAddress>,
        token_uris: Array<ByteArray>,
    ) -> Span<u256>;

    /// Transfers collection ownership atomically.
    /// This changes future mint authority only. Existing token legal records are untouched.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection to transfer.
    /// * `new_owner` - The address that will become the collection owner.
    fn transfer_collection_ownership(
        ref self: ContractState, collection_id: u256, new_owner: ContractAddress,
    );

    /// Archives a token, preserving the on-chain provenance record permanently.
    /// Archived tokens cannot be transferred or re-archived.
    /// Only the token owner can archive their token.
    /// This replaces destructive burning to comply with Berne Convention requirements —
    /// the legal record of IP creation is never deleted.
    ///
    /// # Arguments
    /// * `token` - The identifier of the token to archive (format: "collection_id:token_id").
    fn archive(ref self: ContractState, token: ByteArray);

    /// Archives multiple tokens in batch.
    /// Caller must own all tokens in the batch.
    ///
    /// # Arguments
    /// * `tokens` - Array of token identifiers to archive.
    fn batch_archive(ref self: ContractState, tokens: Array<ByteArray>);

    /// Transfers a `token` from `from` address to `to` address.
    /// The IPCollection contract must be approved for the token.
    /// The caller must be the token owner or an approved operator.
    ///
    /// # Arguments
    /// * `from` - Current owner of the token.
    /// * `to` - Recipient of the token.
    /// * `token` - Identifier of the token to transfer.
    fn transfer_token(
        ref self: ContractState, from: ContractAddress, to: ContractAddress, token: ByteArray,
    );

    /// Transfers multiple `tokens` from `from` address to `to` address in batch.
    /// The IPCollection contract must be approved for each token.
    /// The caller must be the token owner or an approved operator.
    ///
    /// # Arguments
    /// * `from` - Current owner of the tokens.
    /// * `to` - Recipient of the tokens.
    /// * `tokens` - Array of token identifiers to transfer.
    fn batch_transfer(
        ref self: ContractState,
        from: ContractAddress,
        to: ContractAddress,
        tokens: Array<ByteArray>,
    );

    /// Lists all token IDs owned by `user` in a specific `collection_id`.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection.
    /// * `user` - The address whose tokens are to be listed.
    ///
    /// # Returns
    /// A Span of token IDs (`u256`).
    fn list_user_tokens_per_collection(
        self: @ContractState, collection_id: u256, user: ContractAddress,
    ) -> Span<u256>;

    /// Lists all collection IDs owned by `user`.
    ///
    /// # Arguments
    /// * `user` - The address whose collections are to be listed.
    ///
    /// # Returns
    /// A Span of collection IDs (`u256`).
    fn list_user_collections(self: @ContractState, user: ContractAddress) -> Span<u256>;

    /// Retrieves the metadata of a collection by its `collection_id`.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection.
    ///
    /// # Returns
    /// A `Collection` struct.
    fn get_collection(self: @ContractState, collection_id: u256) -> Collection;

    /// Returns the total number of collections ever created.
    ///
    /// # Returns
    /// * `u256` - Total collection count.
    fn get_collection_count(self: @ContractState) -> u256;

    /// Checks if a `collection_id` exists.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection.
    ///
    /// # Returns
    /// `true` if valid, `false` otherwise.
    fn is_valid_collection(self: @ContractState, collection_id: u256) -> bool;

    /// Retrieves statistics for a collection by its `collection_id`.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection.
    ///
    /// # Returns
    /// A `CollectionStats` struct.
    fn get_collection_stats(self: @ContractState, collection_id: u256) -> CollectionStats;

    /// Checks if the given `owner` address is the owner of the specified `collection_id`.
    ///
    /// # Arguments
    /// * `collection_id` - The identifier of the collection.
    /// * `owner` - The address to check for ownership.
    ///
    /// # Returns
    /// `true` if the address is the owner, `false` otherwise.
    fn is_collection_owner(
        self: @ContractState, collection_id: u256, owner: ContractAddress,
    ) -> bool;

    /// Retrieves the full token data including immutable legal record fields.
    /// Reverts if the collection is invalid or the token does not exist.
    ///
    /// # Arguments
    /// * `token` - The identifier of the token (format: "collection_id:token_id").
    ///
    /// # Returns
    /// A `TokenData` struct including `original_creator` and `registered_at`.
    fn get_token(self: @ContractState, token: ByteArray) -> TokenData;

    /// Checks if a `token` identifier is valid (exists in a valid collection).
    ///
    /// # Arguments
    /// * `token` - The identifier of the token.
    ///
    /// # Returns
    /// `true` if valid, `false` otherwise.
    fn is_valid_token(self: @ContractState, token: ByteArray) -> bool;

    /// Checks if a `token` identifier exists and is not archived.
    /// Use this for trade/transfer eligibility checks.
    ///
    /// # Arguments
    /// * `token` - The identifier of the token.
    ///
    /// # Returns
    /// `true` if the token exists and has not been archived, `false` otherwise.
    fn is_transferable_token(self: @ContractState, token: ByteArray) -> bool;

}
