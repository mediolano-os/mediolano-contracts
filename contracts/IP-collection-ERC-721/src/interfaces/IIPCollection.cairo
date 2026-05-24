use starknet::ContractAddress;
use crate::types::TokenData;

/// SRC5 interface ID for the owner-minted IP collection surface.
///
/// Computed as the XOR of selectors:
/// - mint_item
/// - get_collection_issuer
/// - get_token_issuer
/// - get_token_registered_at
/// - get_token_data
pub const IIP_COLLECTION_ID: felt252 =
    0x0169025717e7d54a71b5dcbf608cd0a71b562570902dad8b7d4a7e80fe15eeb0;

#[starknet::interface]
pub trait IIPCollection<TContractState> {
    /// Owner-only mint for canonical IP collection issuance.
    fn mint_item(
        ref self: TContractState, recipient: ContractAddress, token_uri: ByteArray,
    ) -> u256;

    /// Initial collection issuer recorded at deployment.
    fn get_collection_issuer(self: @TContractState) -> ContractAddress;

    /// Collection authority that minted the token.
    fn get_token_issuer(self: @TContractState, token_id: u256) -> ContractAddress;

    /// Block timestamp stored immutably at mint time.
    fn get_token_registered_at(self: @TContractState, token_id: u256) -> u64;

    /// Returns all token provenance fields in one call.
    fn get_token_data(self: @TContractState, token_id: u256) -> TokenData;
}
