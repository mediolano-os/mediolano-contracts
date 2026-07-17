use ip_crowdfunding::interface::{
    IIPCrowdfundingCollectionDispatcher, IIPCrowdfundingCollectionDispatcherTrait,
    IIP_CROWDFUNDING_COLLECTION_ID,
};
use ip_crowdfunding::mock::malicious_erc20::{
    IMaliciousERC20ConfigDispatcher, IMaliciousERC20ConfigDispatcherTrait, MaliciousERC20,
};
use ip_crowdfunding::mock::mock_erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_crowdfunding::types::CampaignStatus;
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

const END_TIME: u64 = 10_000;

fn OTHER() -> ContractAddress {
    0x333.try_into().unwrap()
}

fn deploy_mock_account() -> ContractAddress {
    let class = declare("MockAccount").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

fn deploy_erc20() -> ContractAddress {
    let class = declare("MockERC20").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "Mock Token";
    let symbol: ByteArray = "MTK";
    cd.append_serde(name);
    cd.append_serde(symbol);
    cd.append_serde(0_u256);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

fn deploy_malicious_erc20() -> ContractAddress {
    let class = declare("MaliciousERC20").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "Malicious Token";
    let symbol: ByteArray = "EVIL";
    cd.append_serde(name);
    cd.append_serde(symbol);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

fn deploy_collection_with_owner(owner: ContractAddress) -> ContractAddress {
    let class = declare("IPCrowdfundingCollection").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "Crowdfunding Test";
    let symbol: ByteArray = "FUND";
    let base_uri: ByteArray = "ipfs://QmCollectionMeta/";
    cd.append_serde(name);
    cd.append_serde(symbol);
    cd.append_serde(base_uri);
    cd.append_serde(owner);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

fn fund_and_approve(
    token: ContractAddress, account: ContractAddress, spender: ContractAddress, amount: u256,
) {
    IERC20MintDispatcher { contract_address: token }.mint(account, amount);
    start_cheat_caller_address(token, account);
    IERC20Dispatcher { contract_address: token }.approve(spender, amount);
    stop_cheat_caller_address(token);
}

/// owner + collection + payment token + one funded backer.
fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let owner = deploy_mock_account();
    let collection = deploy_collection_with_owner(owner);
    let token = deploy_erc20();
    let backer = deploy_mock_account();
    fund_and_approve(token, backer, collection, 1_000_000_u256);
    (owner, collection, token, backer)
}

fn create_campaign(
    collection: ContractAddress, owner: ContractAddress, token: ContractAddress, goal: u256,
) -> u256 {
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    let id = dispatcher.create_campaign(goal, token, END_TIME, "ipfs://QmCampaign");
    stop_cheat_caller_address(collection);
    id
}

fn contribute_as(
    collection: ContractAddress, backer: ContractAddress, token_id: u256, amount: u256,
) -> u256 {
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, backer);
    let contributed = dispatcher.contribute(token_id, amount);
    stop_cheat_caller_address(collection);
    contributed
}

// ──────────────── create_campaign
// ────────────────

#[test]
fn test_create_assigns_sequential_ids() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id1 = create_campaign(collection, owner, token, 1000_u256);
    let id2 = create_campaign(collection, owner, token, 2000_u256);
    assert(id1 == 1_u256, 'first id should be 1');
    assert(id2 == 2_u256, 'second id should be 2');
    assert(dispatcher.campaign_count() == 2_u256, 'count should be 2');

    let c = dispatcher.get_campaign(id1);
    assert(c.goal_amount == 1000_u256, 'wrong goal');
    assert(c.end_time == END_TIME, 'wrong end time');
    assert(!c.cancelled, 'should not be cancelled');
    assert(dispatcher.campaign_status(id1) == CampaignStatus::Active, 'should be active');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_create_non_owner_panics() {
    let (_, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, OTHER());
    dispatcher.create_campaign(1000_u256, token, END_TIME, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Goal is zero')]
fn test_create_zero_goal_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_campaign(0_u256, token, END_TIME, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Payment token is zero')]
fn test_create_zero_token_panics() {
    let (owner, collection, _, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_campaign(1000_u256, 0.try_into().unwrap(), END_TIME, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'End time in the past')]
fn test_create_past_end_time_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_block_timestamp(collection, END_TIME + 1);
    start_cheat_caller_address(collection, owner);
    dispatcher.create_campaign(1000_u256, token, END_TIME, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_bad_uri_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_campaign(1000_u256, token, END_TIME, "https://example.com");
}

#[test]
#[should_panic(expected: 'Campaign not found')]
fn test_get_unknown_campaign_panics() {
    let (_, collection, _, _) = setup();
    IIPCrowdfundingCollectionDispatcher { contract_address: collection }.get_campaign(99_u256);
}

// ──────────────── contribute
// ────────────────

#[test]
fn test_contribute_records_and_moves_funds() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256);

    contribute_as(collection, backer, id, 400_u256);
    assert(dispatcher.get_position(id, backer).contributed == 400_u256, 'wrong position');
    assert(dispatcher.get_campaign(id).total_raised == 400_u256, 'wrong raised');
    assert(erc20.balance_of(collection) == 400_u256, 'escrow should hold funds');
}

#[test]
fn test_overfunding_allowed() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1500_u256);
    contribute_as(collection, backer, id, 500_u256);
    assert(dispatcher.get_campaign(id).total_raised == 2000_u256, 'overfunding should work');
    assert(dispatcher.campaign_status(id) == CampaignStatus::Active, 'still active until end');
}

#[test]
#[should_panic(expected: 'Campaign not active')]
fn test_contribute_after_end_panics() {
    let (owner, collection, token, backer) = setup();
    let id = create_campaign(collection, owner, token, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    contribute_as(collection, backer, id, 100_u256);
}

#[test]
#[should_panic(expected: 'Campaign not active')]
fn test_contribute_after_cancel_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_campaign(id);
    stop_cheat_caller_address(collection);
    contribute_as(collection, backer, id, 100_u256);
}

#[test]
#[should_panic(expected: 'Amount is zero')]
fn test_contribute_zero_panics() {
    let (owner, collection, token, backer) = setup();
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 0_u256);
}

#[test]
#[should_panic(expected: 'Payment failed')]
fn test_fee_on_transfer_token_rejected() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    let backer = deploy_mock_account();
    fund_and_approve(malicious, backer, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::SHORT_TRANSFER_FROM, 0_u256);
    contribute_as(collection, backer, id, 100_u256);
}

// ──────────────── withdraw
// ────────────────

#[test]
fn test_withdraw_while_active() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 400_u256);
    let balance_before = erc20.balance_of(backer);

    start_cheat_caller_address(collection, backer);
    dispatcher.withdraw(id, 150_u256);
    stop_cheat_caller_address(collection);

    assert(dispatcher.get_position(id, backer).contributed == 250_u256, 'wrong position');
    assert(dispatcher.get_campaign(id).total_raised == 250_u256, 'wrong raised');
    assert(erc20.balance_of(backer) == balance_before + 150_u256, 'funds not returned');
}

#[test]
#[should_panic(expected: 'Campaign not active')]
fn test_withdraw_after_end_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 400_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, backer);
    dispatcher.withdraw(id, 100_u256);
}

#[test]
#[should_panic(expected: 'Insufficient contribution')]
fn test_withdraw_more_than_contributed_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 100_u256);
    start_cheat_caller_address(collection, backer);
    dispatcher.withdraw(id, 101_u256);
}

// ──────────────── success path
// ────────────────

#[test]
fn test_success_proceeds_and_receipts() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let erc1155 = IERC1155Dispatcher { contract_address: collection };
    let second = deploy_mock_account();
    fund_and_approve(token, second, collection, 1_000_000_u256);

    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 700_u256);
    contribute_as(collection, second, id, 500_u256); // overfunded: 1200 total

    start_cheat_block_timestamp(collection, END_TIME);
    assert(dispatcher.campaign_status(id) == CampaignStatus::Succeeded, 'should be succeeded');

    start_cheat_caller_address(collection, owner);
    let proceeds = dispatcher.claim_proceeds(id);
    stop_cheat_caller_address(collection);
    assert(proceeds == 1200_u256, 'wrong proceeds');
    assert(erc20.balance_of(owner) == 1200_u256, 'owner not paid');

    start_cheat_caller_address(collection, backer);
    dispatcher.mint_receipt(id);
    stop_cheat_caller_address(collection);
    start_cheat_caller_address(collection, second);
    dispatcher.mint_receipt(id);
    stop_cheat_caller_address(collection);

    assert(erc1155.balance_of(backer, id) == 700_u256, 'wrong receipt 1');
    assert(erc1155.balance_of(second, id) == 500_u256, 'wrong receipt 2');
}

#[test]
#[should_panic(expected: 'Receipt is non-transferable')]
fn test_receipt_transfer_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let erc1155 = IERC1155Dispatcher { contract_address: collection };
    let recipient = deploy_mock_account();
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, backer);
    dispatcher.mint_receipt(id);
    erc1155.safe_transfer_from(backer, recipient, id, 100_u256, array![].span());
}

#[test]
#[should_panic(expected: 'Receipt already minted')]
fn test_double_receipt_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, backer);
    dispatcher.mint_receipt(id);
    dispatcher.mint_receipt(id);
}

#[test]
#[should_panic(expected: 'Not a backer')]
fn test_receipt_non_backer_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    let outsider = deploy_mock_account();
    start_cheat_caller_address(collection, outsider);
    dispatcher.mint_receipt(id);
}

#[test]
#[should_panic(expected: 'Campaign not succeeded')]
fn test_receipt_on_failed_campaign_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 500_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, backer);
    dispatcher.mint_receipt(id);
}

#[test]
#[should_panic(expected: 'Proceeds already claimed')]
fn test_double_proceeds_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, owner);
    dispatcher.claim_proceeds(id);
    dispatcher.claim_proceeds(id);
}

#[test]
#[should_panic(expected: 'Campaign not succeeded')]
fn test_proceeds_before_end_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.claim_proceeds(id);
}

// ──────────────── failure + cancel paths
// ────────────────

#[test]
fn test_failed_campaign_refunds() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 400_u256);
    let balance_before = erc20.balance_of(backer);

    start_cheat_block_timestamp(collection, END_TIME);
    assert(dispatcher.campaign_status(id) == CampaignStatus::Failed, 'should be failed');

    start_cheat_caller_address(collection, backer);
    let refunded = dispatcher.claim_refund(id);
    stop_cheat_caller_address(collection);
    assert(refunded == 400_u256, 'wrong refund');
    assert(erc20.balance_of(backer) == balance_before + 400_u256, 'funds not refunded');
    assert(dispatcher.get_position(id, backer).contributed == 0_u256, 'position not zeroed');
}

#[test]
fn test_cancelled_campaign_refunds() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 400_u256);

    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_campaign(id);
    stop_cheat_caller_address(collection);
    assert(dispatcher.campaign_status(id) == CampaignStatus::Cancelled, 'should be cancelled');

    start_cheat_caller_address(collection, backer);
    let refunded = dispatcher.claim_refund(id);
    stop_cheat_caller_address(collection);
    assert(refunded == 400_u256, 'wrong refund');
}

#[test]
#[should_panic(expected: 'No refund available')]
fn test_double_refund_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 400_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, backer);
    dispatcher.claim_refund(id);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Campaign not refundable')]
fn test_refund_while_active_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 400_u256);
    start_cheat_caller_address(collection, backer);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Campaign not refundable')]
fn test_refund_on_succeeded_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, backer);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_cancel_non_owner_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    start_cheat_caller_address(collection, OTHER());
    dispatcher.cancel_campaign(id);
}

#[test]
#[should_panic(expected: 'Campaign not active')]
fn test_cancel_after_end_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    start_cheat_block_timestamp(collection, END_TIME);
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_campaign(id);
}

#[test]
#[should_panic(expected: 'Campaign not succeeded')]
fn test_proceeds_on_cancelled_panics() {
    let (owner, collection, token, backer) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_campaign(id);
    start_cheat_block_timestamp(collection, END_TIME);
    dispatcher.claim_proceeds(id);
}

// ──────────────── security: reentrancy
// ────────────────

#[test]
fn test_reentrant_contribute_keeps_accounting_exact() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    let backer = deploy_mock_account();
    fund_and_approve(malicious, backer, collection, 1_000_000_u256);
    // The token contract itself backs the campaign and reenters contribute
    // from inside transfer_from.
    fund_and_approve(malicious, malicious, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_CONTRIBUTE, 300_u256);
    cheat_caller_address(collection, backer, CheatSpan::TargetCalls(1));
    IIPCrowdfundingCollectionDispatcher { contract_address: collection }.contribute(id, 400_u256);

    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    assert(dispatcher.get_campaign(id).total_raised == 700_u256, 'wrong total raised');
    assert(dispatcher.get_position(id, backer).contributed == 400_u256, 'wrong outer pos');
    assert(dispatcher.get_position(id, malicious).contributed == 300_u256, 'wrong nested pos');
}

#[test]
#[should_panic(expected: 'Insufficient contribution')]
fn test_reentrant_withdraw_cannot_double_spend() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    fund_and_approve(malicious, malicious, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256);
    contribute_as(collection, malicious, id, 500_u256);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_WITHDRAW, 500_u256);
    start_cheat_caller_address(collection, malicious);
    IIPCrowdfundingCollectionDispatcher { contract_address: collection }.withdraw(id, 500_u256);
}

#[test]
#[should_panic(expected: 'No refund available')]
fn test_reentrant_refund_cannot_double_claim() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    fund_and_approve(malicious, malicious, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256);
    contribute_as(collection, malicious, id, 500_u256);

    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    start_cheat_block_timestamp(collection, END_TIME);
    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_REFUND, 0_u256);
    start_cheat_caller_address(collection, malicious);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Proceeds already claimed')]
fn test_reentrant_proceeds_cannot_double_claim() {
    let malicious = deploy_malicious_erc20();
    // Owner is the malicious token so its transfer hook can reenter
    // claim_proceeds as the collection owner.
    let collection = deploy_collection_with_owner(malicious);
    let backer = deploy_mock_account();
    fund_and_approve(malicious, backer, collection, 1_000_000_u256);
    let id = create_campaign(collection, malicious, malicious, 1000_u256);
    contribute_as(collection, backer, id, 1000_u256);

    start_cheat_block_timestamp(collection, END_TIME);
    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_PROCEEDS, 0_u256);
    start_cheat_caller_address(collection, malicious);
    IIPCrowdfundingCollectionDispatcher { contract_address: collection }.claim_proceeds(id);
}

// ──────────────── views + discovery
// ────────────────

#[test]
fn test_collection_identity_views() {
    let (_, collection, _, _) = setup();
    let dispatcher = IIPCrowdfundingCollectionDispatcher { contract_address: collection };
    assert(dispatcher.name() == "Crowdfunding Test", 'wrong name');
    assert(dispatcher.symbol() == "FUND", 'wrong symbol');
    assert(dispatcher.base_uri() == "ipfs://QmCollectionMeta/", 'wrong base uri');
    assert(dispatcher.version() == "1.0.0", 'wrong version');
}

#[test]
fn test_src5_interfaces_registered() {
    let (_, collection, _, _) = setup();
    let src5 = ISRC5Dispatcher { contract_address: collection };
    assert(src5.supports_interface(IIP_CROWDFUNDING_COLLECTION_ID), 'service id missing');
}
