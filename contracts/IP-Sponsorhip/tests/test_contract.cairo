use ip_sponsorship::IPSponsorship::IPSponsorship::{
    Event as SponsorshipEvent, LicenseMinted, ProposalAccepted, ProposalClosed,
};
use ip_sponsorship::interface::{
    IIPSponsorshipDispatcher, IIPSponsorshipDispatcherTrait, IIP_SPONSORSHIP_ID,
    ILICENSED_COLLECTION_ID,
};
use ip_sponsorship::mocks::MockERC20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_sponsorship::mocks::MockERC721::{IERC721MintDispatcher, IERC721MintDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait, IERC721_ID,
};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
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
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "Mediolano Sponsorship License";
    let symbol: ByteArray = "MSL";
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    IIPSponsorshipDispatcher { contract_address: declare_and_deploy("IPSponsorship", calldata) }
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
    sponsorship.create_offer(nft, IP_TOKEN, 100, DAY, token, TERMS_URI(), true, 0, Option::None)
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
            nft, IP_TOKEN, 100, DAY, token.contract_address, AR_TERMS_URI(), true, 0, Option::None,
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
            nft, IP_TOKEN, 100, DAY, token.contract_address, TERMS_URI(), true, 0, Option::None,
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
            nft, IP_TOKEN, 100, DAY, token.contract_address, HTTP_URI(), true, 0, Option::None,
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
            nft, IP_TOKEN, 100, 0, token.contract_address, TERMS_URI(), true, 0, Option::None,
        );
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_create_offer_rejects_bad_royalty() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship
        .create_offer(
            nft,
            IP_TOKEN,
            100,
            DAY,
            token.contract_address,
            TERMS_URI(),
            true,
            10_001,
            Option::None,
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
            0,
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

    // The license is a real ERC-721 held by the sponsor — on this same contract.
    let erc721 = IERC721Dispatcher { contract_address: sponsorship.contract_address };
    assert(erc721.owner_of(license_id) == SPONSOR1(), 'sponsor holds license nft');
    assert(erc721.balance_of(SPONSOR1()) == 1, 'sponsor balance one');
    assert(sponsorship.get_last_license_id() == license_id, 'last license id');
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
fn test_transferable_license_moves_via_standard_transfer() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    let erc721 = IERC721Dispatcher { contract_address: sponsorship.contract_address };
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    erc721.transfer_from(SPONSOR1(), SPONSOR2(), license_id);

    assert(erc721.owner_of(license_id) == SPONSOR2(), 'holder should update');
}

#[test]
fn test_nontransferable_declared_license_still_transfers() {
    // A `transferable: false` license carries that as a declarative term
    // only (in metadata + the LicenseMinted event) — the contract never
    // gates a transfer on it.
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let offer_id = sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, TERMS_URI(), false, 0, Option::None,
        );

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    let erc721 = IERC721Dispatcher { contract_address: sponsorship.contract_address };
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    erc721.transfer_from(SPONSOR1(), SPONSOR2(), license_id);

    assert(erc721.owner_of(license_id) == SPONSOR2(), 'transfer should have succeeded');
}

#[test]
fn test_royalty_pays_author() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let offer_id = sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, TERMS_URI(), true, 500, Option::None,
        );

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    let (recipient, amount) = sponsorship.royalty_info(license_id, 10_000);
    assert(recipient == AUTHOR(), 'royalty goes to author');
    assert(amount == 500, '5 percent of 10000');
}

#[test]
fn test_token_uri_is_license_terms() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    let metadata = IERC721MetadataDispatcher { contract_address: sponsorship.contract_address };
    assert(metadata.token_uri(license_id) == TERMS_URI(), 'token_uri is license terms');
}

// --- views & discovery ---

#[test]
fn test_supports_sponsorship_interface() {
    let sponsorship = deploy_sponsorship();
    let src5 = ISRC5Dispatcher { contract_address: sponsorship.contract_address };
    assert(src5.supports_interface(IIP_SPONSORSHIP_ID), 'SRC5 id registered');
}

#[test]
fn test_accepted_bid_mints_real_erc721() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let offer_id = create_offer(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    let src5 = ISRC5Dispatcher { contract_address: sponsorship.contract_address };
    assert(src5.supports_interface(IERC721_ID), 'erc721 iface');
    assert(src5.supports_interface(IIP_SPONSORSHIP_ID), 'sponsorship iface');
    assert(src5.supports_interface(IERC2981_ID), 'erc2981 iface');
    assert(src5.supports_interface(ILICENSED_COLLECTION_ID), 'licensed marker');

    let erc721 = IERC721Dispatcher { contract_address: sponsorship.contract_address };
    assert(erc721.owner_of(license_id) == SPONSOR1(), 'owner is sponsor');
    assert(erc721.balance_of(SPONSOR1()) == 1, 'balance is one');
}

#[test]
#[should_panic(expected: 'Offer does not exist')]
fn test_missing_offer_reverts() {
    let sponsorship = deploy_sponsorship();
    sponsorship.get_offer(42);
}

#[test]
fn test_version_views() {
    let sponsorship = deploy_sponsorship();
    assert(sponsorship.version() == "3.0.0", 'sponsorship version');
}

#[test]
fn test_license_minted_event_carries_royalty_and_terms() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let offer_id = sponsorship
        .create_offer(
            nft, IP_TOKEN, 100, DAY, token.contract_address, TERMS_URI(), true, 500, Option::None,
        );

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.place_bid(offer_id, 250);
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    cheat_block_timestamp(sponsorship.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let mut spy = spy_events();
    let license_id = sponsorship.accept_bid(offer_id, SPONSOR1());

    spy
        .assert_emitted(
            @array![
                (
                    sponsorship.contract_address,
                    SponsorshipEvent::LicenseMinted(
                        LicenseMinted {
                            token_id: license_id,
                            recipient: SPONSOR1(),
                            author: AUTHOR(),
                            asset_contract: nft,
                            asset_token_id: IP_TOKEN,
                            expires_at: 1000 + DAY,
                            transferable: true,
                            royalty_bps: 500,
                            license_terms_uri: TERMS_URI(),
                            minted_at: 1000,
                        },
                    ),
                ),
            ],
        );
}

// --- sponsor-initiated proposals ---

#[test]
fn test_propose_sponsorship_then_owner_accepts() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 500,
        );

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_proposal(proposal_id);

    let erc721 = IERC721Dispatcher { contract_address: sponsorship.contract_address };
    assert(erc721.owner_of(license_id) == SPONSOR1(), 'sponsor should hold license');
    assert(token.balance_of(AUTHOR()) == 250, 'author should be paid');
    assert(!sponsorship.get_proposal(proposal_id).open, 'proposal should be closed');
}

#[test]
#[should_panic(expected: 'Not IP owner')]
fn test_accept_proposal_reverts_for_non_owner() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 0,
        );

    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship.accept_proposal(proposal_id);
}

#[test]
fn test_withdraw_proposal_closes_it() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 0,
        );
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.withdraw_proposal(proposal_id);

    assert(!sponsorship.get_proposal(proposal_id).open, 'proposal should be closed');
}

#[test]
#[should_panic(expected: 'Only proposer')]
fn test_withdraw_proposal_rejects_non_proposer() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 0,
        );
    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship.withdraw_proposal(proposal_id);
}

#[test]
fn test_reject_proposal_by_owner_closes_it() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 0,
        );
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.reject_proposal(proposal_id);

    assert(!sponsorship.get_proposal(proposal_id).open, 'proposal should be closed');
}

#[test]
#[should_panic(expected: 'Proposal not open')]
fn test_accept_proposal_reverts_after_withdrawal() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 0,
        );
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.withdraw_proposal(proposal_id);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_proposal(proposal_id);
}

fn propose(
    sponsorship: IIPSponsorshipDispatcher, nft: ContractAddress, token: ContractAddress,
) -> u256 {
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.propose_sponsorship(nft, IP_TOKEN, 250, DAY, 0, token, TERMS_URI(), true, 0)
}

#[test]
#[should_panic(expected: 'Not IP owner')]
fn test_reject_proposal_rejects_non_owner() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    let proposal_id = propose(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, OUTSIDER(), CheatSpan::TargetCalls(1));
    sponsorship.reject_proposal(proposal_id);
}

#[test]
#[should_panic(expected: 'Proposal not open')]
fn test_accept_proposal_reverts_after_reject() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    let proposal_id = propose(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.reject_proposal(proposal_id);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_proposal(proposal_id);
}

#[test]
#[should_panic(expected: 'Proposal not open')]
fn test_withdraw_proposal_reverts_after_accept() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    let proposal_id = propose(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_proposal(proposal_id);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship.withdraw_proposal(proposal_id);
}

#[test]
#[should_panic(expected: 'Amount cannot be zero')]
fn test_propose_rejects_zero_amount() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 0, DAY, 0, token.contract_address, TERMS_URI(), true, 0,
        );
}

#[test]
#[should_panic(expected: 'Duration cannot be zero')]
fn test_propose_rejects_zero_duration() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, 0, 0, token.contract_address, TERMS_URI(), true, 0,
        );
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_propose_rejects_http_terms() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, HTTP_URI(), true, 0,
        );
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_propose_rejects_bad_royalty() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 0, token.contract_address, TERMS_URI(), true, 10_001,
        );
}

#[test]
#[should_panic(expected: 'Deadline in the past')]
fn test_propose_rejects_past_deadline() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());

    cheat_block_timestamp(sponsorship.contract_address, 500, CheatSpan::TargetCalls(1));
    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 400, token.contract_address, TERMS_URI(), true, 0,
        );
}

#[test]
#[should_panic(expected: 'Proposal expired')]
fn test_accept_proposal_reverts_after_deadline() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);

    cheat_caller_address(sponsorship.contract_address, SPONSOR1(), CheatSpan::TargetCalls(1));
    let proposal_id = sponsorship
        .propose_sponsorship(
            nft, IP_TOKEN, 250, DAY, 1000, token.contract_address, TERMS_URI(), true, 0,
        );

    cheat_block_timestamp(sponsorship.contract_address, 1001, CheatSpan::TargetCalls(1));
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_proposal(proposal_id);
}

#[test]
#[should_panic]
fn test_accept_proposal_without_allowance_reverts_atomically() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    // Proposer never approved — the proposer's de-facto withdrawal path.
    let proposal_id = propose(sponsorship, nft, token.contract_address);

    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    sponsorship.accept_proposal(proposal_id);
}

#[test]
fn test_new_owner_can_accept_proposal_after_ip_sale() {
    // A proposal binds to the asset, not a person: whoever owns the asset
    // at acceptance time is paid and issues the license.
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    let proposal_id = propose(sponsorship, nft, token.contract_address);

    let ip = IERC721Dispatcher { contract_address: nft };
    cheat_caller_address(nft, AUTHOR(), CheatSpan::TargetCalls(1));
    ip.transfer_from(AUTHOR(), SPONSOR2(), IP_TOKEN);

    cheat_caller_address(sponsorship.contract_address, SPONSOR2(), CheatSpan::TargetCalls(1));
    let license_id = sponsorship.accept_proposal(proposal_id);

    assert(token.balance_of(SPONSOR2()) == 250, 'new owner should be paid');
    let erc721 = IERC721Dispatcher { contract_address: sponsorship.contract_address };
    assert(erc721.owner_of(license_id) == SPONSOR1(), 'sponsor should hold license');
    let (royalty_recipient, _) = sponsorship.royalty_info(license_id, 10_000);
    assert(royalty_recipient == SPONSOR2(), 'license author is new owner');
}

#[test]
fn test_accept_proposal_emits_closed_and_accepted() {
    let sponsorship = deploy_sponsorship();
    let token = deploy_erc20();
    let nft = deploy_ip_nft_for(AUTHOR());
    fund_and_approve(token, SPONSOR1(), sponsorship.contract_address, 250);
    let proposal_id = propose(sponsorship, nft, token.contract_address);

    cheat_block_timestamp(sponsorship.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(sponsorship.contract_address, AUTHOR(), CheatSpan::TargetCalls(1));
    let mut spy = spy_events();
    let license_id = sponsorship.accept_proposal(proposal_id);

    spy
        .assert_emitted(
            @array![
                (
                    sponsorship.contract_address,
                    SponsorshipEvent::ProposalClosed(
                        ProposalClosed { proposal_id, accepted: true, closed_at: 1000 },
                    ),
                ),
                (
                    sponsorship.contract_address,
                    SponsorshipEvent::ProposalAccepted(
                        ProposalAccepted {
                            proposal_id,
                            license_id,
                            sponsor: SPONSOR1(),
                            author: AUTHOR(),
                            amount: 250,
                            expires_at: 1000 + DAY,
                        },
                    ),
                ),
            ],
        );
}
