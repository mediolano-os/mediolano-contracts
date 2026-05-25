use starknet::ContractAddress;
use crate::types::TokenData;

/// SRC5 interface ID for the programmable IP collection surface.
///
/// Computed as the XOR of selectors:
/// - mint_item
/// - get_collection_creator
/// - get_token_creator
/// - get_token_registered_at
/// - get_token_data
pub const IIP_COLLECTION_ID: felt252 =
    0x0202300b3ad00076154db28f5234f2f40b48ea4f76160fd2df86e70577c93be3;

/// Public interface for the IPCollection contract.
///
/// IPCollection is a standalone, immutable, permissionless ERC-721 provenance contract.
/// Any user can deploy their own collection instance and any user can mint into it.
/// No address holds any privileged power after deployment — the contract is fully
/// trust-minimized. Each token carries a permanent IP provenance record: creator
/// address and registration timestamp, stored immutably at mint time.
#[starknet::interface]
pub trait IIPCollection<TContractState> {
    /// Mints a new ERC-721 token to `recipient` with the given `token_uri`.
    ///
    /// Callable by anyone — no access control on mint.
    /// `token_uri` must start with `ipfs://` or `ar://`.
    /// `recipient` must not be the zero address.
    /// Reverts if `recipient` is a contract that does not implement IERC721Receiver.
    ///
    /// Returns the newly minted token ID (starts at 1, increments by 1).
    fn mint_item(
        ref self: TContractState, recipient: ContractAddress, token_uri: ByteArray,
    ) -> u256;

    /// Returns the informational collection creator recorded at deployment.
    /// Informational only — this address holds no special power over the contract.
    fn get_collection_creator(self: @TContractState) -> ContractAddress;

    /// Returns the original creator (caller at mint time) for a token.
    /// This is the immutable Berne Convention authorship record.
    /// Reverts if the token does not exist.
    fn get_token_creator(self: @TContractState, token_id: u256) -> ContractAddress;

    /// Returns the block timestamp stored immutably at mint time.
    /// Reverts if the token does not exist.
    fn get_token_registered_at(self: @TContractState, token_id: u256) -> u64;

    /// Returns all provenance fields for a token in a single call.
    /// Avoids multiple separate cross-contract calls.
    /// Reverts if the token does not exist.
    fn get_token_data(self: @TContractState, token_id: u256) -> TokenData;
}
