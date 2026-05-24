use starknet::ContractAddress;
use crate::types::{TicketData, TicketSeries};

pub const IIP_TICKET_SERVICE_ID: felt252 =
    0x0064383abff0b2487b1c4acd681d761b39c91cc025a43bf0f7a355641b7c644f;

#[starknet::interface]
pub trait IIPTicketService<TContractState> {
    fn create_ticket_series(
        ref self: TContractState,
        price: u256,
        max_supply: u256,
        expiration: u64,
        royalty_bps: u256,
        payment_token: Option<ContractAddress>,
        metadata_uri: ByteArray,
    ) -> u256;

    fn mint_ticket(ref self: TContractState, series_id: u256) -> u256;

    fn redeem_ticket(ref self: TContractState, token_id: u256);

    fn has_valid_ticket(self: @TContractState, user: ContractAddress, series_id: u256) -> bool;

    fn get_ticket_series(self: @TContractState, series_id: u256) -> TicketSeries;

    fn get_ticket_data(self: @TContractState, token_id: u256) -> TicketData;

    fn get_ticket_series_id(self: @TContractState, token_id: u256) -> u256;

    fn get_active_ticket_balance(
        self: @TContractState, user: ContractAddress, series_id: u256,
    ) -> u256;

    fn get_last_series_id(self: @TContractState) -> u256;

    fn total_supply(self: @TContractState) -> u256;

    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
}
