use ip_negotiation_escrow::types::Negotiation;
use starknet::ContractAddress;

pub const IIP_NEGOTIATION_ESCROW_ID: felt252 =
    0x0148a3c45c2f9c346979ac40c2783ef0c0d4fd028dbf7097d15a925fe601c54d;

#[starknet::interface]
pub trait IIPNegotiationEscrow<TContractState> {
    fn create_listing(
        ref self: TContractState,
        ip_asset_contract: ContractAddress,
        ip_token_id: u256,
        payment_token: ContractAddress,
        price: u256,
        listing_uri: ByteArray,
        listing_hash: felt252,
        terms_uri: ByteArray,
        terms_hash: felt252,
        deadline: u64,
    ) -> u256;

    fn fund_listing(ref self: TContractState, negotiation_id: u256) -> u256;

    fn submit_fulfillment(
        ref self: TContractState,
        negotiation_id: u256,
        fulfillment_uri: ByteArray,
        fulfillment_hash: felt252,
    );

    fn approve_fulfillment(ref self: TContractState, negotiation_id: u256);

    fn cancel_listing(ref self: TContractState, negotiation_id: u256);

    fn claim_seller_funds(ref self: TContractState, negotiation_id: u256) -> u256;

    fn claim_buyer_refund(ref self: TContractState, negotiation_id: u256) -> u256;

    fn get_negotiation(self: @TContractState, negotiation_id: u256) -> Negotiation;

    fn get_negotiation_by_asset(
        self: @TContractState, ip_asset_contract: ContractAddress, ip_token_id: u256,
    ) -> Negotiation;

    fn get_fulfillment_uri(self: @TContractState, negotiation_id: u256) -> ByteArray;

    fn get_claimable_seller_funds(
        self: @TContractState, negotiation_id: u256, seller: ContractAddress,
    ) -> u256;

    fn get_claimable_buyer_refund(
        self: @TContractState, negotiation_id: u256, buyer: ContractAddress,
    ) -> u256;

    fn get_last_negotiation_id(self: @TContractState) -> u256;
}
