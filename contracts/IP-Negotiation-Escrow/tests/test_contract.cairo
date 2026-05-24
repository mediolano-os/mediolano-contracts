use ip_negotiation_escrow::interface::{
    IIPNegotiationEscrowDispatcher, IIPNegotiationEscrowDispatcherTrait, IIP_NEGOTIATION_ESCROW_ID,
};
use ip_negotiation_escrow::malicious_erc20::{
    IMaliciousERC20ConfigDispatcher, IMaliciousERC20ConfigDispatcherTrait,
};
use ip_negotiation_escrow::mock_erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_negotiation_escrow::types::NegotiationStatus;
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

fn SELLER() -> ContractAddress {
    0x201.try_into().unwrap()
}

fn BUYER() -> ContractAddress {
    0x202.try_into().unwrap()
}

fn OTHER_BUYER() -> ContractAddress {
    0x203.try_into().unwrap()
}

fn IP_ASSET() -> ContractAddress {
    0x204.try_into().unwrap()
}

fn LISTING_URI() -> ByteArray {
    "ipfs://negotiation-listing"
}

fn TERMS_URI() -> ByteArray {
    "ipfs://negotiation-terms"
}

fn FULFILLMENT_URI() -> ByteArray {
    "ar://negotiation-fulfillment"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/terms.json"
}

fn ATTACK_SELLER_CLAIM() -> u8 {
    1
}

fn ATTACK_BUYER_REFUND() -> u8 {
    2
}

fn SHORT_TRANSFER_FROM() -> u8 {
    3
}

fn deploy_escrow() -> IIPNegotiationEscrowDispatcher {
    let contract = declare("IPNegotiationEscrow").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IIPNegotiationEscrowDispatcher { contract_address }
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

fn setup() -> (IIPNegotiationEscrowDispatcher, IERC20Dispatcher) {
    let escrow = deploy_escrow();
    let token = deploy_erc20();
    mint_erc20(token.contract_address, BUYER(), 1000000);
    approve(token, BUYER(), escrow.contract_address, 1000000);
    (escrow, token)
}

fn setup_with_malicious_token() -> (IIPNegotiationEscrowDispatcher, IERC20Dispatcher) {
    let escrow = deploy_escrow();
    let token = deploy_malicious_erc20();
    mint_erc20(token.contract_address, BUYER(), 1000000);
    approve(token, BUYER(), escrow.contract_address, 1000000);
    (escrow, token)
}

fn configure_malicious_token(
    token: IERC20Dispatcher, escrow: IIPNegotiationEscrowDispatcher, negotiation_id: u256, mode: u8,
) {
    IMaliciousERC20ConfigDispatcher { contract_address: token.contract_address }
        .configure_attack(escrow.contract_address, negotiation_id, mode);
}

fn create_listing(escrow: IIPNegotiationEscrowDispatcher, token: IERC20Dispatcher) -> u256 {
    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow
        .create_listing(
            IP_ASSET(),
            77,
            token.contract_address,
            1000,
            LISTING_URI(),
            111,
            TERMS_URI(),
            222,
            999999,
        )
}

fn fund(escrow: IIPNegotiationEscrowDispatcher, negotiation_id: u256, buyer: ContractAddress) {
    cheat_caller_address(escrow.contract_address, buyer, CheatSpan::TargetCalls(1));
    escrow.fund_listing(negotiation_id);
}

fn submit_fulfillment(escrow: IIPNegotiationEscrowDispatcher, negotiation_id: u256) {
    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow.submit_fulfillment(negotiation_id, FULFILLMENT_URI(), 333);
}

fn approve_fulfillment(escrow: IIPNegotiationEscrowDispatcher, negotiation_id: u256) {
    cheat_caller_address(escrow.contract_address, BUYER(), CheatSpan::TargetCalls(1));
    escrow.approve_fulfillment(negotiation_id);
}

#[test]
fn test_create_listing_mints_non_transferable_listing_asset() {
    let (escrow, token) = setup();

    let negotiation_id = create_listing(escrow, token);

    assert(negotiation_id == 1, 'negotiation id');
    assert(escrow.get_last_negotiation_id() == 1, 'last id');

    let negotiation = escrow.get_negotiation(negotiation_id);
    assert(negotiation.seller == SELLER(), 'seller');
    assert(negotiation.payment_token == token.contract_address, 'payment token');
    assert(negotiation.ip_asset_contract == IP_ASSET(), 'asset contract');
    assert(negotiation.ip_token_id == 77, 'asset token');
    assert(negotiation.status == NegotiationStatus::Open, 'open');
    assert(negotiation.listing_uri == LISTING_URI(), 'listing uri');
    assert(negotiation.terms_uri == TERMS_URI(), 'terms uri');

    let erc721 = IERC721Dispatcher { contract_address: escrow.contract_address };
    assert(erc721.owner_of(negotiation_id) == SELLER(), 'asset owner');

    let by_asset = escrow.get_negotiation_by_asset(IP_ASSET(), 77);
    assert(by_asset.negotiation_id == negotiation_id, 'asset lookup');
}

#[test]
fn test_token_uri_and_src5() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    let metadata = IERC721MetadataDispatcher { contract_address: escrow.contract_address };
    let src5 = ISRC5Dispatcher { contract_address: escrow.contract_address };

    assert(metadata.token_uri(negotiation_id) == LISTING_URI(), 'token uri');
    assert(src5.supports_interface(IIP_NEGOTIATION_ESCROW_ID), 'service interface');
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_rejects_http_listing_uri() {
    let (escrow, token) = setup();

    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow
        .create_listing(
            IP_ASSET(), 77, token.contract_address, 1000, HTTP_URI(), 111, TERMS_URI(), 222, 999999,
        );
}

#[test]
#[should_panic(expected: 'Deadline expired')]
fn test_create_rejects_expired_deadline() {
    let (escrow, token) = setup();

    cheat_block_timestamp(escrow.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow
        .create_listing(
            IP_ASSET(),
            77,
            token.contract_address,
            1000,
            LISTING_URI(),
            111,
            TERMS_URI(),
            222,
            1000,
        );
}

#[test]
#[should_panic(expected: 'Active listing exists')]
fn test_create_rejects_duplicate_active_listing_for_asset() {
    let (escrow, token) = setup();
    create_listing(escrow, token);

    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow
        .create_listing(
            IP_ASSET(),
            77,
            token.contract_address,
            1000,
            LISTING_URI(),
            111,
            TERMS_URI(),
            222,
            999999,
        );
}

#[test]
fn test_seller_can_cancel_open_listing_and_relist_asset() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);

    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow.cancel_listing(negotiation_id);

    assert(
        escrow.get_negotiation(negotiation_id).status == NegotiationStatus::Cancelled, 'cancelled',
    );

    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    let relisted_id = escrow
        .create_listing(
            IP_ASSET(),
            77,
            token.contract_address,
            1000,
            LISTING_URI(),
            111,
            TERMS_URI(),
            222,
            999999,
        );
    assert(relisted_id == 2, 'relisted');
}

#[test]
fn test_fund_listing_exact_escrow() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);

    let before = token.balance_of(BUYER());
    fund(escrow, negotiation_id, BUYER());

    let negotiation = escrow.get_negotiation(negotiation_id);
    assert(negotiation.buyer == BUYER(), 'buyer');
    assert(negotiation.status == NegotiationStatus::Funded, 'funded');
    assert(negotiation.escrowed_amount == 1000, 'escrowed');
    assert(token.balance_of(BUYER()) == before - 1000, 'buyer balance');
    assert(token.balance_of(escrow.contract_address) == 1000, 'escrow balance');
}

#[test]
#[should_panic(expected: 'Invalid buyer')]
fn test_seller_cannot_fund_own_listing() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    approve(token, SELLER(), escrow.contract_address, 1000);

    fund(escrow, negotiation_id, SELLER());
}

#[test]
#[should_panic(expected: 'Deadline expired')]
fn test_fund_rejects_expired_listing() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    fund(escrow, negotiation_id, BUYER());
}

#[test]
#[should_panic(expected: 'Payment failed')]
fn test_fund_rejects_short_erc20_receipt() {
    let (escrow, token) = setup_with_malicious_token();
    let negotiation_id = create_listing(escrow, token);
    configure_malicious_token(token, escrow, negotiation_id, SHORT_TRANSFER_FROM());

    fund(escrow, negotiation_id, BUYER());
}

#[test]
fn test_submit_approve_and_seller_claim() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());
    submit_fulfillment(escrow, negotiation_id);

    assert(
        escrow.get_negotiation(negotiation_id).status == NegotiationStatus::FulfillmentSubmitted,
        'submitted',
    );
    assert(escrow.get_fulfillment_uri(negotiation_id) == FULFILLMENT_URI(), 'fulfillment uri');

    approve_fulfillment(escrow, negotiation_id);

    let negotiation = escrow.get_negotiation(negotiation_id);
    assert(negotiation.status == NegotiationStatus::Completed, 'completed');
    assert(negotiation.released_amount == 1000, 'released');
    assert(escrow.get_claimable_seller_funds(negotiation_id, SELLER()) == 1000, 'claimable');

    let before = token.balance_of(SELLER());
    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    let claimed = escrow.claim_seller_funds(negotiation_id);

    assert(claimed == 1000, 'claimed');
    assert(token.balance_of(SELLER()) == before + 1000, 'seller paid');
    assert(escrow.get_claimable_seller_funds(negotiation_id, SELLER()) == 0, 'claim consumed');
}

#[test]
#[should_panic(expected: 'Not seller')]
fn test_only_seller_can_submit_fulfillment() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());

    cheat_caller_address(escrow.contract_address, OTHER_BUYER(), CheatSpan::TargetCalls(1));
    escrow.submit_fulfillment(negotiation_id, FULFILLMENT_URI(), 333);
}

#[test]
#[should_panic(expected: 'Deadline expired')]
fn test_submit_rejects_after_deadline() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    submit_fulfillment(escrow, negotiation_id);
}

#[test]
#[should_panic(expected: 'Not buyer')]
fn test_only_buyer_can_approve_fulfillment() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());
    submit_fulfillment(escrow, negotiation_id);

    cheat_caller_address(escrow.contract_address, OTHER_BUYER(), CheatSpan::TargetCalls(1));
    escrow.approve_fulfillment(negotiation_id);
}

#[test]
fn test_expired_funded_listing_cancellation_refunds_buyer() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    cheat_caller_address(escrow.contract_address, BUYER(), CheatSpan::TargetCalls(1));
    escrow.cancel_listing(negotiation_id);

    let negotiation = escrow.get_negotiation(negotiation_id);
    assert(negotiation.status == NegotiationStatus::Cancelled, 'cancelled');
    assert(negotiation.refunded_amount == 1000, 'refunded amount');
    assert(escrow.get_claimable_buyer_refund(negotiation_id, BUYER()) == 1000, 'refund');

    let before = token.balance_of(BUYER());
    cheat_caller_address(escrow.contract_address, BUYER(), CheatSpan::TargetCalls(1));
    let refund = escrow.claim_buyer_refund(negotiation_id);

    assert(refund == 1000, 'refund amount');
    assert(token.balance_of(BUYER()) == before + 1000, 'buyer refunded');
    assert(escrow.get_claimable_buyer_refund(negotiation_id, BUYER()) == 0, 'refund consumed');
}

#[test]
#[should_panic(expected: 'Invalid status')]
fn test_cannot_cancel_after_fulfillment_submitted() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());
    submit_fulfillment(escrow, negotiation_id);

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    cheat_caller_address(escrow.contract_address, BUYER(), CheatSpan::TargetCalls(1));
    escrow.cancel_listing(negotiation_id);
}

#[test]
#[should_panic(expected: 'Listing asset non-transferable')]
fn test_listing_asset_is_non_transferable() {
    let (escrow, token) = setup();
    let negotiation_id = create_listing(escrow, token);
    let erc721 = IERC721Dispatcher { contract_address: escrow.contract_address };

    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    erc721.transfer_from(SELLER(), OTHER_BUYER(), negotiation_id);
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_claim_seller_funds_blocks_reentrant_token_callback() {
    let (escrow, token) = setup_with_malicious_token();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());
    submit_fulfillment(escrow, negotiation_id);
    approve_fulfillment(escrow, negotiation_id);
    configure_malicious_token(token, escrow, negotiation_id, ATTACK_SELLER_CLAIM());

    cheat_caller_address(escrow.contract_address, SELLER(), CheatSpan::TargetCalls(1));
    escrow.claim_seller_funds(negotiation_id);
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_claim_buyer_refund_blocks_reentrant_token_callback() {
    let (escrow, token) = setup_with_malicious_token();
    let negotiation_id = create_listing(escrow, token);
    fund(escrow, negotiation_id, BUYER());

    cheat_block_timestamp(escrow.contract_address, 1000000, CheatSpan::TargetCalls(1));
    cheat_caller_address(escrow.contract_address, BUYER(), CheatSpan::TargetCalls(1));
    escrow.cancel_listing(negotiation_id);
    configure_malicious_token(token, escrow, negotiation_id, ATTACK_BUYER_REFUND());

    cheat_caller_address(escrow.contract_address, BUYER(), CheatSpan::TargetCalls(1));
    escrow.claim_buyer_refund(negotiation_id);
}

#[test]
#[should_panic(expected: 'Negotiation not found')]
fn test_missing_negotiation_reverts() {
    let (escrow, _) = setup();

    escrow.get_negotiation(1);
}
