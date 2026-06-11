use starknet::ContractAddress;
use crate::types::TimeCapsuleData;

/// Protocol discovery ID registered via SRC5.
/// Derivation: starknet_keccak("mediolano.ip-time-capsule.v2").
pub const IIP_TIME_CAPSULE_ID: felt252 =
    0x035accb37e9eaf4dc53e1afab6bb09430fb0e4b53b2f8fc0abc76174ce7121a9;

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
