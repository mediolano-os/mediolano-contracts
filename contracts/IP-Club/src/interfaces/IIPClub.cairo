use starknet::ContractAddress;
use crate::types::ClubRecord;

// Protocol discovery ID registered via SRC5.
// Derivation: starknet_keccak("mediolano.ip-club.v2").
pub const IIP_CLUB_ID: felt252 = 0x027db28e39a9c175613ead4d5f54645106b22d41799a23649c05efbee3ebab61;

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
        transfer_lock: Option<u64>,
        royalty_bps: u256,
    ) -> u256;
    fn set_club_open(ref self: TContractState, club_id: u256, open: bool);
    fn join_club(ref self: TContractState, club_id: u256);
    fn leave_club(ref self: TContractState, club_id: u256, token_id: u256);
    fn get_club_record(self: @TContractState, club_id: u256) -> ClubRecord;
    fn is_member(self: @TContractState, club_id: u256, user: ContractAddress) -> bool;
    fn get_last_club_id(self: @TContractState) -> u256;
    fn version(self: @TContractState) -> ByteArray;
}
