use starknet::ContractAddress;
use crate::types::{CollectionConfig, Contribution, ContributionType, TokenData};

/// SRC5 interface ID for collaborative IP collection behavior.
pub const IIP_COLLABORATIVE_COLLECTION_ID: felt252 =
    0x037f7abfe8ddddc21679794c218b559402e56bf1e6e6e2409c389038cd63f7cd;

#[starknet::interface]
pub trait IIPCollaborativeCollection<TContractState> {
    fn register_contribution_type(
        ref self: TContractState,
        type_id: felt252,
        min_quality_score: u8,
        submission_deadline: u64,
        max_supply: u256,
    );

    fn submit_contribution(
        ref self: TContractState, token_uri: ByteArray, contribution_type: felt252,
    ) -> u256;

    fn approve_contribution(ref self: TContractState, contribution_id: u256, quality_score: u8);

    fn reject_contribution(ref self: TContractState, contribution_id: u256, quality_score: u8);

    fn mint_contribution(ref self: TContractState, contribution_id: u256) -> u256;

    fn archive_contribution_token(ref self: TContractState, token_id: u256);

    fn add_verifier(ref self: TContractState, verifier: ContractAddress);

    fn remove_verifier(ref self: TContractState, verifier: ContractAddress);

    fn is_verifier(self: @TContractState, verifier: ContractAddress) -> bool;

    fn get_collection_issuer(self: @TContractState) -> ContractAddress;

    fn get_ip_nft(self: @TContractState) -> ContractAddress;

    fn get_uri_policy(self: @TContractState) -> felt252;

    fn get_collection_config(self: @TContractState) -> CollectionConfig;

    fn get_contribution(self: @TContractState, contribution_id: u256) -> Contribution;

    fn get_contribution_type(self: @TContractState, type_id: felt252) -> ContributionType;

    fn get_contributions_count(self: @TContractState) -> u256;

    fn get_contributor_contributions(
        self: @TContractState, contributor: ContractAddress,
    ) -> Array<u256>;

    fn get_token_contribution(self: @TContractState, token_id: u256) -> u256;

    fn get_token_contributor(self: @TContractState, token_id: u256) -> ContractAddress;

    fn get_token_registered_at(self: @TContractState, token_id: u256) -> u64;

    fn get_token_data(self: @TContractState, token_id: u256) -> TokenData;
}
