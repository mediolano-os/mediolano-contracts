use starknet::ContractAddress;
use crate::types::{Commission, Milestone};

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-commission-escrow")
pub const IIP_COMMISSION_ESCROW_ID: felt252 =
    0x2732dc59dcc9ee3a818c88669f513e3b1b4bdd3717ea03ccff5059991314b51;

#[starknet::interface]
pub trait IIPCommissionEscrow<TContractState> {
    /// Opens a commission and escrows its full budget in the same
    /// transaction. The caller becomes the commissioner and receives the
    /// non-transferable offer NFT. `invited_creator` zero = open offer
    /// anyone may accept. `milestone_amounts` defines the payment plan; the
    /// budget is their sum. `review_period` (seconds, > 0) is the
    /// commissioner's own review SLA: a milestone left under review longer
    /// becomes claimable by the creator.
    fn create_commission(
        ref self: TContractState,
        invited_creator: ContractAddress,
        payment_token: ContractAddress,
        brief_uri: ByteArray,
        revisions_allowed: u32,
        deadline: u64,
        review_period: u64,
        milestone_amounts: Array<u256>,
    ) -> u256;

    /// Accepts an open commission before its deadline. Open offer: anyone
    /// but the commissioner. Invited offer: the invited creator only.
    fn accept_commission(ref self: TContractState, commission_id: u256);

    /// Creator only, before the deadline, strictly sequential (the previous
    /// milestone must be approved). Starts the review window.
    fn submit_milestone(
        ref self: TContractState,
        commission_id: u256,
        milestone_index: u32,
        deliverable_uri: ByteArray,
    );

    /// Commissioner only. Approves the milestone under review and credits
    /// the creator. The last approval completes the commission.
    fn approve_milestone(ref self: TContractState, commission_id: u256, milestone_index: u32);

    /// Commissioner only. Sends the milestone under review back for another
    /// pass, bounded by `revisions_allowed`.
    fn request_revision(ref self: TContractState, commission_id: u256, milestone_index: u32);

    /// Creator only. Approves a milestone the commissioner left under
    /// review past `review_period` — silence never wins.
    fn claim_overdue_milestone(ref self: TContractState, commission_id: u256, milestone_index: u32);

    /// Commissioner only. Before acceptance, or after the deadline when no
    /// milestone is under review. Unreleased escrow becomes refundable.
    fn cancel_commission(ref self: TContractState, commission_id: u256);

    /// Creator only, any time while in progress. Forfeits unearned
    /// milestones (they become refundable to the commissioner); earned
    /// milestones stay claimable.
    fn abandon_commission(ref self: TContractState, commission_id: u256);

    /// Pull payments for each party's unclaimed balance.
    fn claim_creator_funds(ref self: TContractState, commission_id: u256) -> u256;
    fn claim_commissioner_refund(ref self: TContractState, commission_id: u256) -> u256;

    /// Returns the Commission. Panics if never created.
    fn get_commission(self: @TContractState, commission_id: u256) -> Commission;

    /// Returns the Milestone. Panics if never created.
    fn get_milestone(self: @TContractState, commission_id: u256, milestone_index: u32) -> Milestone;

    /// Number of commissions created so far (ids are sequential from 1).
    fn commission_count(self: @TContractState) -> u256;

    fn version(self: @TContractState) -> ByteArray;
}
