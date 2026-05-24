use ip_commission_escrow::types::{Commission, MilestoneDetails};
use starknet::ContractAddress;

pub const IIP_COMMISSION_ESCROW_ID: felt252 =
    0x020b1655b35dced41a9f0c857992e8dffdf747d83ddc9e922b572a6d8dcc3d08;

#[starknet::interface]
pub trait IIPCommissionEscrow<TContractState> {
    fn create_commission(
        ref self: TContractState,
        invited_creator: ContractAddress,
        payment_token: ContractAddress,
        total_amount: u256,
        brief_uri: ByteArray,
        brief_hash: felt252,
        license_uri: ByteArray,
        license_hash: felt252,
        revisions_allowed: u32,
        deadline: u64,
        milestone_amounts: Array<u256>,
    ) -> u256;

    fn fund_commission(ref self: TContractState, commission_id: u256) -> u256;

    fn accept_commission(ref self: TContractState, commission_id: u256);

    fn submit_milestone(
        ref self: TContractState,
        commission_id: u256,
        milestone_index: u32,
        deliverable_uri: ByteArray,
        deliverable_hash: felt252,
    );

    fn request_revision(ref self: TContractState, commission_id: u256, milestone_index: u32);

    fn approve_milestone(ref self: TContractState, commission_id: u256, milestone_index: u32);

    fn cancel_commission(ref self: TContractState, commission_id: u256);

    fn claim_creator_funds(ref self: TContractState, commission_id: u256) -> u256;

    fn claim_commissioner_refund(ref self: TContractState, commission_id: u256) -> u256;

    fn get_commission(self: @TContractState, commission_id: u256) -> Commission;

    fn get_milestone(
        self: @TContractState, commission_id: u256, milestone_index: u32,
    ) -> MilestoneDetails;

    fn get_milestone_deliverable_uri(
        self: @TContractState, commission_id: u256, milestone_index: u32,
    ) -> ByteArray;

    fn get_claimable_creator_funds(
        self: @TContractState, commission_id: u256, creator: ContractAddress,
    ) -> u256;

    fn get_claimable_commissioner_refund(
        self: @TContractState, commission_id: u256, commissioner: ContractAddress,
    ) -> u256;

    fn get_last_commission_id(self: @TContractState) -> u256;
}
