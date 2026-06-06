use starknet::ContractAddress;
use crate::types::TimeCapsuleData;

/// SRC5 interface ID for the IP Time Capsule helper ABI.
///
/// Computed as the XOR of selectors:
/// - mint_capsule
/// - reveal_capsule
/// - get_capsule_data
/// - get_encrypted_uri
/// - get_revealed_uri
/// - get_token_creator
/// - get_token_reveal_at
/// - is_unlocked
/// - is_revealed
/// - get_hidden_uri
/// - get_max_lock_duration
/// - compute_content_commitment
/// - get_commitment_scheme
pub const IIP_TIME_CAPSULE_ID: felt252 =
    0x03874654ec5283a05a5b634b5fd6ce5c4acdc942c788acaa5982991a3f7663d1;

#[starknet::interface]
pub trait ITimeCapsule<TContractState> {
    fn mint_capsule(
        ref self: TContractState,
        recipient: ContractAddress,
        encrypted_uri: ByteArray,
        content_commitment: felt252,
        reveal_at: u64,
    ) -> u256;

    fn reveal_capsule(
        ref self: TContractState,
        token_id: u256,
        revealed_uri: ByteArray,
        content_hash: felt252,
        content_salt: felt252,
    );

    fn get_capsule_data(self: @TContractState, token_id: u256) -> TimeCapsuleData;

    fn get_encrypted_uri(self: @TContractState, token_id: u256) -> ByteArray;

    fn get_revealed_uri(self: @TContractState, token_id: u256) -> ByteArray;

    fn get_token_creator(self: @TContractState, token_id: u256) -> ContractAddress;

    fn get_token_reveal_at(self: @TContractState, token_id: u256) -> u64;

    fn is_unlocked(self: @TContractState, token_id: u256) -> bool;

    fn is_revealed(self: @TContractState, token_id: u256) -> bool;

    fn get_hidden_uri(self: @TContractState) -> ByteArray;

    fn get_max_lock_duration(self: @TContractState) -> u64;

    fn compute_content_commitment(
        self: @TContractState, content_hash: felt252, content_salt: felt252,
    ) -> felt252;

    fn get_commitment_scheme(self: @TContractState) -> felt252;
}
