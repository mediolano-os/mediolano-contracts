use ip_syndication::interface::{
    IIPSyndicationCollectionDispatcher, IIPSyndicationCollectionDispatcherTrait,
    IIP_SYNDICATION_COLLECTION_ID,
};
use ip_syndication::mock::malicious_erc20::{
    IMaliciousERC20ConfigDispatcher, IMaliciousERC20ConfigDispatcherTrait, MaliciousERC20,
};
use ip_syndication::mock::mock_erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_syndication::types::Status;
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

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

fn deploy_collection_with_owner(owner: ContractAddress) -> ContractAddress {
    let class = declare("IPSyndicationCollection").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "IP Syndications Test";
    let symbol: ByteArray = "SYND";
    let base_uri: ByteArray = "ipfs://QmCollectionMeta/";
    cd.append_serde(name);
    cd.append_serde(symbol);
    cd.append_serde(base_uri);
    cd.append_serde(owner);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

/// owner + collection + payment token + one funded/approved participant.
fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let owner = deploy_mock_account();
    let collection = deploy_collection_with_owner(owner);
    let token = deploy_erc20();
    let participant = deploy_mock_account();
    fund_and_approve(token, participant, collection, 1_000_000_u256);
    (owner, collection, token, participant)
}

fn fund_and_approve(
    token: ContractAddress, account: ContractAddress, spender: ContractAddress, amount: u256,
) {
    IERC20MintDispatcher { contract_address: token }.mint(account, amount);
    start_cheat_caller_address(token, account);
    IERC20Dispatcher { contract_address: token }.approve(spender, amount);
    stop_cheat_caller_address(token);
}

fn create_campaign(
    collection: ContractAddress,
    owner: ContractAddress,
    token: ContractAddress,
    target: u256,
    whitelist: bool,
) -> u256 {
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    let id = dispatcher.create_syndication(target, token, whitelist, 500_u16, "ipfs://QmCampaign");
    stop_cheat_caller_address(collection);
    id
}

fn deposit_as(
    collection: ContractAddress, participant: ContractAddress, token_id: u256, amount: u256,
) -> u256 {
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, participant);
    let deposited = dispatcher.deposit(token_id, amount);
    stop_cheat_caller_address(collection);
    deposited
}

// ──────────────── create_syndication
// ────────────────

#[test]
fn test_create_assigns_sequential_ids() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id1 = create_campaign(collection, owner, token, 1000_u256, false);
    let id2 = create_campaign(collection, owner, token, 2000_u256, false);
    assert(id1 == 1_u256, 'first id should be 1');
    assert(id2 == 2_u256, 'second id should be 2');
    assert(dispatcher.syndication_count() == 2_u256, 'count should be 2');
}

#[test]
fn test_create_stores_campaign() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    let syndication = dispatcher.get_syndication(id);
    assert(syndication.target_amount == 1000_u256, 'wrong target');
    assert(syndication.total_raised == 0_u256, 'raised should be 0');
    assert(syndication.payment_token == token, 'wrong payment token');
    assert(!syndication.whitelist, 'should not be whitelist');
    assert(syndication.status == Status::Active, 'should be active');
    assert(!syndication.proceeds_claimed, 'proceeds not claimed');
    assert(syndication.royalty_bps == 500_u16, 'wrong royalty');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_create_non_owner_panics() {
    let (_, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, OTHER());
    dispatcher.create_syndication(1000_u256, token, false, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Target is zero')]
fn test_create_zero_target_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_syndication(0_u256, token, false, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Payment token is zero')]
fn test_create_zero_token_panics() {
    let (owner, collection, _, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_syndication(1000_u256, 0.try_into().unwrap(), false, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_create_royalty_overflow_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_syndication(1000_u256, token, false, 10001_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_bad_uri_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_syndication(1000_u256, token, false, 0_u16, "https://example.com");
}

#[test]
fn test_uri_resolves_per_campaign() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    let erc1155 = IERC1155Dispatcher { contract_address: collection };
    let _ = erc1155;
    let syndication = dispatcher.get_syndication(id);
    assert(syndication.metadata_uri == "ipfs://QmCampaign", 'wrong metadata uri');
}

#[test]
#[should_panic(expected: 'Syndication not found')]
fn test_get_unknown_campaign_panics() {
    let (_, collection, _, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    dispatcher.get_syndication(99_u256);
}

// ──────────────── deposit
// ────────────────

#[test]
fn test_deposit_records_position_and_moves_funds() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256, false);

    let deposited = deposit_as(collection, participant, id, 400_u256);
    assert(deposited == 400_u256, 'wrong deposit amount');
    assert(dispatcher.get_position(id, participant).deposited == 400_u256, 'wrong position');
    assert(dispatcher.get_syndication(id).total_raised == 400_u256, 'wrong total raised');
    assert(erc20.balance_of(collection) == 400_u256, 'escrow should hold funds');
}

#[test]
fn test_deposit_clamps_to_remaining() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 800_u256);
    let deposited = deposit_as(collection, participant, id, 500_u256);
    assert(deposited == 200_u256, 'should clamp to remaining');
    assert(dispatcher.get_syndication(id).total_raised == 1000_u256, 'should hit target');
}

#[test]
fn test_deposit_reaching_target_completes() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    assert(dispatcher.get_syndication(id).status == Status::Completed, 'should be completed');
}

#[test]
#[should_panic(expected: 'Syndication not active')]
fn test_deposit_after_completion_panics() {
    let (owner, collection, token, participant) = setup();
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    deposit_as(collection, participant, id, 1_u256);
}

#[test]
#[should_panic(expected: 'Amount is zero')]
fn test_deposit_zero_panics() {
    let (owner, collection, token, participant) = setup();
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 0_u256);
}

#[test]
#[should_panic(expected: 'Not whitelisted')]
fn test_deposit_not_whitelisted_panics() {
    let (owner, collection, token, participant) = setup();
    let id = create_campaign(collection, owner, token, 1000_u256, true);
    deposit_as(collection, participant, id, 100_u256);
}

#[test]
fn test_deposit_whitelisted_succeeds() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, true);
    start_cheat_caller_address(collection, owner);
    dispatcher.set_whitelist(id, participant, true);
    stop_cheat_caller_address(collection);
    assert(dispatcher.is_whitelisted(id, participant), 'should be whitelisted');
    let deposited = deposit_as(collection, participant, id, 100_u256);
    assert(deposited == 100_u256, 'deposit should succeed');
}

// ──────────────── withdraw
// ────────────────

#[test]
fn test_withdraw_partial_returns_funds() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 400_u256);
    let balance_before = erc20.balance_of(participant);

    start_cheat_caller_address(collection, participant);
    dispatcher.withdraw(id, 150_u256);
    stop_cheat_caller_address(collection);

    assert(dispatcher.get_position(id, participant).deposited == 250_u256, 'wrong position');
    assert(dispatcher.get_syndication(id).total_raised == 250_u256, 'wrong total raised');
    assert(erc20.balance_of(participant) == balance_before + 150_u256, 'funds not returned');
}

#[test]
fn test_withdraw_full_then_redeposit() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 400_u256);

    start_cheat_caller_address(collection, participant);
    dispatcher.withdraw(id, 400_u256);
    stop_cheat_caller_address(collection);
    assert(dispatcher.get_syndication(id).total_raised == 0_u256, 'raised should be 0');

    let deposited = deposit_as(collection, participant, id, 100_u256);
    assert(deposited == 100_u256, 'redeposit should work');
}

#[test]
#[should_panic(expected: 'Insufficient deposit')]
fn test_withdraw_more_than_deposited_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 100_u256);
    start_cheat_caller_address(collection, participant);
    dispatcher.withdraw(id, 101_u256);
}

#[test]
#[should_panic(expected: 'Syndication not active')]
fn test_withdraw_after_completion_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    start_cheat_caller_address(collection, participant);
    dispatcher.withdraw(id, 100_u256);
}

#[test]
#[should_panic(expected: 'Syndication not active')]
fn test_withdraw_after_cancel_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 100_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_syndication(id);
    stop_cheat_caller_address(collection);
    start_cheat_caller_address(collection, participant);
    dispatcher.withdraw(id, 100_u256);
}

// ──────────────── cancel + refund
// ────────────────

#[test]
fn test_cancel_then_refund_full_position() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 600_u256);
    let balance_before = erc20.balance_of(participant);

    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_syndication(id);
    stop_cheat_caller_address(collection);
    assert(dispatcher.get_syndication(id).status == Status::Cancelled, 'should be cancelled');

    start_cheat_caller_address(collection, participant);
    let refunded = dispatcher.claim_refund(id);
    stop_cheat_caller_address(collection);

    assert(refunded == 600_u256, 'wrong refund');
    assert(erc20.balance_of(participant) == balance_before + 600_u256, 'funds not refunded');
    assert(dispatcher.get_position(id, participant).deposited == 0_u256, 'position not zeroed');
}

#[test]
#[should_panic(expected: 'No refund available')]
fn test_double_refund_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 600_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_syndication(id);
    stop_cheat_caller_address(collection);
    start_cheat_caller_address(collection, participant);
    dispatcher.claim_refund(id);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Syndication not cancelled')]
fn test_refund_while_active_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 600_u256);
    start_cheat_caller_address(collection, participant);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_cancel_non_owner_panics() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    start_cheat_caller_address(collection, OTHER());
    dispatcher.cancel_syndication(id);
}

#[test]
#[should_panic(expected: 'Syndication not active')]
fn test_cancel_completed_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_syndication(id);
}

// ──────────────── proceeds
// ────────────────

#[test]
fn test_claim_proceeds_pays_owner_once() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);

    start_cheat_caller_address(collection, owner);
    let amount = dispatcher.claim_proceeds(id);
    stop_cheat_caller_address(collection);

    assert(amount == 1000_u256, 'wrong proceeds');
    assert(erc20.balance_of(owner) == 1000_u256, 'owner not paid');
    assert(dispatcher.get_syndication(id).proceeds_claimed, 'not marked claimed');
}

#[test]
#[should_panic(expected: 'Proceeds already claimed')]
fn test_double_proceeds_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.claim_proceeds(id);
    dispatcher.claim_proceeds(id);
}

#[test]
#[should_panic(expected: 'Syndication not completed')]
fn test_proceeds_before_completion_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 500_u256);
    start_cheat_caller_address(collection, owner);
    dispatcher.claim_proceeds(id);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_proceeds_non_owner_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    start_cheat_caller_address(collection, participant);
    dispatcher.claim_proceeds(id);
}

// ──────────────── mint_shares
// ────────────────

#[test]
fn test_mint_shares_matches_deposits() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let erc1155 = IERC1155Dispatcher { contract_address: collection };
    let second = deploy_mock_account();
    fund_and_approve(token, second, collection, 1_000_000_u256);

    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 700_u256);
    deposit_as(collection, second, id, 300_u256);

    start_cheat_caller_address(collection, participant);
    dispatcher.mint_shares(id);
    stop_cheat_caller_address(collection);
    start_cheat_caller_address(collection, second);
    dispatcher.mint_shares(id);
    stop_cheat_caller_address(collection);

    assert(erc1155.balance_of(participant, id) == 700_u256, 'wrong shares 1');
    assert(erc1155.balance_of(second, id) == 300_u256, 'wrong shares 2');
}

#[test]
#[should_panic(expected: 'Shares already minted')]
fn test_double_mint_shares_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    start_cheat_caller_address(collection, participant);
    dispatcher.mint_shares(id);
    dispatcher.mint_shares(id);
}

#[test]
#[should_panic(expected: 'Not a participant')]
fn test_mint_shares_non_participant_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);
    let outsider = deploy_mock_account();
    start_cheat_caller_address(collection, outsider);
    dispatcher.mint_shares(id);
}

#[test]
#[should_panic(expected: 'Syndication not completed')]
fn test_mint_shares_before_completion_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    deposit_as(collection, participant, id, 500_u256);
    start_cheat_caller_address(collection, participant);
    dispatcher.mint_shares(id);
}

// ──────────────── whitelist management
// ────────────────

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_whitelist_non_owner_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, true);
    start_cheat_caller_address(collection, OTHER());
    dispatcher.set_whitelist(id, participant, true);
}

#[test]
#[should_panic(expected: 'Not a whitelist campaign')]
fn test_set_whitelist_on_public_campaign_panics() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    start_cheat_caller_address(collection, owner);
    dispatcher.set_whitelist(id, participant, true);
}

#[test]
fn test_whitelist_revoke() {
    let (owner, collection, token, participant) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, true);
    start_cheat_caller_address(collection, owner);
    dispatcher.set_whitelist(id, participant, true);
    dispatcher.set_whitelist(id, participant, false);
    stop_cheat_caller_address(collection);
    assert(!dispatcher.is_whitelisted(id, participant), 'should be revoked');
}

// ──────────────── security: malicious payment token
// ────────────────

#[test]
#[should_panic(expected: 'Payment failed')]
fn test_fee_on_transfer_token_rejected() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    let participant = deploy_mock_account();
    fund_and_approve(malicious, participant, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256, false);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::SHORT_TRANSFER_FROM, 0_u256);
    deposit_as(collection, participant, id, 100_u256);
}

#[test]
fn test_reentrant_deposit_keeps_accounting_exact() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    let participant = deploy_mock_account();
    fund_and_approve(malicious, participant, collection, 1_000_000_u256);
    // The token contract itself participates: it holds a balance and approves
    // the collection, then reenters deposit() from inside transfer_from.
    fund_and_approve(malicious, malicious, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256, false);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_DEPOSIT, 300_u256);
    // Cheat only the outer call so the nested reentrant deposit is attributed
    // to its real caller — the malicious token contract.
    cheat_caller_address(collection, participant, CheatSpan::TargetCalls(1));
    IIPSyndicationCollectionDispatcher { contract_address: collection }.deposit(id, 400_u256);

    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    assert(dispatcher.get_syndication(id).total_raised == 700_u256, 'wrong total raised');
    assert(dispatcher.get_position(id, participant).deposited == 400_u256, 'wrong outer pos');
    assert(dispatcher.get_position(id, malicious).deposited == 300_u256, 'wrong nested pos');
}

#[test]
#[should_panic(expected: 'Insufficient deposit')]
fn test_reentrant_withdraw_cannot_double_spend() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    fund_and_approve(malicious, malicious, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256, false);
    deposit_as(collection, malicious, id, 500_u256);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_WITHDRAW, 500_u256);
    start_cheat_caller_address(collection, malicious);
    IIPSyndicationCollectionDispatcher { contract_address: collection }.withdraw(id, 500_u256);
}

#[test]
#[should_panic(expected: 'No refund available')]
fn test_reentrant_refund_cannot_double_claim() {
    let (owner, collection, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    fund_and_approve(malicious, malicious, collection, 1_000_000_u256);
    let id = create_campaign(collection, owner, malicious, 1000_u256, false);
    deposit_as(collection, malicious, id, 500_u256);

    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.cancel_syndication(id);
    stop_cheat_caller_address(collection);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_REFUND, 0_u256);
    start_cheat_caller_address(collection, malicious);
    dispatcher.claim_refund(id);
}

#[test]
#[should_panic(expected: 'Proceeds already claimed')]
fn test_reentrant_proceeds_cannot_double_claim() {
    let (_, _, _, _) = setup();
    let malicious = deploy_malicious_erc20();
    // Owner is the malicious token itself so its transfer hook can reenter
    // claim_proceeds as the collection owner.
    let collection = deploy_collection_with_owner(malicious);
    let participant = deploy_mock_account();
    fund_and_approve(malicious, participant, collection, 1_000_000_u256);
    let id = create_campaign(collection, malicious, malicious, 1000_u256, false);
    deposit_as(collection, participant, id, 1000_u256);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(collection, id, MaliciousERC20::ATTACK_PROCEEDS, 0_u256);
    start_cheat_caller_address(collection, malicious);
    IIPSyndicationCollectionDispatcher { contract_address: collection }.claim_proceeds(id);
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

// ──────────────── views + royalty + discovery
// ────────────────

#[test]
fn test_collection_identity_views() {
    let (_, collection, _, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    assert(dispatcher.name() == "IP Syndications Test", 'wrong name');
    assert(dispatcher.symbol() == "SYND", 'wrong symbol');
    assert(dispatcher.base_uri() == "ipfs://QmCollectionMeta/", 'wrong base uri');
    assert(dispatcher.version() == "1.0.0", 'wrong version');
}

#[test]
fn test_royalty_info() {
    let (owner, collection, token, _) = setup();
    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    let id = create_campaign(collection, owner, token, 1000_u256, false);
    let (receiver, amount) = dispatcher.royalty_info(id, 20000_u256);
    assert(receiver == owner, 'royalty receiver not owner');
    assert(amount == 1000_u256, 'wrong royalty amount'); // 5% of 20000
}

#[test]
fn test_src5_interfaces_registered() {
    let (_, collection, _, _) = setup();
    let src5 = ISRC5Dispatcher { contract_address: collection };
    assert(src5.supports_interface(IIP_SYNDICATION_COLLECTION_ID), 'service id missing');
    assert(src5.supports_interface(IERC2981_ID), 'erc2981 id missing');
}
