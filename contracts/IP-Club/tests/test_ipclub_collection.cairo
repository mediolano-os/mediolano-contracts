use ip_club::interface::{IIPClubCollectionDispatcher, IIPClubCollectionDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
use openzeppelin_token::erc1155::interface::{
    IERC1155Dispatcher, IERC1155DispatcherTrait, IERC1155MetadataURIDispatcher,
    IERC1155MetadataURIDispatcherTrait,
};
use openzeppelin_utils::serde::SerializedAppend;
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
    let class = declare("IPClubCollection").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "IP Club Test";
    let symbol: ByteArray = "CLUB";
    let base_uri: ByteArray = "ipfs://QmCollectionMeta/";
    cd.append_serde(name);
    cd.append_serde(symbol);
    cd.append_serde(base_uri);
    cd.append_serde(owner);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

// ──────────────── create_membership
// ────────────────────────────────────────

#[test]
fn test_create_membership_assigns_token_id() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club
        .create_membership(100_u256, Option::None, Option::None, 500_u16, "ipfs://QmTest1");
    stop_cheat_caller_address(addr);
    assert(id == 1_u256, 'first tier id should be 1');
}

#[test]
fn test_second_membership_increments_id() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmA");
    let id2 = club.create_membership(20_u256, Option::None, Option::None, 0_u16, "ipfs://QmB");
    stop_cheat_caller_address(addr);
    assert(id2 == 2_u256, 'second tier id should be 2');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_create_membership_non_owner_panics() {
    let addr = deploy_collection();
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, OTHER());
    club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'Max supply is zero')]
fn test_create_membership_zero_supply_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    club.create_membership(0_u256, Option::None, Option::None, 0_u16, "ipfs://QmX");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_membership_bad_uri_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    club.create_membership(10_u256, Option::None, Option::None, 0_u16, "https://example.com");
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_create_membership_royalty_overflow_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    club.create_membership(10_u256, Option::None, Option::None, 10001_u16, "ipfs://QmX");
}

#[test]
fn test_create_membership_ar_uri_accepted() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(5_u256, Option::None, Option::None, 0_u16, "ar://txhash123");
    stop_cheat_caller_address(addr);
    assert(id == 1_u256, 'ar:// uri should be accepted');
}

#[test]
#[should_panic(expected: 'end_time before start_time')]
fn test_create_membership_inverted_window_panics() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    club
        .create_membership(
            10_u256, Option::Some(2000_u64), Option::Some(1000_u64), 0_u16, "ipfs://QmX",
        );
}

// ──────────────── mint
// ─────────────────────────────────────────────────────

#[test]
fn test_mint_increases_balance() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    let erc1155 = IERC1155Dispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(100_u256, Option::None, Option::None, 0_u16, "ipfs://QmM");
    club.mint(recipient, id, 3_u256);
    stop_cheat_caller_address(addr);
    assert(erc1155.balance_of(recipient, id) == 3_u256, 'balance should be 3');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_mint_non_owner_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmM");
    stop_cheat_caller_address(addr);
    start_cheat_caller_address(addr, OTHER());
    club.mint(recipient, id, 1_u256);
}

#[test]
#[should_panic(expected: 'Max supply reached')]
fn test_mint_exceeds_supply_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(2_u256, Option::None, Option::None, 0_u16, "ipfs://QmS");
    club.mint(recipient, id, 3_u256);
}

#[test]
#[should_panic(expected: 'Membership not found')]
fn test_mint_unknown_membership_panics() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    club.mint(recipient, 42_u256, 1_u256);
}

#[test]
fn test_mint_outside_window_succeeds() {
    // Window gates membership, not minting: pre-selling a future season pass.
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 1000);
    start_cheat_caller_address(addr, owner);
    let id = club
        .create_membership(
            10_u256, Option::Some(5000_u64), Option::Some(9000_u64), 500_u16, "ipfs://QmTier",
        );
    club.mint(owner, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(!club.is_member_of(id, owner), 'not yet valid');
    assert(!club.is_member(owner), 'not yet member');
    start_cheat_block_timestamp(addr, 6000);
    assert(club.is_member_of(id, owner), 'valid in window');
    assert(club.is_member(owner), 'member in window');
    start_cheat_block_timestamp(addr, 9000);
    assert(!club.is_member_of(id, owner), 'ended');
    assert(!club.is_member(owner), 'ended member');
}

// ──────────────── is_member / is_member_of
// ─────────────────────────────────

#[test]
fn test_is_member_of_true_for_holder_in_window() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 500);
    start_cheat_caller_address(addr, owner);
    let id = club
        .create_membership(
            10_u256, Option::Some(100_u64), Option::Some(1000_u64), 0_u16, "ipfs://QmV",
        );
    club.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(club.is_member_of(id, recipient), 'should be member');
}

#[test]
fn test_is_member_of_false_for_non_holder() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let non_holder = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmN");
    club.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(!club.is_member_of(id, non_holder), 'non-holder not member');
}

#[test]
fn test_is_member_of_no_time_window() {
    let owner = deploy_mock_account();
    let recipient = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmO");
    club.mint(recipient, id, 1_u256);
    stop_cheat_caller_address(addr);
    assert(club.is_member_of(id, recipient), 'no window = lifetime');
}

#[test]
fn test_is_member_of_false_for_unknown_membership() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    assert(!club.is_member_of(7_u256, owner), 'unknown id not member');
}

#[test]
fn test_is_member_across_tiers() {
    // Holder of any currently-valid tier is a member; expired tiers alone are
    // not enough.
    let owner = deploy_mock_account();
    let holder = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_block_timestamp(addr, 1000);
    start_cheat_caller_address(addr, owner);
    let expired = club
        .create_membership(10_u256, Option::None, Option::Some(2000_u64), 0_u16, "ipfs://QmA");
    let lifetime = club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmB");
    club.mint(holder, expired, 1_u256);
    stop_cheat_caller_address(addr);
    start_cheat_block_timestamp(addr, 3000);
    assert(!club.is_member(holder), 'expired only');
    start_cheat_caller_address(addr, owner);
    club.mint(holder, lifetime, 1_u256);
    stop_cheat_caller_address(addr);
    assert(club.is_member(holder), 'lifetime tier');
    assert(!club.is_member_of(expired, holder), 'tier expired');
    assert(club.is_member_of(lifetime, holder), 'tier lifetime');
}

#[test]
fn test_is_member_false_for_non_holder() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    assert(!club.is_member(owner), 'no tiers, no member');
}

// ──────────────── uri
// ──────────────────────────────────────────────────────

#[test]
fn test_uri_returns_membership_metadata() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    let metadata = IERC1155MetadataURIDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmU");
    stop_cheat_caller_address(addr);
    assert(metadata.uri(id) == "ipfs://QmU", 'per-tier uri');
}

#[test]
#[should_panic(expected: 'Membership not found')]
fn test_uri_unknown_id_panics() {
    let addr = deploy_collection();
    let metadata = IERC1155MetadataURIDispatcher { contract_address: addr };
    metadata.uri(99_u256);
}

// ──────────────── royalty_info
// ─────────────────────────────────────────────

#[test]
fn test_royalty_info() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 500_u16, "ipfs://QmR");
    stop_cheat_caller_address(addr);
    let (receiver, amount) = club.royalty_info(id, 10000_u256);
    assert(receiver == owner, 'receiver should be owner');
    assert(amount == 500_u256, 'royalty 5% of 10000 = 500');
}

#[test]
fn test_royalty_info_camel() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 1000_u16, "ipfs://QmRC");
    stop_cheat_caller_address(addr);
    let (_, amount) = club.royaltyInfo(id, 10000_u256);
    assert(amount == 1000_u256, 'royalty 10% of 10000');
}

// ──────────────── get_membership
// ───────────────────────────────────────────

#[test]
fn test_get_membership_returns_record() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club
        .create_membership(
            42_u256, Option::Some(100_u64), Option::Some(999_u64), 250_u16, "ipfs://QmG",
        );
    stop_cheat_caller_address(addr);
    let m = club.get_membership(id);
    assert(m.max_supply == 42_u256, 'max_supply');
    assert(m.royalty_bps == 250_u16, 'royalty_bps');
    assert(m.minted == 0_u256, 'minted starts at 0');
}

#[test]
#[should_panic(expected: 'Membership not found')]
fn test_get_membership_unknown_id_panics() {
    let addr = deploy_collection();
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    club.get_membership(99_u256);
}

// ──────────────── collection identity
// ──────────────────────────────────────

#[test]
fn test_collection_identity_views() {
    let owner = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    assert(club.name() == "IP Club Test", 'name view');
    assert(club.symbol() == "CLUB", 'symbol view');
    assert(club.base_uri() == "ipfs://QmCollectionMeta/", 'base_uri view');
}

// ──────────────── transfers
// ────────────────────────────────────────────────

#[test]
fn test_membership_is_transferable() {
    let owner = deploy_mock_account();
    let holder = deploy_mock_account();
    let buyer = deploy_mock_account();
    let addr = deploy_collection_with_owner(owner);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    let erc1155 = IERC1155Dispatcher { contract_address: addr };
    start_cheat_caller_address(addr, owner);
    let id = club.create_membership(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmT");
    club.mint(holder, id, 2_u256);
    stop_cheat_caller_address(addr);
    start_cheat_caller_address(addr, holder);
    erc1155.safe_transfer_from(holder, buyer, id, 1_u256, array![].span());
    stop_cheat_caller_address(addr);
    assert(erc1155.balance_of(buyer, id) == 1_u256, 'buyer holds card');
    assert(club.is_member(buyer), 'buyer is member');
}

// ──────────────── version & SRC5
// ───────────────────────────────────────────

#[test]
fn test_version() {
    let addr = deploy_collection();
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    assert(club.version() == "4.0.0", 'version should be 4.0.0');
}

#[test]
fn test_erc2981_interface_registered() {
    let addr = deploy_collection();
    let src5 = ISRC5Dispatcher { contract_address: addr };
    assert(src5.supports_interface(IERC2981_ID), 'should support IERC2981');
}
