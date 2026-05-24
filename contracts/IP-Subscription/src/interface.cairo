use starknet::ContractAddress;
use crate::types::{PlanRecord, SubscriptionRecord};

pub const IIP_SUBSCRIPTION_ID: felt252 =
    0x02b8b00d09660d14a71dfb5dd9f0acd39174877cf4e400f727b397a385e61ae3;

#[starknet::interface]
pub trait ISubscription<TContractState> {
    fn create_plan(
        ref self: TContractState,
        price: u256,
        duration: u64,
        tier: felt252,
        payment_token: Option<ContractAddress>,
        recipient: ContractAddress,
        metadata_uri: ByteArray,
    ) -> u256;
    fn set_plan_active(ref self: TContractState, plan_id: u256, active: bool);
    fn subscribe(ref self: TContractState, plan_id: u256);
    fn renew_subscription(ref self: TContractState, plan_id: u256);
    fn unsubscribe(ref self: TContractState, plan_id: u256);
    fn switch_subscription(ref self: TContractState, current_plan_id: u256, new_plan_id: u256);
    fn is_subscribed(self: @TContractState, subscriber: ContractAddress, plan_id: u256) -> bool;
    fn get_subscription(
        self: @TContractState, subscriber: ContractAddress, plan_id: u256,
    ) -> SubscriptionRecord;
    fn get_plan(self: @TContractState, plan_id: u256) -> PlanRecord;
    fn get_last_plan_id(self: @TContractState) -> u256;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn get_user_plan_ids(self: @TContractState, subscriber: ContractAddress) -> Array<u256>;
}
