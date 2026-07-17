use ip_commission_escrow::interface::{
    IIPCommissionEscrowDispatcher, IIPCommissionEscrowDispatcherTrait, IIP_COMMISSION_ESCROW_ID,
};
use ip_commission_escrow::mock::malicious_erc20::{
    IMaliciousERC20ConfigDispatcher, IMaliciousERC20ConfigDispatcherTrait, MaliciousERC20,
};
use ip_commission_escrow::mock::mock_erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_commission_escrow::types::{CommissionStatus, MilestoneStatus};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

const DEADLINE: u64 = 10_000;
const REVIEW_PERIOD: u64 = 100;

fn OTHER() -> ContractAddress {
    0x333.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
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

fn deploy_escrow() -> ContractAddress {
    let class = declare("IPCommissionEscrow").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
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

/// escrow + token + funded commissioner + creator accounts.
fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let escrow = deploy_escrow();
    let token = deploy_erc20();
    let commissioner = deploy_mock_account();
    let creator = deploy_mock_account();
    fund_and_approve(token, commissioner, escrow, 1_000_000_u256);
    (escrow, token, commissioner, creator)
}

fn create_as(
    escrow: ContractAddress,
    commissioner: ContractAddress,
    token: ContractAddress,
    invited: ContractAddress,
) -> u256 {
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, commissioner);
    let id = dispatcher
        .create_commission(
            invited,
            token,
            "ipfs://QmBrief",
            1_u32,
            DEADLINE,
            REVIEW_PERIOD,
            array![600_u256, 400_u256],
        );
    stop_cheat_caller_address(escrow);
    id
}

fn accept_as(escrow: ContractAddress, creator: ContractAddress, id: u256) {
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, creator);
    dispatcher.accept_commission(id);
    stop_cheat_caller_address(escrow);
}

fn submit_as(escrow: ContractAddress, creator: ContractAddress, id: u256, index: u32) {
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, creator);
    dispatcher.submit_milestone(id, index, "ipfs://QmWork");
    stop_cheat_caller_address(escrow);
}

fn approve_as(escrow: ContractAddress, commissioner: ContractAddress, id: u256, index: u32) {
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.approve_milestone(id, index);
    stop_cheat_caller_address(escrow);
}

// ──────────────── create_commission
// ────────────────

#[test]
fn test_create_escrows_and_mints_offer() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let erc721 = IERC721Dispatcher { contract_address: escrow };

    let id = create_as(escrow, commissioner, token, ZERO());
    assert(id == 1_u256, 'first id should be 1');
    assert(dispatcher.commission_count() == 1_u256, 'count should be 1');
    assert(erc20.balance_of(escrow) == 1000_u256, 'escrow should hold budget');
    assert(erc721.owner_of(id) == commissioner, 'offer should go to owner');

    let c = dispatcher.get_commission(id);
    assert(c.commissioner == commissioner, 'wrong commissioner');
    assert(c.total_amount == 1000_u256, 'wrong total');
    assert(c.milestone_count == 2_u32, 'wrong milestone count');
    assert(c.status == CommissionStatus::Open, 'should be open');

    let m0 = dispatcher.get_milestone(id, 0);
    assert(m0.amount == 600_u256, 'wrong m0 amount');
    assert(m0.status == MilestoneStatus::Pending, 'm0 should be pending');
    let m1 = dispatcher.get_milestone(id, 1);
    assert(m1.amount == 400_u256, 'wrong m1 amount');
}

#[test]
#[should_panic(expected: 'Payment token is zero')]
fn test_create_zero_token_panics() {
    let (escrow, _, commissioner, _) = setup();
    create_as(escrow, commissioner, ZERO(), ZERO());
}

#[test]
#[should_panic(expected: 'Deadline in the past')]
fn test_create_past_deadline_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_block_timestamp(escrow, DEADLINE + 1);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher
        .create_commission(
            ZERO(), token, "ipfs://QmBrief", 1_u32, DEADLINE, REVIEW_PERIOD, array![100_u256],
        );
}

#[test]
#[should_panic(expected: 'Review period is zero')]
fn test_create_zero_review_period_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, commissioner);
    dispatcher
        .create_commission(ZERO(), token, "ipfs://QmBrief", 1_u32, DEADLINE, 0, array![100_u256]);
}

#[test]
#[should_panic(expected: 'Invited is commissioner')]
fn test_create_self_invite_panics() {
    let (escrow, token, commissioner, _) = setup();
    create_as(escrow, commissioner, token, commissioner);
}

#[test]
#[should_panic(expected: 'No milestones')]
fn test_create_no_milestones_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, commissioner);
    dispatcher
        .create_commission(
            ZERO(), token, "ipfs://QmBrief", 1_u32, DEADLINE, REVIEW_PERIOD, array![],
        );
}

#[test]
#[should_panic(expected: 'Milestone amount is zero')]
fn test_create_zero_milestone_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, commissioner);
    dispatcher
        .create_commission(
            ZERO(),
            token,
            "ipfs://QmBrief",
            1_u32,
            DEADLINE,
            REVIEW_PERIOD,
            array![100_u256, 0_u256],
        );
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_bad_uri_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    start_cheat_caller_address(escrow, commissioner);
    dispatcher
        .create_commission(
            ZERO(), token, "https://example.com", 1_u32, DEADLINE, REVIEW_PERIOD, array![100_u256],
        );
}

#[test]
#[should_panic(expected: 'Payment failed')]
fn test_fee_on_transfer_token_rejected() {
    let escrow = deploy_escrow();
    let malicious = deploy_malicious_erc20();
    let commissioner = deploy_mock_account();
    fund_and_approve(malicious, commissioner, escrow, 1_000_000_u256);
    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(escrow, 0_u256, MaliciousERC20::SHORT_TRANSFER_FROM);
    create_as(escrow, commissioner, malicious, ZERO());
}

// ──────────────── accept
// ────────────────

#[test]
fn test_accept_open_offer() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    let c = dispatcher.get_commission(id);
    assert(c.creator == creator, 'wrong creator');
    assert(c.status == CommissionStatus::InProgress, 'should be in progress');
}

#[test]
#[should_panic(expected: 'Not the invited creator')]
fn test_accept_invited_by_other_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, creator);
    accept_as(escrow, OTHER(), id);
}

#[test]
fn test_accept_invited_by_invitee() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, creator);
    accept_as(escrow, creator, id);
    assert(dispatcher.get_commission(id).creator == creator, 'invitee should accept');
}

#[test]
#[should_panic(expected: 'Commissioner cannot accept')]
fn test_accept_by_commissioner_panics() {
    let (escrow, token, commissioner, _) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, commissioner, id);
}

#[test]
#[should_panic(expected: 'Deadline passed')]
fn test_accept_after_deadline_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    start_cheat_block_timestamp(escrow, DEADLINE + 1);
    accept_as(escrow, creator, id);
}

#[test]
#[should_panic(expected: 'Commission not open')]
fn test_double_accept_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    accept_as(escrow, OTHER(), id);
}

// ──────────────── milestones
// ────────────────

#[test]
fn test_submit_and_approve_flow() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);

    submit_as(escrow, creator, id, 0);
    let m0 = dispatcher.get_milestone(id, 0);
    assert(m0.status == MilestoneStatus::Submitted, 'm0 should be submitted');
    assert(m0.deliverable_uri == "ipfs://QmWork", 'wrong deliverable');

    approve_as(escrow, commissioner, id, 0);
    let c = dispatcher.get_commission(id);
    assert(c.released_amount == 600_u256, 'wrong released');
    assert(c.creator_claim == 600_u256, 'wrong claim');
    assert(c.approved_milestone_count == 1_u32, 'wrong approved count');
    assert(c.status == CommissionStatus::InProgress, 'still in progress');

    submit_as(escrow, creator, id, 1);
    approve_as(escrow, commissioner, id, 1);
    let c = dispatcher.get_commission(id);
    assert(c.status == CommissionStatus::Completed, 'should be completed');
    assert(c.creator_claim == 1000_u256, 'full claim');
}

#[test]
#[should_panic(expected: 'Previous milestone open')]
fn test_submit_out_of_order_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 1);
}

#[test]
#[should_panic(expected: 'Not the creator')]
fn test_submit_by_other_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, OTHER(), id, 0);
}

#[test]
#[should_panic(expected: 'Deadline passed')]
fn test_submit_after_deadline_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    start_cheat_block_timestamp(escrow, DEADLINE + 1);
    submit_as(escrow, creator, id, 0);
}

#[test]
#[should_panic(expected: 'Not the commissioner')]
fn test_approve_by_other_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    approve_as(escrow, OTHER(), id, 0);
}

#[test]
#[should_panic(expected: 'Milestone not under review')]
fn test_approve_pending_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    approve_as(escrow, commissioner, id, 0);
}

#[test]
fn test_revision_and_resubmit() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);

    start_cheat_caller_address(escrow, commissioner);
    dispatcher.request_revision(id, 0);
    stop_cheat_caller_address(escrow);
    let m0 = dispatcher.get_milestone(id, 0);
    assert(m0.status == MilestoneStatus::RevisionRequested, 'should need revision');
    assert(m0.revision_count == 1_u32, 'wrong revision count');

    submit_as(escrow, creator, id, 0);
    approve_as(escrow, commissioner, id, 0);
}

#[test]
#[should_panic(expected: 'Revision limit reached')]
fn test_revision_limit_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.request_revision(id, 0);
    stop_cheat_caller_address(escrow);
    submit_as(escrow, creator, id, 0);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.request_revision(id, 0);
}

// ──────────────── the silence remedy
// ────────────────

#[test]
fn test_overdue_milestone_claimable_by_creator() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);

    start_cheat_block_timestamp(escrow, 1000);
    submit_as(escrow, creator, id, 0);
    start_cheat_block_timestamp(escrow, 1000 + REVIEW_PERIOD + 1);

    start_cheat_caller_address(escrow, creator);
    dispatcher.claim_overdue_milestone(id, 0);
    stop_cheat_caller_address(escrow);

    let c = dispatcher.get_commission(id);
    assert(c.creator_claim == 600_u256, 'timeout should credit');
    assert(c.approved_milestone_count == 1_u32, 'timeout should approve');
}

#[test]
#[should_panic(expected: 'Review window still open')]
fn test_overdue_claim_too_early_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    start_cheat_block_timestamp(escrow, 1000);
    submit_as(escrow, creator, id, 0);
    start_cheat_block_timestamp(escrow, 1000 + REVIEW_PERIOD);
    start_cheat_caller_address(escrow, creator);
    dispatcher.claim_overdue_milestone(id, 0);
}

#[test]
fn test_timeout_on_last_milestone_completes() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    approve_as(escrow, commissioner, id, 0);

    start_cheat_block_timestamp(escrow, 2000);
    submit_as(escrow, creator, id, 1);
    start_cheat_block_timestamp(escrow, 2000 + REVIEW_PERIOD + 1);
    start_cheat_caller_address(escrow, creator);
    dispatcher.claim_overdue_milestone(id, 1);
    stop_cheat_caller_address(escrow);

    assert(
        dispatcher.get_commission(id).status == CommissionStatus::Completed,
        'timeout should complete',
    );
}

#[test]
#[should_panic(expected: 'Not the creator')]
fn test_overdue_claim_by_other_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    start_cheat_block_timestamp(escrow, REVIEW_PERIOD + 1000);
    start_cheat_caller_address(escrow, OTHER());
    dispatcher.claim_overdue_milestone(id, 0);
}

// ──────────────── cancel fairness
// ────────────────

#[test]
fn test_cancel_open_refunds_all() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let erc20 = IERC20Dispatcher { contract_address: token };
    let id = create_as(escrow, commissioner, token, ZERO());

    start_cheat_caller_address(escrow, commissioner);
    dispatcher.cancel_commission(id);
    let refunded = dispatcher.claim_commissioner_refund(id);
    stop_cheat_caller_address(escrow);

    assert(refunded == 1000_u256, 'full refund');
    assert(erc20.balance_of(escrow) == 0_u256, 'escrow should be empty');
    assert(dispatcher.get_commission(id).status == CommissionStatus::Cancelled, 'cancelled');
}

#[test]
#[should_panic(expected: 'Deadline not passed')]
fn test_cancel_in_progress_before_deadline_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.cancel_commission(id);
}

#[test]
#[should_panic(expected: 'Milestone under review')]
fn test_cancel_with_submitted_milestone_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    start_cheat_block_timestamp(escrow, DEADLINE + 1);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.cancel_commission(id);
}

#[test]
fn test_cancel_after_deadline_keeps_earned() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    approve_as(escrow, commissioner, id, 0);

    start_cheat_block_timestamp(escrow, DEADLINE + 1);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.cancel_commission(id);
    let refunded = dispatcher.claim_commissioner_refund(id);
    stop_cheat_caller_address(escrow);
    assert(refunded == 400_u256, 'refund only unreleased');

    start_cheat_caller_address(escrow, creator);
    let claimed = dispatcher.claim_creator_funds(id);
    stop_cheat_caller_address(escrow);
    assert(claimed == 600_u256, 'earned stays claimable');
}

#[test]
#[should_panic(expected: 'Commission not cancellable')]
fn test_cancel_completed_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    approve_as(escrow, commissioner, id, 0);
    submit_as(escrow, creator, id, 1);
    approve_as(escrow, commissioner, id, 1);
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.cancel_commission(id);
}

#[test]
fn test_abandon_by_creator() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    approve_as(escrow, commissioner, id, 0);

    start_cheat_caller_address(escrow, creator);
    dispatcher.abandon_commission(id);
    let claimed = dispatcher.claim_creator_funds(id);
    stop_cheat_caller_address(escrow);
    assert(claimed == 600_u256, 'earned stays claimable');
    assert(dispatcher.get_commission(id).status == CommissionStatus::Cancelled, 'cancelled');

    start_cheat_caller_address(escrow, commissioner);
    let refunded = dispatcher.claim_commissioner_refund(id);
    stop_cheat_caller_address(escrow);
    assert(refunded == 400_u256, 'unearned refunded');
}

#[test]
#[should_panic(expected: 'Not the creator')]
fn test_abandon_by_other_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    start_cheat_caller_address(escrow, OTHER());
    dispatcher.abandon_commission(id);
}

// ──────────────── claims
// ────────────────

#[test]
#[should_panic(expected: 'Nothing to claim')]
fn test_double_creator_claim_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    accept_as(escrow, creator, id);
    submit_as(escrow, creator, id, 0);
    approve_as(escrow, commissioner, id, 0);
    start_cheat_caller_address(escrow, creator);
    dispatcher.claim_creator_funds(id);
    dispatcher.claim_creator_funds(id);
}

#[test]
#[should_panic(expected: 'Nothing to claim')]
fn test_double_refund_claim_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    start_cheat_caller_address(escrow, commissioner);
    dispatcher.cancel_commission(id);
    dispatcher.claim_commissioner_refund(id);
    dispatcher.claim_commissioner_refund(id);
}

#[test]
#[should_panic(expected: 'Nothing to claim')]
fn test_reentrant_creator_claim_cannot_double_spend() {
    let escrow = deploy_escrow();
    let malicious = deploy_malicious_erc20();
    let commissioner = deploy_mock_account();
    fund_and_approve(malicious, commissioner, escrow, 1_000_000_u256);
    let id = create_as(escrow, commissioner, malicious, ZERO());
    // The malicious token contract is the creator so its transfer hook can
    // reenter claim_creator_funds.
    accept_as(escrow, malicious, id);
    submit_as(escrow, malicious, id, 0);
    approve_as(escrow, commissioner, id, 0);

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(escrow, id, MaliciousERC20::ATTACK_CREATOR_CLAIM);
    start_cheat_caller_address(escrow, malicious);
    IIPCommissionEscrowDispatcher { contract_address: escrow }.claim_creator_funds(id);
}

#[test]
#[should_panic(expected: 'Nothing to claim')]
fn test_reentrant_refund_claim_cannot_double_spend() {
    let escrow = deploy_escrow();
    let malicious = deploy_malicious_erc20();
    // The malicious token contract is the commissioner so its transfer hook
    // can reenter claim_commissioner_refund.
    fund_and_approve(malicious, malicious, escrow, 1_000_000_u256);
    let id = create_as(escrow, malicious, malicious, ZERO());

    IMaliciousERC20ConfigDispatcher { contract_address: malicious }
        .configure_attack(escrow, id, MaliciousERC20::ATTACK_COMMISSIONER_REFUND);
    start_cheat_caller_address(escrow, malicious);
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    dispatcher.cancel_commission(id);
    dispatcher.claim_commissioner_refund(id);
}

// ──────────────── offer NFT + views + discovery
// ────────────────

#[test]
#[should_panic(expected: 'Offer is non-transferable')]
fn test_offer_transfer_panics() {
    let (escrow, token, commissioner, creator) = setup();
    let erc721 = IERC721Dispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    start_cheat_caller_address(escrow, commissioner);
    erc721.transfer_from(commissioner, creator, id);
}

#[test]
fn test_offer_metadata() {
    let (escrow, token, commissioner, _) = setup();
    let metadata = IERC721MetadataDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    assert(metadata.token_uri(id) == "ipfs://QmBrief", 'wrong token uri');
    assert(metadata.name() == "Mediolano Commission Offer", 'wrong name');
    assert(metadata.symbol() == "MCOM", 'wrong symbol');
}

#[test]
fn test_version_and_src5() {
    let (escrow, _, _, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    assert(dispatcher.version() == "1.0.0", 'wrong version');
    let src5 = ISRC5Dispatcher { contract_address: escrow };
    assert(src5.supports_interface(IIP_COMMISSION_ESCROW_ID), 'service id missing');
}

#[test]
#[should_panic(expected: 'Commission not found')]
fn test_get_unknown_commission_panics() {
    let (escrow, _, _, _) = setup();
    IIPCommissionEscrowDispatcher { contract_address: escrow }.get_commission(42_u256);
}

#[test]
#[should_panic(expected: 'Milestone not found')]
fn test_get_unknown_milestone_panics() {
    let (escrow, token, commissioner, _) = setup();
    let dispatcher = IIPCommissionEscrowDispatcher { contract_address: escrow };
    let id = create_as(escrow, commissioner, token, ZERO());
    dispatcher.get_milestone(id, 5_u32);
}
