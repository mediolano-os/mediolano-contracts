use ip_commission_escrow::interface::{
    IIPCommissionEscrowDispatcher, IIPCommissionEscrowDispatcherTrait, IIP_COMMISSION_ESCROW_ID,
};
use ip_commission_escrow::malicious_erc20::{
    IMaliciousERC20ConfigDispatcher, IMaliciousERC20ConfigDispatcherTrait,
};
use ip_commission_escrow::mock_erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_commission_escrow::types::{CommissionStatus, MilestoneStatus, OfferMode};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_block_timestamp, cheat_caller_address,
    declare,
};
use starknet::ContractAddress;

fn COMMISSIONER() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn CREATOR() -> ContractAddress {
    0x102.try_into().unwrap()
}

fn INVITED_CREATOR() -> ContractAddress {
    0x103.try_into().unwrap()
}

fn OTHER_CREATOR() -> ContractAddress {
    0x104.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn BRIEF_URI() -> ByteArray {
    "ipfs://commission-brief"
}

fn LICENSE_URI() -> ByteArray {
    "ipfs://commission-license"
}

fn DELIVERABLE_URI() -> ByteArray {
    "ar://commission-deliverable"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/brief.json"
}

fn ATTACK_CREATOR_CLAIM() -> u8 {
    1
}

fn ATTACK_REFUND() -> u8 {
    2
}

fn SHORT_TRANSFER_FROM() -> u8 {
    3
}

fn deploy_escrow() -> IIPCommissionEscrowDispatcher {
    let contract = declare("IPCommissionEscrow").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IIPCommissionEscrowDispatcher { contract_address }
}

fn deploy_erc20() -> IERC20Dispatcher {
    let contract = declare("MockERC20").unwrap().contract_class();
    let mut calldata = array![];
    let name: ByteArray = "Mock Token";
    let symbol: ByteArray = "MOCK";
    let supply: u256 = 0;
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    supply.serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IERC20Dispatcher { contract_address }
}

fn deploy_malicious_erc20() -> IERC20Dispatcher {
    let contract = declare("MaliciousERC20").unwrap().contract_class();
    let mut calldata = array![];
    let name: ByteArray = "Malicious Token";
    let symbol: ByteArray = "MAL";
    let supply: u256 = 0;
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    supply.serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IERC20Dispatcher { contract_address }
}

fn mint_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) {
    IERC20MintDispatcher { contract_address: token }.mint(recipient, amount);
}

fn approve(
    token: IERC20Dispatcher, owner: ContractAddress, spender: ContractAddress, amount: u256,
) {
    cheat_caller_address(token.contract_address, owner, CheatSpan::TargetCalls(1));
    token.approve(spender, amount);
}

fn setup() -> (IIPCommissionEscrowDispatcher, IERC20Dispatcher) {
    let escrow = deploy_escrow();
    let token = deploy_erc20();
    mint_erc20(token.contract_address, COMMISSIONER(), 1000000);
    approve(token, COMMISSIONER(), escrow.contract_address, 1000000);
    (escrow, token)
}

fn setup_with_malicious_token() -> (IIPCommissionEscrowDispatcher, IERC20Dispatcher) {
    let escrow = deploy_escrow();
    let token = deploy_malicious_erc20();
    mint_erc20(token.contract_address, COMMISSIONER(), 1000000);
    approve(token, COMMISSIONER(), escrow.contract_address, 1000000);
    (escrow, token)
}

fn configure_malicious_token(
    token: IERC20Dispatcher, escrow: IIPCommissionEscrowDispatcher, commission_id: u256, mode: u8,
) {
    IMaliciousERC20ConfigDispatcher { contract_address: token.contract_address }
        .configure_attack(escrow.contract_address, commission_id, mode);
}

fn create_open_commission(escrow: IIPCommissionEscrowDispatcher, token: IERC20Dispatcher) -> u256 {
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow
        .create_commission(
            ZERO(),
            token.contract_address,
            1000,
            BRIEF_URI(),
            111,
            LICENSE_URI(),
            222,
            1,
            999999,
            array![400, 600],
        )
}

fn fund(escrow: IIPCommissionEscrowDispatcher, commission_id: u256, commissioner: ContractAddress) {
    cheat_caller_address(escrow.contract_address, commissioner, CheatSpan::TargetCalls(1));
    escrow.fund_commission(commission_id);
}

fn accept(escrow: IIPCommissionEscrowDispatcher, commission_id: u256, creator: ContractAddress) {
    cheat_caller_address(escrow.contract_address, creator, CheatSpan::TargetCalls(1));
    escrow.accept_commission(commission_id);
}

fn submit(
    escrow: IIPCommissionEscrowDispatcher,
    commission_id: u256,
    milestone_index: u32,
    creator: ContractAddress,
) {
    cheat_caller_address(escrow.contract_address, creator, CheatSpan::TargetCalls(1));
    escrow.submit_milestone(commission_id, milestone_index, DELIVERABLE_URI(), 333);
}

#[test]
fn test_create_open_commission_mints_offer_asset() {
    let (escrow, token) = setup();

    let commission_id = create_open_commission(escrow, token);

    assert(commission_id == 1, 'commission id');
    assert(escrow.get_last_commission_id() == 1, 'last id');

    let commission = escrow.get_commission(commission_id);
    assert(commission.commissioner == COMMISSIONER(), 'commissioner');
    assert(commission.payment_token == token.contract_address, 'payment token');
    assert(commission.status == CommissionStatus::Open, 'open');
    assert(commission.mode == OfferMode::Open, 'mode');
    assert(commission.milestone_count == 2, 'milestone count');
    assert(commission.brief_uri == BRIEF_URI(), 'brief uri');
    assert(commission.license_uri == LICENSE_URI(), 'license uri');

    let milestone = escrow.get_milestone(commission_id, 0);
    assert(milestone.amount == 400, 'milestone amount');
    assert(milestone.status == MilestoneStatus::Pending, 'milestone pending');

    let erc721 = IERC721Dispatcher { contract_address: escrow.contract_address };
    assert(erc721.owner_of(commission_id) == COMMISSIONER(), 'offer owner');
}

#[test]
fn test_token_uri_and_src5() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    let metadata = IERC721MetadataDispatcher { contract_address: escrow.contract_address };
    let src5 = ISRC5Dispatcher { contract_address: escrow.contract_address };

    assert(metadata.token_uri(commission_id) == BRIEF_URI(), 'token uri');
    assert(src5.supports_interface(IIP_COMMISSION_ESCROW_ID), 'service interface');
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_rejects_http_brief_uri() {
    let (escrow, token) = setup();

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow
        .create_commission(
            ZERO(),
            token.contract_address,
            1000,
            HTTP_URI(),
            111,
            LICENSE_URI(),
            222,
            1,
            999999,
            array![1000],
        );
}

#[test]
#[should_panic(expected: 'Invalid milestones')]
fn test_create_rejects_milestone_sum_mismatch() {
    let (escrow, token) = setup();

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow
        .create_commission(
            ZERO(),
            token.contract_address,
            1000,
            BRIEF_URI(),
            111,
            LICENSE_URI(),
            222,
            1,
            999999,
            array![300, 600],
        );
}

#[test]
#[should_panic(expected: 'Deadline expired')]
fn test_create_rejects_expired_deadline() {
    let (escrow, token) = setup();

    cheat_block_timestamp(escrow.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow
        .create_commission(
            ZERO(),
            token.contract_address,
            1000,
            BRIEF_URI(),
            111,
            LICENSE_URI(),
            222,
            1,
            1000,
            array![1000],
        );
}

#[test]
fn test_fund_commission_exact_escrow() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);

    let before = token.balance_of(COMMISSIONER());
    fund(escrow, commission_id, COMMISSIONER());

    let commission = escrow.get_commission(commission_id);
    assert(commission.status == CommissionStatus::Funded, 'funded');
    assert(commission.escrowed_amount == 1000, 'escrowed');
    assert(token.balance_of(COMMISSIONER()) == before - 1000, 'commissioner balance');
    assert(token.balance_of(escrow.contract_address) == 1000, 'escrow balance');
}

#[test]
#[should_panic(expected: 'Payment failed')]
fn test_fund_commission_rejects_short_erc20_receipt() {
    let (escrow, token) = setup_with_malicious_token();
    let commission_id = create_open_commission(escrow, token);
    configure_malicious_token(token, escrow, commission_id, SHORT_TRANSFER_FROM());

    fund(escrow, commission_id, COMMISSIONER());
}

#[test]
#[should_panic(expected: 'Deadline expired')]
fn test_accept_rejects_expired_offer() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    accept(escrow, commission_id, CREATOR());
}

#[test]
fn test_open_commission_accept_submit_approve_and_claim() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.approve_milestone(commission_id, 0);

    assert(escrow.get_claimable_creator_funds(commission_id, CREATOR()) == 400, 'claimable');

    let before = token.balance_of(CREATOR());
    cheat_caller_address(escrow.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let claimed = escrow.claim_creator_funds(commission_id);

    assert(claimed == 400, 'claimed');
    assert(token.balance_of(CREATOR()) == before + 400, 'creator paid');
    assert(escrow.get_claimable_creator_funds(commission_id, CREATOR()) == 0, 'claim consumed');
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_claim_creator_funds_blocks_reentrant_token_callback() {
    let (escrow, token) = setup_with_malicious_token();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.approve_milestone(commission_id, 0);
    configure_malicious_token(token, escrow, commission_id, ATTACK_CREATOR_CLAIM());

    cheat_caller_address(escrow.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    escrow.claim_creator_funds(commission_id);
}

#[test]
#[should_panic(expected: 'Deadline expired')]
fn test_submit_rejects_after_deadline() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    submit(escrow, commission_id, 0, CREATOR());
}

#[test]
fn test_completion_after_all_milestones_approved() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.approve_milestone(commission_id, 0);

    submit(escrow, commission_id, 1, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.approve_milestone(commission_id, 1);

    let commission = escrow.get_commission(commission_id);
    assert(commission.status == CommissionStatus::Completed, 'completed');
    assert(commission.released_amount == 1000, 'released');
    assert(commission.approved_milestone_count == 2, 'approved count');
}

#[test]
fn test_expired_in_progress_cancellation_refunds_unreleased_amount() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.approve_milestone(commission_id, 0);

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.cancel_commission(commission_id);

    let commission = escrow.get_commission(commission_id);
    assert(commission.status == CommissionStatus::Cancelled, 'cancelled');
    assert(commission.released_amount == 400, 'released preserved');
    assert(commission.refunded_amount == 600, 'unreleased refund');
    assert(escrow.get_claimable_creator_funds(commission_id, CREATOR()) == 400, 'creator claim');
    assert(
        escrow.get_claimable_commissioner_refund(commission_id, COMMISSIONER()) == 600,
        'commissioner refund',
    );

    let commissioner_before = token.balance_of(COMMISSIONER());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.claim_commissioner_refund(commission_id);
    assert(token.balance_of(COMMISSIONER()) == commissioner_before + 600, 'commissioner paid');

    let creator_before = token.balance_of(CREATOR());
    cheat_caller_address(escrow.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    escrow.claim_creator_funds(commission_id);
    assert(token.balance_of(CREATOR()) == creator_before + 400, 'creator paid');
}

#[test]
#[should_panic(expected: 'Previous milestone open')]
fn test_submit_requires_previous_milestone_approved() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 1, CREATOR());
}

#[test]
fn test_revision_flow() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.request_revision(commission_id, 0);

    let milestone = escrow.get_milestone(commission_id, 0);
    assert(milestone.status == MilestoneStatus::RevisionRequested, 'revision requested');
    assert(milestone.revision_count == 1, 'revision count');

    submit(escrow, commission_id, 0, CREATOR());
    assert(escrow.get_milestone_deliverable_uri(commission_id, 0) == DELIVERABLE_URI(), 'uri');
}

#[test]
#[should_panic(expected: 'Revision limit reached')]
fn test_revision_limit_enforced() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.request_revision(commission_id, 0);
    submit(escrow, commission_id, 0, CREATOR());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.request_revision(commission_id, 0);
}

#[test]
fn test_exclusive_commission_accepts_invited_creator() {
    let (escrow, token) = setup();

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    let commission_id = escrow
        .create_commission(
            INVITED_CREATOR(),
            token.contract_address,
            1000,
            BRIEF_URI(),
            111,
            LICENSE_URI(),
            222,
            1,
            999999,
            array![1000],
        );

    assert(escrow.get_commission(commission_id).mode == OfferMode::Exclusive, 'exclusive');
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, INVITED_CREATOR());
    assert(escrow.get_commission(commission_id).creator == INVITED_CREATOR(), 'accepted creator');
}

#[test]
#[should_panic(expected: 'Not invited creator')]
fn test_exclusive_commission_rejects_other_creator() {
    let (escrow, token) = setup();

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    let commission_id = escrow
        .create_commission(
            INVITED_CREATOR(),
            token.contract_address,
            1000,
            BRIEF_URI(),
            111,
            LICENSE_URI(),
            222,
            1,
            999999,
            array![1000],
        );
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, OTHER_CREATOR());
}

#[test]
fn test_cancel_funded_commission_and_claim_refund() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.cancel_commission(commission_id);

    assert(
        escrow.get_claimable_commissioner_refund(commission_id, COMMISSIONER()) == 1000, 'refund',
    );
    let before = token.balance_of(COMMISSIONER());
    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    let refund = escrow.claim_commissioner_refund(commission_id);

    assert(refund == 1000, 'refund amount');
    assert(token.balance_of(COMMISSIONER()) == before + 1000, 'refunded balance');
    assert(escrow.get_commission(commission_id).status == CommissionStatus::Cancelled, 'cancelled');
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_claim_commissioner_refund_blocks_reentrant_token_callback() {
    let (escrow, token) = setup_with_malicious_token();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.cancel_commission(commission_id);
    configure_malicious_token(token, escrow, commission_id, ATTACK_REFUND());

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.claim_commissioner_refund(commission_id);
}

#[test]
#[should_panic(expected: 'Invalid status')]
fn test_cannot_cancel_in_progress_commission() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    fund(escrow, commission_id, COMMISSIONER());
    accept(escrow, commission_id, CREATOR());

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    escrow.cancel_commission(commission_id);
}

#[test]
#[should_panic(expected: 'Offer asset non-transferable')]
fn test_offer_asset_is_non_transferable() {
    let (escrow, token) = setup();
    let commission_id = create_open_commission(escrow, token);
    let erc721 = IERC721Dispatcher { contract_address: escrow.contract_address };

    cheat_caller_address(escrow.contract_address, COMMISSIONER(), CheatSpan::TargetCalls(1));
    erc721.transfer_from(COMMISSIONER(), OTHER_CREATOR(), commission_id);
}

#[test]
#[should_panic(expected: 'Commission not found')]
fn test_missing_commission_reverts() {
    let (escrow, _) = setup();

    escrow.get_commission(1);
}
