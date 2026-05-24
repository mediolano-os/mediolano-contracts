use ip_syndication::types::{IPMetadata, Mode, ParticipantDetails, Status, SyndicationDetails};
use starknet::ContractAddress;

pub const IIP_SYNDICATION_ID: felt252 =
    0x03d8a3fb2b0e94c537cf673b579ec4cb94e6916e1fc0f38ecf50cc13fb6a2fb5;

#[starknet::interface]
pub trait IIPSyndication<TContractState> {
    fn register_ip(
        ref self: TContractState,
        target_amount: u256,
        name: felt252,
        description: ByteArray,
        metadata_uri: ByteArray,
        licensing_terms: felt252,
        mode: Mode,
        payment_token: ContractAddress,
    ) -> u256;

    fn activate_syndication(ref self: TContractState, ip_id: u256);

    fn update_whitelist(
        ref self: TContractState, ip_id: u256, account: ContractAddress, status: bool,
    );

    fn deposit(ref self: TContractState, ip_id: u256, amount: u256) -> u256;

    fn cancel_syndication(ref self: TContractState, ip_id: u256);

    fn claim_refund(ref self: TContractState, ip_id: u256) -> u256;

    fn claim_proceeds(ref self: TContractState, ip_id: u256) -> u256;

    fn mint_asset(ref self: TContractState, ip_id: u256);

    fn is_whitelisted(self: @TContractState, ip_id: u256, account: ContractAddress) -> bool;

    fn get_ip_metadata(self: @TContractState, ip_id: u256) -> IPMetadata;

    fn get_syndication_details(self: @TContractState, ip_id: u256) -> SyndicationDetails;

    fn get_syndication_status(self: @TContractState, ip_id: u256) -> Status;

    fn get_participant_details(
        self: @TContractState, ip_id: u256, participant: ContractAddress,
    ) -> ParticipantDetails;

    fn get_all_participants(self: @TContractState, ip_id: u256) -> Array<ContractAddress>;

    fn get_participants(
        self: @TContractState, ip_id: u256, start: u256, limit: u256,
    ) -> Array<ContractAddress>;

    fn get_participant_count(self: @TContractState, ip_id: u256) -> u256;

    fn get_last_ip_id(self: @TContractState) -> u256;

    fn get_claimable_refund(
        self: @TContractState, ip_id: u256, participant: ContractAddress,
    ) -> u256;

    fn total_shares_minted(self: @TContractState, ip_id: u256) -> u256;
}
