use ip_sponsorship::interface::{
    IIPSponsorshipDispatcher, IIPSponsorshipDispatcherTrait, IIP_SPONSORSHIP_ID,
};
use ip_sponsorship::mocks::MockERC20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_sponsorship::mocks::MockERC721::{IERC721MintDispatcher, IERC721MintDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_block_timestamp, cheat_caller_address,
    declare,
};
use starknet::ContractAddress;

fn AUTHOR() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn SPONSOR1() -> ContractAddress {
    0x102.try_into().unwrap()
}

fn SPONSOR2() -> ContractAddress {
    0x103.try_into().unwrap()
}

fn OUTSIDER() -> ContractAddress {
    0x104.try_into().unwrap()
}

fn TERMS_URI() -> ByteArray {
    "ipfs://bafyLicenseTerms"
}

fn AR_TERMS_URI() -> ByteArray {
    "ar://license-terms"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/terms.json"
}

const DAY: u64 = 86400;
const IP_TOKEN: u256 = 7;

fn declare_and_deploy(contract_name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_sponsorship() -> IIPSponsorshipDispatcher {
    let address = declare_and_deploy("IPSponsorship", array![]);
    IIPSponsorshipDispatcher { contract_address: address }
}

fn deploy_erc20() -> IERC20Dispatcher {
    let mut calldata = array![];
    let name: ByteArray = "Mock Token";
    let symbol: ByteArray = "MOCK";
    let supply: u256 = 0;
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(supply);
    IERC20Dispatcher { contract_address: declare_and_deploy("MockERC20", calldata) }
}

fn deploy_ip_nft_for(owner: ContractAddress) -> ContractAddress {
    let address = declare_and_deploy("MockERC721", array![]);
    IERC721MintDispatcher { contract_address: address }.mint(owner, IP_TOKEN);
    address
}

fn fund_and_approve(
    token: IERC20Dispatcher, user: ContractAddress, spender: ContractAddress, amount: u256,
) {
    IERC20MintDispatcher { contract_address: token.contract_address }.mint(user, amount);
    cheat_caller_address(token.contract_address, user, CheatSpan::TargetCalls(1));
    token.approve(spender, amount);
}

fn create_offer(
    sponsorship: IIPSponsorshipDispatcher, nft: ContractAddress, token: ContractAddress,
) -> u256 {
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.create_offer(nft, IP_TOKEN, 100, DAY, token, TERMS_URI(), true, Option::None)
}

// --- offer creation ---

#[test]
fn test_create_offer_by_ip_owner() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    assert(offer_id == 1, 'offer id should be one');
    assert(sponsorship.get_last_offer_id() == 1, 'last offer id');
    let offer = sponsorship.get_offer(offer_id);
    assert(offer.author == AUTHOR(), 'author recorded');
    assert(offer.nft_contract == nft, 'nft recorded');
    assert(offer.token_id == IP_TOKEN, 'token recorded');
    assert(offer.open, 'offer should be open');
    assert(offer.license_terms_uri == TERMS_URI(), 'terms recorded');
}

#[test]
fn test_create_offer_accepts_ar_terms() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let offer_id = sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, AR_TERMS_URI(), true, Option::None,
        );
    assert(sponsorship.get_offer(offer_id).license_terms_uri == AR_TERMS_URI(), 'ar terms');
}

#[test]
#[should_panic(expected: 'Not IP owner')]
fn test_create_offer_rejects_non_owner() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, TERMS_URI(), true, Option::None,
        );
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_offer_rejects_http_terms() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, HTTP_URI(), true, Option::None,
        );
}

#[test]
#[should_panic(expected: 'Duration cannot be zero')]
fn test_create_offer_rejects_zero_duration() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, 0, token.contract_address, TERMS_URI(), true, Option::None,
        );
}

// --- offer toggle ---

#[test]
#[should_panic(expected: 'Only offer author')]
fn test_only_author_can_toggle_offer() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship.set_offer_open(offer_id, false);
}

#[test]
#[should_panic(expected: 'Offer not open')]
fn test_closed_offer_blocks_bids() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.set_offer_open(offer_id, false);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);
}

#[test]
#[should_panic(expected: 'Offer not open')]
fn test_closed_offer_blocks_accept() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.set_offer_open(offer_id, false);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_bid(offer_id, SPONSOR1());
}

#[test]
fn test_reopened_offer_accepts_bids() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.set_offer_open(offer_id, false);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.set_offer_open(offer_id, true);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);
    assert(sponsorship.get_bid(offer_id, SPONSOR1()) == 200, 'bid should land');
}

// --- bidding ---

#[test]
fn test_rebid_overwrites_standing_bid() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 350);

    assert(sponsorship.get_bid(offer_id, SPONSOR1()) == 350, 'rebid should overwrite');
}

#[test]
#[should_panic(expected: 'Bid below minimum')]
fn test_bid_below_minimum_rejected() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 99);
}

#[test]
#[should_panic(expected: 'Not the invited sponsor')]
fn test_specific_sponsor_offer_rejects_others() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let offer_id = sponsorship
        .create_offer(
            nft,
            IP_TOKEN,
            100,
            DAY,
            token.contract_address,
            TERMS_URI(),
            true,
            Option::Some(SPONSOR1()),
        );

    cheat_caller_address(sponsorship.contract_address, SPONSOR2(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);
}

#[test]
#[should_panic(expected: 'No standing bid')]
fn test_retract_clears_bid() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.retract_bid(offer_id);

    assert(sponsorship.get_bid(offer_id, SPONSOR1()) == 0, 'bid should clear');

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_bid(offer_id, SPONSOR1());
}

// --- acceptance & settlement ---

#[test]
fn test_accept_settles_payment_and_issues_license() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    cheat_block_timestamp(sponsorship.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    // Payment settled sponsor → author directly.
    assert(token.balance_of(AUTHOR()) == 250, 'author should be paid');
    assert(token.balance_of(SPONSOR1()) == 0, 'sponsor should be charged');

    // Offer consumed; bid consumed.
    assert(!sponsorship.get_offer(offer_id).open, 'offer should close');
    assert(sponsorship.get_bid(offer_id, SPONSOR1()) == 0, 'bid should be consumed');

    // License issued with the offer's immutable terms.
    let license = sponsorship.get_license(license_id);
    assert(license.author == AUTHOR(), 'license author');
    assert(license.sponsor == SPONSOR1(), 'license sponsor');
    assert(license.amount_paid == 250, 'license amount');
    assert(license.expires_at == 1000 + DAY, 'license expiry');
    assert(license.transferable, 'license transferable');
    cheat_block_timestamp(sponsorship.contract_address, 1000, CheatSpan::TargetCalls(1));
    assert(sponsorship.is_license_valid(license_id), 'license should be valid');
}

#[test]
#[should_panic(expected: 'Only offer author')]
fn test_accept_rejects_non_author() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 200);

    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship.accept_bid(offer_id, SPONSOR1());
}

#[test]
#[should_panic]
fn test_accept_without_allowance_reverts_atomically() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    // Sponsor never approved — the sponsor's de-facto withdrawal path.

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_bid(offer_id, SPONSOR1());
}

#[test]
#[should_panic(expected: 'Not IP owner')]
fn test_accept_after_ip_sale_reverts() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    // Author sells the IP before accepting — the offer must not survive.
    let erc721 = IERC721Dispatcher { contract_address: nft };
    cheat_caller_address(nft, AUTHOR(), CheatSpan::TargetCalls(1));
    erc721.transfer_from(AUTHOR(), OUTSIDER(), IP_TOKEN);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_bid(offer_id, SPONSOR1());
}

// --- licenses ---

#[test]
fn test_license_expires_inclusively() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_block_timestamp(sponsorship.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    cheat_block_timestamp(sponsorship.contract_address, 1000 + DAY, CheatSpan::TargetCalls(1));
    assert(sponsorship.is_license_valid(license_id), 'valid at expiry boundary');
    cheat_block_timestamp(sponsorship.contract_address, 1001 + DAY, CheatSpan::TargetCalls(1));
    assert(!sponsorship.is_license_valid(license_id), 'invalid after expiry');
}

#[test]
fn test_license_transfer() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.transfer_license(license_id, SPONSOR2());

    assert(sponsorship.get_license(license_id).sponsor == SPONSOR2(), 'holder should update');
}

#[test]
#[should_panic(expected: 'License not transferable')]
fn test_non_transferable_license_stays_put() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let offer_id = sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, TERMS_URI(), false, Option::None,
        );

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.transfer_license(license_id, SPONSOR2());
}

#[test]
#[should_panic(expected: 'Only license holder')]
fn test_license_transfer_rejects_non_holder() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship.transfer_license(license_id, OUTSIDER());
}

// --- views & discovery ---

#[test]
fn test_supports_sponsorship_interface() {
    let sponsorship = deploy_sponsorship();
    let src5 = ISRC5Dispatcher { contract_address: sponsorship.contract_address };
    assert(src5.supports_interface(IIP_SPONSORSHIP_ID), 'SRC5 id registered');
}

#[test]
#[should_panic(expected: 'Offer does not exist')]
fn test_missing_offer_reverts() {
    let sponsorship = deploy_sponsorship();
    sponsorship.get_offer(42);
}

#[test]
#[should_panic(expected: 'License does not exist')]
fn test_missing_license_reverts() {
    let sponsorship = deploy_sponsorship();
    sponsorship.get_license(42);
}
