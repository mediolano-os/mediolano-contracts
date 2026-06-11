use starknet::ContractAddress;
use crate::types::{PlanRecord, SubscriptionRecord};

// Protocol discovery ID registered via SRC5.
// Derivation: starknet_keccak("mediolano.ip-subscription.v2").
pub const IIP_SUBSCRIPTION_ID: felt252 =
    0x013f7d8dc8964bc1dc290304c1f2641165381c97e48c9f1497f90a93f7d513ac;

#[starknet::interface]
pub trait ISubscription<TContractState> {
    fn create_plan(
        ref self: TContractState,
        price: u256,
        duration: u64,
        payment_token: Option<ContractAddress>,
        recipient: ContractAddress,
        metadata_uri: ByteArray,
    ) -> u256;
    fn set_plan_active(ref self: TContractState, plan_id: u256, active: bool);
    fn subscribe(ref self: TContractState, plan_id: u256);
    fn renew_subscription(ref self: TContractState, plan_id: u256);
    fn is_subscribed(self: @TContractState, subscriber: ContractAddress, plan_id: u256) -> bool;
    fn get_subscription(
        self: @TContractState, subscriber: ContractAddress, plan_id: u256,
    ) -> SubscriptionRecord;
    fn get_plan(self: @TContractState, plan_id: u256) -> PlanRecord;
    fn get_last_plan_id(self: @TContractState) -> u256;
}
