use starknet::ContractAddress;
use crate::types::ClubRecord;

pub const IIP_CLUB_ID: felt252 = 0x03b5aa442badd81e46ab69f8de85a01dd131401c146133b0a1a9a112270e9c7b;

#[starknet::interface]
pub trait IIPClub<TContractState> {
    fn create_club(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        metadata_uri: ByteArray,
        max_members: Option<u32>,
        entry_fee: Option<u256>,
        payment_token: Option<ContractAddress>,
    ) -> u256;
    fn close_club(ref self: TContractState, club_id: u256);
    fn join_club(ref self: TContractState, club_id: u256);
    fn get_club_record(self: @TContractState, club_id: u256) -> ClubRecord;
    fn is_member(self: @TContractState, club_id: u256, user: ContractAddress) -> bool;
    fn get_last_club_id(self: @TContractState) -> u256;
}
