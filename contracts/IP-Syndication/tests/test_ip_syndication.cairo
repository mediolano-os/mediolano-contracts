use ip_syndication::interface::{
    IIPSyndicationDispatcher, IIPSyndicationDispatcherTrait, IIP_SYNDICATION_ID,
};
use ip_syndication::mock::erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use ip_syndication::mock::malicious_erc20::{
    IMaliciousERC20ConfigDispatcher, IMaliciousERC20ConfigDispatcherTrait,
};
use ip_syndication::mock::reentrant_erc1155_receiver::{
    IReentrantERC1155ReceiverConfigDispatcher, IReentrantERC1155ReceiverConfigDispatcherTrait,
};
use ip_syndication::types::{Mode, Status};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc1155::interface::{
    IERC1155Dispatcher, IERC1155DispatcherTrait, IERC1155MetadataURIDispatcher,
    IERC1155MetadataURIDispatcherTrait,
};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
use starknet::ContractAddress;

fn OWNER() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn CREATOR() -> ContractAddress {
    0x102.try_into().unwrap()
}

fn ALICE() -> ContractAddress {
    0x103.try_into().unwrap()
}

fn BOB() -> ContractAddress {
    0x104.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn IPFS_URI() -> ByteArray {
    "ipfs://bafybeisyndication"
}

fn AR_URI() -> ByteArray {
    "ar://syndication"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/syndication.json"
}

fn ATTACK_DEPOSIT() -> u8 {
    1
}

fn ATTACK_REFUND() -> u8 {
    2
}

fn ATTACK_PROCEEDS() -> u8 {
    3
}

fn SHORT_TRANSFER_FROM() -> u8 {
    4
}

fn deploy_syndication() -> IIPSyndicationDispatcher {
    let contract = declare("IPSyndication").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IIPSyndicationDispatcher { contract_address }
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

fn deploy_receiver() -> ContractAddress {
    let contract = declare("MockERC1155Receiver").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_reentrant_receiver() -> ContractAddress {
    let contract = declare("ReentrantERC1155Receiver").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn configure_malicious_erc20(
    token: IERC20Dispatcher, syndication: IIPSyndicationDispatcher, ip_id: u256, mode: u8,
) {
    IMaliciousERC20ConfigDispatcher { contract_address: token.contract_address }
        .configure_attack(syndication.contract_address, ip_id, mode, 1);
}

fn configure_reentrant_receiver(
    receiver: ContractAddress, syndication: IIPSyndicationDispatcher, ip_id: u256,
) {
    IReentrantERC1155ReceiverConfigDispatcher { contract_address: receiver }
        .configure_reentrant_mint(syndication.contract_address, ip_id);
}

fn mint_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) {
    IERC20MintDispatcher { contract_address: token }.mint(recipient, amount);
}

fn approve(token: IERC20Dispatcher, owner: ContractAddress, spender: ContractAddress) {
    cheat_caller_address(token.contract_address, owner, CheatSpan::TargetCalls(1));
    token.approve(spender, 1000000);
}

fn setup() -> (IIPSyndicationDispatcher, IERC20Dispatcher) {
    let syndication = deploy_syndication();
    let token = deploy_erc20();
    mint_erc20(token.contract_address, ALICE(), 1000000);
    mint_erc20(token.contract_address, BOB(), 1000000);
    mint_erc20(token.contract_address, OWNER(), 1000000);
    approve(token, ALICE(), syndication.contract_address);
    approve(token, BOB(), syndication.contract_address);
    approve(token, OWNER(), syndication.contract_address);
    (syndication, token)
}

fn register_public(
    syndication: IIPSyndicationDispatcher, token: IERC20Dispatcher, target: u256,
) -> u256 {
    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication
        .register_ip(
            target,
            'syndicated_ip',
            "description",
            IPFS_URI(),
            'license_terms',
            Mode::Public,
            token.contract_address,
        )
}

fn activate(syndication: IIPSyndicationDispatcher, ip_id: u256) {
    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.activate_syndication(ip_id);
}

#[test]
fn test_register_ip_success() {
    let (syndication, token) = setup();

    let ip_id = register_public(syndication, token, 1000);

    assert(ip_id == 1, 'ip id should be one');
    assert(syndication.get_last_ip_id() == 1, 'last id should match');

    let metadata = syndication.get_ip_metadata(ip_id);
    assert(metadata.owner == CREATOR(), 'owner should match');
    assert(metadata.target_amount == 1000, 'target should match');
    assert(metadata.metadata_uri == IPFS_URI(), 'uri should match');
    assert(metadata.token_id == ip_id, 'token id should match');
    assert(metadata.exists, 'metadata should exist');

    let details = syndication.get_syndication_details(ip_id);
    assert(details.status == Status::Pending, 'status should be pending');
    assert(details.mode == Mode::Public, 'mode should be public');
    assert(details.payment_token == token.contract_address, 'token should match');
}

#[test]
fn test_register_accepts_ar_uri() {
    let (syndication, token) = setup();

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let ip_id = syndication
        .register_ip(
            1000, 'ip', "description", AR_URI(), 'terms', Mode::Public, token.contract_address,
        );

    assert(syndication.get_ip_metadata(ip_id).metadata_uri == AR_URI(), 'ar uri should match');
}

#[test]
#[should_panic(expected: 'Target is zero')]
fn test_register_rejects_zero_target() {
    let (syndication, token) = setup();

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication
        .register_ip(
            0, 'ip', "description", IPFS_URI(), 'terms', Mode::Public, token.contract_address,
        );
}

#[test]
#[should_panic(expected: 'Invalid payment token')]
fn test_register_rejects_zero_payment_token() {
    let (syndication, _) = setup();

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.register_ip(1000, 'ip', "description", IPFS_URI(), 'terms', Mode::Public, ZERO());
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_register_rejects_http_uri() {
    let (syndication, token) = setup();

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication
        .register_ip(
            1000, 'ip', "description", HTTP_URI(), 'terms', Mode::Public, token.contract_address,
        );
}

#[test]
fn test_activate_syndication() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);

    activate(syndication, ip_id);

    assert(syndication.get_syndication_status(ip_id) == Status::Active, 'status should active');
}

#[test]
#[should_panic(expected: 'Not IP owner')]
fn test_activate_rejects_non_owner() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.activate_syndication(ip_id);
}

#[test]
fn test_deposit_public_mode() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    let alice_before = token.balance_of(ALICE());
    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    let deposited = syndication.deposit(ip_id, 300);

    assert(deposited == 300, 'deposit amount should match');
    assert(token.balance_of(ALICE()) == alice_before - 300, 'alice balance');
    assert(token.balance_of(syndication.contract_address) == 300, 'contract balance');
    assert(syndication.get_participant_count(ip_id) == 1, 'participant count');

    let participant = syndication.get_participant_details(ip_id, ALICE());
    assert(participant.amount_deposited == 300, 'amount deposited');
    assert(participant.share == 300, 'share should match');
}

#[test]
fn test_deposit_caps_to_remaining_amount() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 700);

    cheat_caller_address(syndication.contract_address, BOB(), CheatSpan::TargetCalls(1));
    let deposited = syndication.deposit(ip_id, 1000);

    assert(deposited == 300, 'should cap deposit');
    assert(syndication.get_syndication_status(ip_id) == Status::Completed, 'completed');
    assert(syndication.get_syndication_details(ip_id).total_raised == 1000, 'total raised');
}

#[test]
fn test_get_participants_paginates_results() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 300);
    cheat_caller_address(syndication.contract_address, BOB(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 300);

    let all_participants = syndication.get_all_participants(ip_id);
    assert(all_participants.len() == 2, 'all participants len');
    assert(*all_participants.at(0) == ALICE(), 'all first');
    assert(*all_participants.at(1) == BOB(), 'all second');

    let page = syndication.get_participants(ip_id, 1, 1);
    assert(page.len() == 1, 'page len');
    assert(*page.at(0) == BOB(), 'page participant');

    let empty_page = syndication.get_participants(ip_id, 99, 10);
    assert(empty_page.len() == 0, 'empty page');
}

#[test]
#[should_panic(expected: 'Syndication not active')]
fn test_deposit_requires_active_syndication() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 100);
}

#[test]
#[should_panic(expected: 'Payment failed')]
fn test_deposit_rejects_short_transfer_from_receipt() {
    let syndication = deploy_syndication();
    let token = deploy_malicious_erc20();
    mint_erc20(token.contract_address, ALICE(), 1000000);
    approve(token, ALICE(), syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);
    configure_malicious_erc20(token, syndication, ip_id, SHORT_TRANSFER_FROM());

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 100);
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_deposit_blocks_reentrant_token_callback() {
    let syndication = deploy_syndication();
    let token = deploy_malicious_erc20();
    mint_erc20(token.contract_address, ALICE(), 1000000);
    approve(token, ALICE(), syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);
    configure_malicious_erc20(token, syndication, ip_id, ATTACK_DEPOSIT());

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 100);
}

#[test]
fn test_whitelist_mode_deposit() {
    let (syndication, token) = setup();

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let ip_id = syndication
        .register_ip(
            1000, 'ip', "description", IPFS_URI(), 'terms', Mode::Whitelist, token.contract_address,
        );

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.update_whitelist(ip_id, ALICE(), true);
    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.activate_syndication(ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 100);

    assert(syndication.is_whitelisted(ip_id, ALICE()), 'alice whitelisted');
    assert(syndication.get_participant_count(ip_id) == 1, 'participant count');
}

#[test]
#[should_panic(expected: 'Address not whitelisted')]
fn test_whitelist_mode_rejects_non_whitelisted_deposit() {
    let (syndication, token) = setup();

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let ip_id = syndication
        .register_ip(
            1000, 'ip', "description", IPFS_URI(), 'terms', Mode::Whitelist, token.contract_address,
        );
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 100);
}

#[test]
fn test_cancel_and_pull_refund() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 400);

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.cancel_syndication(ip_id);

    let alice_before = token.balance_of(ALICE());
    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    let refund = syndication.claim_refund(ip_id);

    assert(refund == 400, 'refund should match');
    assert(token.balance_of(ALICE()) == alice_before + 400, 'alice refunded');
    assert(syndication.get_claimable_refund(ip_id, ALICE()) == 0, 'refund consumed');
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_claim_refund_blocks_reentrant_token_callback() {
    let syndication = deploy_syndication();
    let token = deploy_malicious_erc20();
    mint_erc20(token.contract_address, ALICE(), 1000000);
    approve(token, ALICE(), syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 400);

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.cancel_syndication(ip_id);
    configure_malicious_erc20(token, syndication, ip_id, ATTACK_REFUND());

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.claim_refund(ip_id);
}

#[test]
#[should_panic(expected: 'Completed or cancelled')]
fn test_cancel_rejects_completed_syndication() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.cancel_syndication(ip_id);
}

#[test]
fn test_claim_proceeds_after_completion() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);

    let creator_before = token.balance_of(CREATOR());
    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let proceeds = syndication.claim_proceeds(ip_id);

    assert(proceeds == 1000, 'proceeds should match');
    assert(token.balance_of(CREATOR()) == creator_before + 1000, 'creator paid');
    assert(syndication.get_syndication_details(ip_id).proceeds_claimed, 'claimed');
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_claim_proceeds_blocks_reentrant_token_callback() {
    let syndication = deploy_syndication();
    let token = deploy_malicious_erc20();
    mint_erc20(token.contract_address, ALICE(), 1000000);
    approve(token, ALICE(), syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);
    configure_malicious_erc20(token, syndication, ip_id, ATTACK_PROCEEDS());

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.claim_proceeds(ip_id);
}

#[test]
#[should_panic(expected: 'Proceeds already claimed')]
fn test_claim_proceeds_only_once() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, ALICE(), CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);

    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.claim_proceeds(ip_id);
    cheat_caller_address(syndication.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    syndication.claim_proceeds(ip_id);
}

#[test]
fn test_mint_asset_after_completion() {
    let (syndication, token) = setup();
    let alice = deploy_receiver();
    let bob = deploy_receiver();
    mint_erc20(token.contract_address, alice, 1000000);
    mint_erc20(token.contract_address, bob, 1000000);
    approve(token, alice, syndication.contract_address);
    approve(token, bob, syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, alice, CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 400);
    cheat_caller_address(syndication.contract_address, bob, CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 600);

    cheat_caller_address(syndication.contract_address, alice, CheatSpan::TargetCalls(1));
    syndication.mint_asset(ip_id);

    let erc1155 = IERC1155Dispatcher { contract_address: syndication.contract_address };
    assert(erc1155.balance_of(alice, ip_id) == 400, 'alice share balance');
    assert(syndication.total_shares_minted(ip_id) == 400, 'shares minted');
    assert(syndication.get_participant_details(ip_id, alice).share_minted, 'minted flag');
}

#[test]
#[should_panic(expected: 'Already minted')]
fn test_mint_asset_only_once() {
    let (syndication, token) = setup();
    let participant = deploy_receiver();
    mint_erc20(token.contract_address, participant, 1000000);
    approve(token, participant, syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, participant, CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);
    cheat_caller_address(syndication.contract_address, participant, CheatSpan::TargetCalls(1));
    syndication.mint_asset(ip_id);
    cheat_caller_address(syndication.contract_address, participant, CheatSpan::TargetCalls(1));
    syndication.mint_asset(ip_id);
}

#[test]
fn test_mint_asset_to_receiver_contract() {
    let (syndication, token) = setup();
    let receiver = deploy_receiver();
    mint_erc20(token.contract_address, receiver, 1000);
    approve(token, receiver, syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, receiver, CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);
    cheat_caller_address(syndication.contract_address, receiver, CheatSpan::TargetCalls(1));
    syndication.mint_asset(ip_id);

    let erc1155 = IERC1155Dispatcher { contract_address: syndication.contract_address };
    assert(erc1155.balance_of(receiver, ip_id) == 1000, 'receiver balance');
}

#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_mint_asset_blocks_reentrant_receiver_callback() {
    let (syndication, token) = setup();
    let receiver = deploy_reentrant_receiver();
    mint_erc20(token.contract_address, receiver, 1000);
    approve(token, receiver, syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);
    configure_reentrant_receiver(receiver, syndication, ip_id);

    cheat_caller_address(syndication.contract_address, receiver, CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);
    cheat_caller_address(syndication.contract_address, receiver, CheatSpan::TargetCalls(1));
    syndication.mint_asset(ip_id);
}

#[test]
fn test_erc1155_share_is_transferable() {
    let (syndication, token) = setup();
    let alice = deploy_receiver();
    let bob = deploy_receiver();
    mint_erc20(token.contract_address, alice, 1000000);
    approve(token, alice, syndication.contract_address);

    let ip_id = register_public(syndication, token, 1000);
    activate(syndication, ip_id);

    cheat_caller_address(syndication.contract_address, alice, CheatSpan::TargetCalls(1));
    syndication.deposit(ip_id, 1000);
    cheat_caller_address(syndication.contract_address, alice, CheatSpan::TargetCalls(1));
    syndication.mint_asset(ip_id);

    let erc1155 = IERC1155Dispatcher { contract_address: syndication.contract_address };
    cheat_caller_address(syndication.contract_address, alice, CheatSpan::TargetCalls(1));
    erc1155.safe_transfer_from(alice, bob, ip_id, 250, array![].span());

    assert(erc1155.balance_of(alice, ip_id) == 750, 'alice balance');
    assert(erc1155.balance_of(bob, ip_id) == 250, 'bob balance');
}

#[test]
fn test_token_uri_and_src5() {
    let (syndication, token) = setup();
    let ip_id = register_public(syndication, token, 1000);
    let metadata = IERC1155MetadataURIDispatcher { contract_address: syndication.contract_address };
    let src5 = ISRC5Dispatcher { contract_address: syndication.contract_address };

    assert(metadata.uri(ip_id) == IPFS_URI(), 'token uri');
    assert(src5.supports_interface(IIP_SYNDICATION_ID), 'interface supported');
}

#[test]
#[should_panic(expected: 'IP does not exist')]
fn test_missing_ip_reverts() {
    let (syndication, _) = setup();

    syndication.get_ip_metadata(1);
}
