use starknet::ContractAddress;
use crate::types::{License, SponsorshipOffer};

// Protocol discovery ID registered via SRC5.
// Derivation: starknet_keccak("mediolano.ip-sponsorship.v2").
pub const IIP_SPONSORSHIP_ID: felt252 =
    0x0034e46e7acd46043d30df2ef53d27bbb6b7636b61c4e27e989e3bee5575bba5;

#[starknet::interface]
pub trait IIPSponsorship<TContractState> {
    fn create_offer(
        ref self: TContractState,
        nft_contract: ContractAddress,
        token_id: u256,
        min_amount: u256,
        duration: u64,
        payment_token: ContractAddress,
        license_terms_uri: ByteArray,
        transferable: bool,
        specific_sponsor: Option<ContractAddress>,
    ) -> u256;
    fn set_offer_open(ref self: TContractState, offer_id: u256, open: bool);
    fn place_bid(ref self: TContractState, offer_id: u256, amount: u256);
    fn retract_bid(ref self: TContractState, offer_id: u256);
    fn accept_bid(ref self: TContractState, offer_id: u256, sponsor: ContractAddress) -> u256;
    fn transfer_license(ref self: TContractState, license_id: u256, to: ContractAddress);
    fn get_offer(self: @TContractState, offer_id: u256) -> SponsorshipOffer;
    fn get_bid(self: @TContractState, offer_id: u256, sponsor: ContractAddress) -> u256;
    fn get_license(self: @TContractState, license_id: u256) -> License;
    fn is_license_valid(self: @TContractState, license_id: u256) -> bool;
    fn get_last_offer_id(self: @TContractState) -> u256;
    fn get_last_license_id(self: @TContractState) -> u256;
}
