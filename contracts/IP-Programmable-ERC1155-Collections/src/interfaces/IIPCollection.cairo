use starknet::ContractAddress;
use crate::types::TokenData;

/// Public interface for an IPCollection ERC-1155 contract.
///
/// Each collection is a standalone ERC-1155 contract deployed by the factory.
/// The collection owner controls minting. Any holder can transfer their tokens.
/// IP provenance (original creator + registration timestamp) is recorded immutably
/// at first mint of each token type, satisfying the Berne Convention authorship standard.
#[starknet::interface]
pub trait IIPCollection<TContractState> {
    // ── Collection metadata ────────────────────────────────────────────────────

    /// Human-readable collection name set at deploy time.
    fn name(self: @TContractState) -> ByteArray;

    /// Collection ticker symbol set at deploy time.
    fn symbol(self: @TContractState) -> ByteArray;

    /// Collection-level metadata URI (e.g. ipfs://Qm…/collection.json).
    /// Points to the JSON that contains the collection image, description, and external link.
    /// Also used as fallback `uri(token_id)` response for unminted token types.
    fn base_uri(self: @TContractState) -> ByteArray;

    /// Returns the immutable implementation version for this deployed collection class.
    fn version(self: @TContractState) -> ByteArray;

    // ── Minting ────────────────────────────────────────────────────────────────

    /// Mints a NEW edition with an id assigned atomically on-chain (sequential from 1).
    /// Owner only. `to` must not be zero; `value` must be > 0; `token_uri` must be valid length.
    /// Records the caller as the immutable IP creator + registration timestamp.
    /// Returns the assigned token id.
    fn mint_edition(
        ref self: TContractState,
        to: ContractAddress,
        value: u256,
        token_uri: ByteArray,
    ) -> u256;

    /// Mints `value` additional copies of an EXISTING edition to `to`.
    /// Owner only. Reverts if `token_id` has never been minted. URI/provenance unchanged.
    fn add_supply(ref self: TContractState, to: ContractAddress, token_id: u256, value: u256);

    // ── Provenance queries ─────────────────────────────────────────────────────

    /// Returns the address that deployed this collection via the factory.
    /// Immutable — does not change if ownership is transferred.
    fn get_collection_creator(self: @TContractState) -> ContractAddress;

    /// Returns the address that first minted this token type (the IP creator/author).
    /// Immutable Berne Convention authorship record.
    /// Reverts if the token type has never been minted.
    fn get_token_creator(self: @TContractState, token_id: u256) -> ContractAddress;

    /// Returns the block timestamp recorded at first mint of this token type.
    /// Reverts if the token type has never been minted.
    fn get_token_registered_at(self: @TContractState, token_id: u256) -> u64;

    /// Returns all provenance fields for a token type in a single call.
    /// Reverts if the token type has never been minted.
    fn get_token_data(self: @TContractState, token_id: u256) -> TokenData;

    /// Number of distinct editions minted so far (sequential ids 1..=total_editions).
    fn total_editions(self: @TContractState) -> u256;

    /// True if `token_id` has been minted (an edition exists).
    fn token_exists(self: @TContractState, token_id: u256) -> bool;
}
