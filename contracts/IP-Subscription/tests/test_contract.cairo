use ip_subscription::interface::{
    IIP_SUBSCRIPTION_ID, ISubscriptionDispatcher, ISubscriptionDispatcherTrait,
};
use ip_subscription::mocks::MockERC20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_block_timestamp, cheat_caller_address,
    declare,
};
use starknet::ContractAddress;

fn OWNER() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn USER1() -> ContractAddress {
    0x102.try_into().unwrap()
}

fn USER2() -> ContractAddress {
    0x103.try_into().unwrap()
}

fn RECIPIENT() -> ContractAddress {
    0x104.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn IPFS_URI() -> ByteArray {
    "ipfs://bafybeisubscription"
}

fn AR_URI() -> ByteArray {
    "ar://subscription-plan"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/plan.json"
}

fn declare_and_deploy(contract_name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_subscription(owner: ContractAddress) -> ISubscriptionDispatcher {
    let mut calldata = array![];
    calldata.append_serde(owner);
    let address = declare_and_deploy("Subscription", calldata);
    ISubscriptionDispatcher { contract_address: address }
}

fn deploy_erc20() -> IERC20Dispatcher {
    let mut calldata = array![];
    let name: ByteArray = "Mock Token";
    let symbol: ByteArray = "MOCK";
    let supply: u256 = 0;
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(supply);
    let address = declare_and_deploy("MockERC20", calldata);
    IERC20Dispatcher { contract_address: address }
}

fn mint_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) {
    IERC20MintDispatcher { contract_address: token }.mint(recipient, amount);
}

fn deploy_reentrant_payment_token(subscription: ContractAddress, plan_id: u256) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(subscription);
    calldata.append_serde(plan_id);
    declare_and_deploy("ReentrantPaymentToken", calldata)
}

fn create_free_plan(subscription: ISubscriptionDispatcher) -> u256 {
    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, 3600, 1, Option::None, RECIPIENT(), IPFS_URI())
}

#[test]
fn test_create_free_plan() {
    let subscription = deploy_subscription(OWNER());

    let plan_id = create_free_plan(subscription);

    assert(subscription.get_owner() == OWNER(), 'owner should match');
    assert(plan_id == 1, 'plan id should be one');
    assert(subscription.get_last_plan_id() == 1, 'last plan id should match');

    let plan = subscription.get_plan(plan_id);
    assert(plan.exists, 'plan should exist');
    assert(plan.active, 'plan should be active');
    assert(plan.price == 0, 'price should be zero');
    assert(plan.duration == 3600, 'duration should match');
    assert(plan.metadata_uri == IPFS_URI(), 'metadata should match');
}

#[test]
fn test_create_plan_accepts_ar_uri() {
    let subscription = deploy_subscription(OWNER());

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    let plan_id = subscription.create_plan(0, 3600, 1, Option::None, RECIPIENT(), AR_URI());

    assert(subscription.get_plan(plan_id).metadata_uri == AR_URI(), 'metadata should match');
}

#[test]
#[should_panic]
fn test_constructor_rejects_zero_owner() {
    deploy_subscription(ZERO());
}

#[test]
#[should_panic(expected: 'Only owner can create plans')]
fn test_only_owner_can_create_plan() {
    let subscription = deploy_subscription(OWNER());

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, 3600, 1, Option::None, RECIPIENT(), IPFS_URI());
}

#[test]
#[should_panic(expected: 'Duration cannot be zero')]
fn test_create_plan_rejects_zero_duration() {
    let subscription = deploy_subscription(OWNER());

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, 0, 1, Option::None, RECIPIENT(), IPFS_URI());
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_plan_rejects_http_uri() {
    let subscription = deploy_subscription(OWNER());

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, 3600, 1, Option::None, RECIPIENT(), HTTP_URI());
}

#[test]
#[should_panic(expected: 'Free plan cannot use token')]
fn test_free_plan_rejects_payment_token() {
    let subscription = deploy_subscription(OWNER());
    let erc20 = deploy_erc20();

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    subscription
        .create_plan(0, 3600, 1, Option::Some(erc20.contract_address), RECIPIENT(), IPFS_URI());
}

#[test]
#[should_panic]
fn test_paid_plan_requires_payment_token() {
    let subscription = deploy_subscription(OWNER());

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    subscription.create_plan(1000, 3600, 1, Option::None, RECIPIENT(), IPFS_URI());
}

#[test]
fn test_subscribe_free_plan_records_expiry() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);
    let now: u64 = 1000;

    cheat_block_timestamp(subscription.contract_address, now, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.subscriber == USER1(), 'subscriber should match');
    assert(record.plan_id == plan_id, 'plan should match');
    assert(record.started_at == now, 'start should match');
    assert(record.expires_at == now + 3600, 'expiry should match');
    assert(subscription.is_subscribed(USER1(), plan_id), 'should be subscribed');

    let plan_ids = subscription.get_user_plan_ids(USER1());
    assert(plan_ids.len() == 1, 'one plan id expected');
    assert(*plan_ids.at(0) == plan_id, 'plan id should match');
}

#[test]
#[should_panic(expected: 'Already subscribed')]
fn test_cannot_duplicate_active_subscription() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);
}

#[test]
fn test_subscription_expires_by_time() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);

    cheat_block_timestamp(subscription.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_block_timestamp(subscription.contract_address, 5000, CheatSpan::TargetCalls(1));
    assert(!subscription.is_subscribed(USER1(), plan_id), 'should expire');
}

#[test]
fn test_renew_subscription_extends_active_subscription() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);

    cheat_block_timestamp(subscription.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_block_timestamp(subscription.contract_address, 2000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);

    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.expires_at == 8200, 'renew extends expiry');
    assert(subscription.is_subscribed(USER1(), plan_id), 'should still be active');
}

#[test]
fn test_renew_expired_subscription_reactivates_from_now() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);

    cheat_block_timestamp(subscription.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_block_timestamp(subscription.contract_address, 5000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);

    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.expires_at == 8600, 'renewal should start from now');
    assert(subscription.is_subscribed(USER1(), plan_id), 'should be active');
}

#[test]
fn test_unsubscribe_disables_subscription() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_block_timestamp(subscription.contract_address, 1200, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.unsubscribe(plan_id);

    assert(!subscription.is_subscribed(USER1(), plan_id), 'should not be active');
    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.expires_at == 1200, 'expiry is unsubscribe');
}

#[test]
fn test_paid_subscribe_transfers_tokens() {
    let subscription = deploy_subscription(OWNER());
    let erc20 = deploy_erc20();

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    let plan_id = subscription
        .create_plan(1000, 3600, 1, Option::Some(erc20.contract_address), RECIPIENT(), IPFS_URI());

    mint_erc20(erc20.contract_address, USER1(), 3000);
    cheat_caller_address(erc20.contract_address, USER1(), CheatSpan::TargetCalls(1));
    erc20.approve(subscription.contract_address, 1000);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    assert(erc20.balance_of(RECIPIENT()) == 1000, 'recipient should be paid');
    assert(erc20.balance_of(USER1()) == 2000, 'payer balance should decrement');
}

#[test]
fn test_paid_renew_transfers_tokens() {
    let subscription = deploy_subscription(OWNER());
    let erc20 = deploy_erc20();

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    let plan_id = subscription
        .create_plan(1000, 3600, 1, Option::Some(erc20.contract_address), RECIPIENT(), IPFS_URI());

    mint_erc20(erc20.contract_address, USER1(), 3000);
    cheat_caller_address(erc20.contract_address, USER1(), CheatSpan::TargetCalls(1));
    erc20.approve(subscription.contract_address, 3000);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_block_timestamp(subscription.contract_address, 2000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);

    assert(erc20.balance_of(RECIPIENT()) == 2000, 'recipient gets renewal');
    assert(erc20.balance_of(USER1()) == 1000, 'payer pays twice');
}

#[test]
fn test_paid_switch_transfers_new_plan_price() {
    let subscription = deploy_subscription(OWNER());
    let erc20 = deploy_erc20();

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(2));
    let basic_id = subscription.create_plan(0, 3600, 1, Option::None, RECIPIENT(), IPFS_URI());
    let pro_id = subscription
        .create_plan(2000, 7200, 2, Option::Some(erc20.contract_address), RECIPIENT(), IPFS_URI());

    mint_erc20(erc20.contract_address, USER1(), 2500);
    cheat_caller_address(erc20.contract_address, USER1(), CheatSpan::TargetCalls(1));
    erc20.approve(subscription.contract_address, 2000);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(basic_id);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.switch_subscription(basic_id, pro_id);

    assert(erc20.balance_of(RECIPIENT()) == 2000, 'recipient gets pro');
    assert(erc20.balance_of(USER1()) == 500, 'payer pays pro');
}

#[test]
fn test_switch_subscription() {
    let subscription = deploy_subscription(OWNER());

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(2));
    let basic_id = subscription.create_plan(0, 3600, 1, Option::None, RECIPIENT(), IPFS_URI());
    let pro_id = subscription.create_plan(0, 7200, 2, Option::None, RECIPIENT(), IPFS_URI());

    cheat_block_timestamp(subscription.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(basic_id);

    cheat_block_timestamp(subscription.contract_address, 1500, CheatSpan::TargetCalls(1));
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.switch_subscription(basic_id, pro_id);

    assert(!subscription.is_subscribed(USER1(), basic_id), 'basic should be inactive');
    assert(subscription.is_subscribed(USER1(), pro_id), 'pro should be active');
    assert(
        subscription.get_subscription(USER1(), pro_id).expires_at == 8700, 'expiry should match',
    );
}

#[test]
#[should_panic(expected: 'Plan is inactive')]
fn test_inactive_plan_rejects_new_subscription() {
    let subscription = deploy_subscription(OWNER());
    let plan_id = create_free_plan(subscription);

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, false);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);
}

#[test]
#[should_panic(expected: 'Reentrant subscription')]
fn test_reentrant_payment_token_rejected() {
    let subscription = deploy_subscription(OWNER());
    let expected_plan_id = 1;
    let token = deploy_reentrant_payment_token(subscription.contract_address, expected_plan_id);

    cheat_caller_address(subscription.contract_address, OWNER(), CheatSpan::TargetCalls(1));
    let plan_id = subscription
        .create_plan(1000, 3600, 1, Option::Some(token), RECIPIENT(), IPFS_URI());
    assert(plan_id == expected_plan_id, 'test expects first plan');

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);
}

#[test]
fn test_supports_subscription_interface() {
    let subscription = deploy_subscription(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: subscription.contract_address };

    assert(src5.supports_interface(IIP_SUBSCRIPTION_ID), 'interface should be supported');
}

#[test]
#[should_panic(expected: 'Plan does not exist')]
fn test_missing_plan_reverts() {
    let subscription = deploy_subscription(OWNER());

    subscription.get_plan(1);
}
