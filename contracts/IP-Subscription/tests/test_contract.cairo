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

fn CREATOR1() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn CREATOR2() -> ContractAddress {
    0x105.try_into().unwrap()
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

const HOUR: u64 = 3600;

fn declare_and_deploy(contract_name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_subscription() -> ISubscriptionDispatcher {
    let address = declare_and_deploy("Subscription", array![]);
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

fn create_free_plan(subscription: ISubscriptionDispatcher, creator: ContractAddress) -> u256 {
    cheat_caller_address(subscription.contract_address, creator, CheatSpan::TargetCalls(1));
    subscription.create_plan(0, HOUR, Option::None, RECIPIENT(), IPFS_URI())
}

fn create_paid_plan(
    subscription: ISubscriptionDispatcher,
    creator: ContractAddress,
    token: ContractAddress,
    price: u256,
) -> u256 {
    cheat_caller_address(subscription.contract_address, creator, CheatSpan::TargetCalls(1));
    subscription.create_plan(price, HOUR, Option::Some(token), RECIPIENT(), IPFS_URI())
}

fn fund_and_approve(
    token: IERC20Dispatcher, user: ContractAddress, spender: ContractAddress, amount: u256,
) {
    mint_erc20(token.contract_address, user, amount);
    cheat_caller_address(token.contract_address, user, CheatSpan::TargetCalls(1));
    token.approve(spender, amount);
}

fn at(subscription: ISubscriptionDispatcher, ts: u64) {
    cheat_block_timestamp(subscription.contract_address, ts, CheatSpan::TargetCalls(1));
}

// --- plan creation ---

#[test]
fn test_create_plan_is_permissionless() {
    let subscription = deploy_subscription();

    let first = create_free_plan(subscription, CREATOR1());
    let second = create_free_plan(subscription, CREATOR2());

    assert(first == 1, 'first plan id should be one');
    assert(second == 2, 'second plan id should be two');
    assert(subscription.get_last_plan_id() == 2, 'last plan id should match');

    let plan1 = subscription.get_plan(first);
    assert(plan1.creator == CREATOR1(), 'creator1 should be recorded');
    assert(plan1.active, 'plan1 should be live');
    assert(plan1.price == 0, 'price should be zero');
    assert(plan1.duration == HOUR, 'duration should match');
    assert(plan1.metadata_uri == IPFS_URI(), 'metadata should match');

    let plan2 = subscription.get_plan(second);
    assert(plan2.creator == CREATOR2(), 'creator2 should be recorded');
}

#[test]
fn test_create_plan_accepts_ar_uri() {
    let subscription = deploy_subscription();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    let plan_id = subscription.create_plan(0, HOUR, Option::None, RECIPIENT(), AR_URI());

    assert(subscription.get_plan(plan_id).metadata_uri == AR_URI(), 'metadata should match');
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_plan_rejects_http_uri() {
    let subscription = deploy_subscription();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, HOUR, Option::None, RECIPIENT(), HTTP_URI());
}

#[test]
#[should_panic(expected: 'Duration cannot be zero')]
fn test_create_plan_rejects_zero_duration() {
    let subscription = deploy_subscription();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, 0, Option::None, RECIPIENT(), IPFS_URI());
}

#[test]
#[should_panic(expected: 'Recipient is zero address')]
fn test_create_plan_rejects_zero_recipient() {
    let subscription = deploy_subscription();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.create_plan(0, HOUR, Option::None, ZERO(), IPFS_URI());
}

#[test]
#[should_panic(expected: 'Free plan cannot use token')]
fn test_free_plan_rejects_payment_token() {
    let subscription = deploy_subscription();
    let token = deploy_erc20();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription
        .create_plan(0, HOUR, Option::Some(token.contract_address), RECIPIENT(), IPFS_URI());
}

#[test]
#[should_panic(expected: 'Paid plan requires token')]
fn test_paid_plan_requires_payment_token() {
    let subscription = deploy_subscription();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.create_plan(100, HOUR, Option::None, RECIPIENT(), IPFS_URI());
}

// --- plan management ---

#[test]
#[should_panic(expected: 'Only plan creator')]
fn test_only_plan_creator_can_toggle() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    cheat_caller_address(subscription.contract_address, CREATOR2(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, false);
}

#[test]
#[should_panic(expected: 'Plan does not exist')]
fn test_toggle_unknown_plan_reverts() {
    let subscription = deploy_subscription();

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(42, false);
}

#[test]
#[should_panic(expected: 'Plan is inactive')]
fn test_deactivation_blocks_subscribe() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, false);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);
}

#[test]
#[should_panic(expected: 'Plan is inactive')]
fn test_deactivation_blocks_renewal() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, false);

    at(subscription, 2000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);
}

#[test]
fn test_deactivation_preserves_paid_access() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, false);

    at(subscription, 2000);
    assert(subscription.is_subscribed(USER1(), plan_id), 'paid access should survive');
}

#[test]
fn test_reactivation_allows_subscribe() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, false);
    cheat_caller_address(subscription.contract_address, CREATOR1(), CheatSpan::TargetCalls(1));
    subscription.set_plan_active(plan_id, true);

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    at(subscription, 1000);
    assert(subscription.is_subscribed(USER1(), plan_id), 'subscribe should work again');
}

// --- subscribe / expiry ---

#[test]
fn test_subscribe_records_expiry() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.started_at == 1000, 'started_at should match');
    assert(record.expires_at == 1000 + HOUR, 'expires_at should match');
}

#[test]
#[should_panic(expected: 'Already subscribed')]
fn test_cannot_duplicate_active_subscription() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    at(subscription, 2000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);
}

#[test]
fn test_subscription_expires_by_time() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    // Active through the exact expiry second, inactive after it.
    at(subscription, 1000 + HOUR);
    assert(subscription.is_subscribed(USER1(), plan_id), 'active at expiry boundary');
    at(subscription, 1001 + HOUR);
    assert(!subscription.is_subscribed(USER1(), plan_id), 'inactive after expiry');
}

#[test]
fn test_resubscribe_after_expiry() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    let restart = 2000 + HOUR;
    at(subscription, restart);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.started_at == restart, 'streak should restart');
    assert(record.expires_at == restart + HOUR, 'expiry should restart');
}

// --- renewal ---

#[test]
fn test_renew_extends_from_current_expiry() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    at(subscription, 2000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);

    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.started_at == 1000, 'streak start should be kept');
    assert(record.expires_at == 1000 + 2 * HOUR, 'expiry should stack');
}

#[test]
#[should_panic(expected: 'Subscription inactive')]
fn test_renew_expired_subscription_reverts() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    at(subscription, 2000 + HOUR);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);
}

#[test]
#[should_panic(expected: 'Subscription inactive')]
fn test_renew_without_subscription_reverts() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);
}

// --- payments ---

#[test]
fn test_paid_subscribe_transfers_tokens() {
    let subscription = deploy_subscription();
    let token = deploy_erc20();
    let price: u256 = 250;
    let plan_id = create_paid_plan(subscription, CREATOR1(), token.contract_address, price);

    fund_and_approve(token, USER1(), subscription.contract_address, price);

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    assert(token.balance_of(USER1()) == 0, 'subscriber should be charged');
    assert(token.balance_of(RECIPIENT()) == price, 'recipient should be paid');
    at(subscription, 1000);
    assert(subscription.is_subscribed(USER1(), plan_id), 'subscription should be live');
}

#[test]
fn test_paid_renew_transfers_tokens() {
    let subscription = deploy_subscription();
    let token = deploy_erc20();
    let price: u256 = 250;
    let plan_id = create_paid_plan(subscription, CREATOR1(), token.contract_address, price);

    fund_and_approve(token, USER1(), subscription.contract_address, 2 * price);

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);

    at(subscription, 2000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.renew_subscription(plan_id);

    assert(token.balance_of(RECIPIENT()) == 2 * price, 'recipient paid twice');
    let record = subscription.get_subscription(USER1(), plan_id);
    assert(record.expires_at == 1000 + 2 * HOUR, 'expiry should stack');
}

#[test]
#[should_panic]
fn test_paid_subscribe_without_allowance_reverts() {
    let subscription = deploy_subscription();
    let token = deploy_erc20();
    let plan_id = create_paid_plan(subscription, CREATOR1(), token.contract_address, 250);

    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(plan_id);
}

// A malicious payment token that reenters `subscribe` during `transfer_from`
// runs under its own caller context: it can only create a subscription for
// itself. The victim's record is written before the external call
// (checks-effects-interactions), so state stays consistent without a lock.
#[test]
fn test_reentrant_payment_token_is_isolated() {
    let subscription = deploy_subscription();
    let free_plan = create_free_plan(subscription, CREATOR1());
    let reentrant_token = deploy_reentrant_payment_token(subscription.contract_address, free_plan);

    let paid_plan = create_paid_plan(subscription, CREATOR1(), reentrant_token, 250);

    at(subscription, 1000);
    cheat_caller_address(subscription.contract_address, USER1(), CheatSpan::TargetCalls(1));
    subscription.subscribe(paid_plan);

    at(subscription, 1000);
    assert(subscription.is_subscribed(USER1(), paid_plan), 'victim sub should be intact');
    at(subscription, 1000);
    assert(!subscription.is_subscribed(USER1(), free_plan), 'no sub forged for victim');
    at(subscription, 1000);
    let token_address: ContractAddress = reentrant_token;
    assert(subscription.is_subscribed(token_address, free_plan), 'token only subscribed itself');
}

// --- views / discovery ---

#[test]
fn test_supports_subscription_interface() {
    let subscription = deploy_subscription();
    let src5 = ISRC5Dispatcher { contract_address: subscription.contract_address };
    assert(src5.supports_interface(IIP_SUBSCRIPTION_ID), 'SRC5 id should be registered');
}

#[test]
#[should_panic(expected: 'Plan does not exist')]
fn test_missing_plan_reverts() {
    let subscription = deploy_subscription();
    subscription.get_plan(42);
}

#[test]
#[should_panic(expected: 'Subscription does not exist')]
fn test_missing_subscription_reverts() {
    let subscription = deploy_subscription();
    let plan_id = create_free_plan(subscription, CREATOR1());
    subscription.get_subscription(USER1(), plan_id);
}
