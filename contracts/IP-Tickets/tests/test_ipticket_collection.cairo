use ip_ticket::interface::{IIPTicketCollectionDispatcher, IIPTicketCollectionDispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
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

fn deploy_collection() -> ContractAddress {
    let owner = deploy_mock_account();
    deploy_collection_with_owner(owner)
}

fn deploy_collection_with_owner(owner: ContractAddress) -> ContractAddress {
    let class = declare("IPTicketCollection").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "IP Tickets Test";
    let symbol: ByteArray = "TICK";
    cd.append_serde(name);
    cd.append_serde(symbol);
    cd.append_serde(owner);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

// ──────────────── create_event ─────────────────────────────────────────────

#[test]
fn test_create_event_assigns_token_id() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(100_u256, Option::None, Option::None, 500_u16, "ipfs://QmTest1");
    stop_cheat_caller_address(addr);
    assert(id == 1_u256, 'first event id should be 1');
}

#[test]
fn test_second_event_increments_id() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmA");
    let id2 = ticket.create_event(20_u256, Option::None, Option::None, 0_u16, "ipfs://QmB");
    stop_cheat_caller_address(addr);
    assert(id2 == 2_u256, 'second event id should be 2');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_create_event_non_owner_panics() {
    let addr = deploy_collection();
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, OTHER());
    ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Max supply is zero')]
fn test_create_event_zero_supply_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    ticket.create_event(0_u256, Option::None, Option::None, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_event_bad_uri_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "https://example.com");
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_create_event_royalty_overflow_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    ticket.create_event(10_u256, Option::None, Option::None, 10001_u16, "ipfs://QmX");
}

#[test]
fn test_create_event_ar_uri_accepted() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(5_u256, Option::None, Option::None, 0_u16, "ar://txhash123");
    stop_cheat_caller_address(addr);
    assert(id == 1_u256, 'ar:// uri should be accepted');
}

// ──────────────── mint ─────────────────────────────────────────────────────

#[test]
fn test_mint_increases_balance() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    let erc1155 = IERC1155Dispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(100_u256, Option::None, Option::None, 0_u16, "ipfs://QmM");
    ticket.mint(recipient, id, 3_u256);
    stop_cheat_caller_address(addr);
    assert(erc1155.balance_of(recipient, id) == 3_u256, 'balance should be 3');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_mint_non_owner_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmM");
    stop_cheat_caller_address(addr);
    start_cheat_caller_address(addr, OTHER());
    ticket.mint(recipient, id, 1_u256);
}

#[test]
#[should_panic(expected: 'Max supply reached')]
fn test_mint_exceeds_supply_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(2_u256, Option::None, Option::None, 0_u16, "ipfs://QmS");
    ticket.mint(recipient, id, 3_u256);
}

#[test]
#[should_panic(expected: 'Event is paused')]
fn test_mint_paused_event_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmP");
    ticket.pause_event(id, false);
    ticket.mint(recipient, id, 1_u256);
}

#[test]
#[should_panic(expected: 'Minting not yet open')]
fn test_mint_before_start_time_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 1000);
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(
        10_u256, Option::Some(2000_u64), Option::None, 0_u16, "ipfs://QmT",
    );
    ticket.mint(recipient, id, 1_u256);
}

#[test]
#[should_panic(expected: 'Minting window closed')]
fn test_mint_after_end_time_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 3000);
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(
        10_u256, Option::None, Option::Some(2000_u64), 0_u16, "ipfs://QmE",
    );
    ticket.mint(recipient, id, 1_u256);
}

#[test]
fn test_mint_within_window() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    let erc1155 = IERC1155Dispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 500);
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(
        10_u256, Option::Some(100_u64), Option::Some(1000_u64), 0_u16, "ipfs://QmW",
    );
    ticket.mint(recipient, id, 2_u256);
    stop_cheat_caller_address(addr);
    assert(erc1155.balance_of(recipient, id) == 2_u256, 'balance in window');
}

// ──────────────── is_valid ─────────────────────────────────────────────────

#[test]
fn test_is_valid_true_for_holder_in_window() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 500);
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(
        10_u256, Option::Some(100_u64), Option::Some(1000_u64), 0_u16, "ipfs://QmV",
    );
    ticket.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(ticket.is_valid(id, recipient), 'should be valid');
}

#[test]
fn test_is_valid_false_after_end_time() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 500);
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(
        10_u256, Option::None, Option::Some(1000_u64), 0_u16, "ipfs://QmWW",
    );
    ticket.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    start_cheat_block_timestamp(addr, 2000);
    assert(!ticket.is_valid(id, recipient), 'invalid after end');
}

#[test]
fn test_is_valid_false_for_non_holder() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let non_holder = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmN");
    ticket.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(!ticket.is_valid(id, non_holder), 'non-holder invalid');
}

#[test]
fn test_is_valid_no_time_window() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmO");
    ticket.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(ticket.is_valid(id, recipient), 'no window = always valid');
}

// ──────────────── pause_event ──────────────────────────────────────────────

#[test]
fn test_pause_and_resume_event() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmPR");
    ticket.pause_event(id, false);
    let ev = ticket.get_event(id);
    assert(!ev.active, 'should be paused');
    ticket.pause_event(id, true);
    let ev2 = ticket.get_event(id);
    assert(ev2.active, 'should be resumed');
}

// ──────────────── royalty_info ─────────────────────────────────────────────

#[test]
fn test_royalty_info() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 500_u16, "ipfs://QmR");
    stop_cheat_caller_address(addr);
    let (receiver, amount) = ticket.royalty_info(id, 10000_u256);
    assert(receiver == owner, 'receiver should be owner');
    assert(amount == 500_u256, 'royalty 5% of 10000 = 500');
}

#[test]
fn test_royalty_info_camel() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 1000_u16, "ipfs://QmRC");
    stop_cheat_caller_address(addr);
    let (_, amount) = ticket.royaltyInfo(id, 10000_u256);
    assert(amount == 1000_u256, 'royalty 10% of 10000');
}

// ──────────────── get_event ────────────────────────────────────────────────

#[test]
fn test_get_event_returns_record() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = ticket.create_event(
        42_u256, Option::Some(100_u64), Option::Some(999_u64), 250_u16, "ipfs://QmG",
    );
    stop_cheat_caller_address(addr);
    let ev = ticket.get_event(id);
    assert(ev.max_supply == 42_u256, 'max_supply');
    assert(ev.royalty_bps == 250_u16, 'royalty_bps');
    assert(ev.active, 'active by default');
    assert(ev.minted == 0_u256, 'minted starts at 0');
}

// ──────────────── version & SRC5 ──────────────────────────────────────────

#[test]
fn test_version() {
    let addr = deploy_collection();
    let ticket = IIPTicketCollectionDispatcher { contract_address: addr };
    assert(ticket.version() == "3.0.0", 'version should be 3.0.0');
}

#[test]
fn test_erc2981_interface_registered() {
    let addr = deploy_collection();
    let src5 = ISRC5Dispatcher { contract_address: addr };
    assert(src5.supports_interface(IERC2981_ID), 'should support IERC2981');
}
