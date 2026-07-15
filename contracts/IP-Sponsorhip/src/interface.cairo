use starknet::ContractAddress;
use crate::types::{LicenseData, SponsorshipOffer, SponsorshipProposal};

// Protocol discovery ID registered via SRC5.
// Derivation: starknet_keccak("mediolano.ip-sponsorship.v3").
pub const IIP_SPONSORSHIP_ID: felt252 =
    0x2acdd68e9e446816f8a4f4667264ce04d0bc9b85a519f7db14c0cf08a606ef3;

// The sponsorship license as a standard, freely transferable ERC-721.
// Derivation: starknet_keccak("mediolano.ip-sponsorship-license.v2").
pub const IIP_SPONSORSHIP_LICENSE_ID: felt252 =
    0xb14de94286e27cd2927d0c2bad0718857f9ad194efacfa09eb639e4dc5c190;

// Marks a collection whose metadata JSON carries the Mediolano programmable
// license trait schema (License, Commercial Use, Derivatives, Attribution,
// Territory, AI Policy, Standard, Registration). Discovery only — the license
// remains data in metadata, not contract-enforced state.
// Derivation: starknet_keccak("mediolano.licensed-collection.v1").
pub const ILICENSED_COLLECTION_ID: felt252 =
    0x3aaa3269207d0d03ca389e2a76f46c207ff513c2503ba463805d76ce52d75b8;

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
        royalty_bps: u256,
        specific_sponsor: Option<ContractAddress>,
    ) -> u256;
    fn set_offer_open(ref self: TContractState, offer_id: u256, open: bool);
    fn place_bid(ref self: TContractState, offer_id: u256, amount: u256);
    fn retract_bid(ref self: TContractState, offer_id: u256);
    fn accept_bid(ref self: TContractState, offer_id: u256, sponsor: ContractAddress) -> u256;
    fn get_offer(self: @TContractState, offer_id: u256) -> SponsorshipOffer;
    fn get_bid(self: @TContractState, offer_id: u256, sponsor: ContractAddress) -> u256;
    fn get_license(self: @TContractState, license_id: u256) -> LicenseData;
    fn is_license_valid(self: @TContractState, license_id: u256) -> bool;
    fn get_last_offer_id(self: @TContractState) -> u256;
    fn get_last_license_id(self: @TContractState) -> u256;
    fn get_license_contract(self: @TContractState) -> ContractAddress;
    // A sponsor proposes terms on an asset with no open offer yet — the
    // symmetric counterpart to create_offer. Any caller may propose; only
    // the asset's current owner may accept or reject. valid_until is an
    // acceptance deadline (unix seconds; 0 = no deadline).
    fn propose_sponsorship(
        ref self: TContractState,
        nft_contract: ContractAddress,
        token_id: u256,
        amount: u256,
        duration: u64,
        valid_until: u64,
        payment_token: ContractAddress,
        license_terms_uri: ByteArray,
        transferable: bool,
        royalty_bps: u256,
    ) -> u256;
    // Withdrawal (like bid retraction) is advisory against an in-flight
    // acceptance in the same block — revoking the ERC-20 allowance is the
    // guaranteed cancel, as acceptance settles against that allowance.
    fn withdraw_proposal(ref self: TContractState, proposal_id: u256);
    fn accept_proposal(ref self: TContractState, proposal_id: u256) -> u256;
    fn reject_proposal(ref self: TContractState, proposal_id: u256);
    fn get_proposal(self: @TContractState, proposal_id: u256) -> SponsorshipProposal;
    fn get_last_proposal_id(self: @TContractState) -> u256;
    fn version(self: @TContractState) -> ByteArray;
}

#[starknet::interface]
pub trait IIPSponsorshipLicense<TContractState> {
    /// One-time bootstrap: pins the IPSponsorship registry as the only
    /// minter. Reverts if a minter is already set — after the first call
    /// this contract has no privileged surface left.
    fn set_minter(ref self: TContractState, minter: ContractAddress);
    fn get_minter(self: @TContractState) -> ContractAddress;
    /// Mints a license token to the sponsor. Minter-only.
    fn mint(ref self: TContractState, recipient: ContractAddress, data: LicenseData) -> u256;
    fn get_license_data(self: @TContractState, token_id: u256) -> LicenseData;
    /// A license is valid while it exists (not burned) and is unexpired.
    fn is_license_valid(self: @TContractState, token_id: u256) -> bool;
    fn last_license_id(self: @TContractState) -> u256;
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn version(self: @TContractState) -> ByteArray;
}
