use ip_club::interface::{
    IIPClubCollectionDispatcher, IIPClubCollectionDispatcherTrait, IIPClubFactoryDispatcherTrait,
    IIP_CLUB_COLLECTION_ID, IIP_CLUB_FACTORY_ID,
};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
use openzeppelin_token::erc20::interface::IERC20DispatcherTrait;
use openzeppelin_token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{CheatSpan, cheat_caller_address};
use crate::utils::{
    AR_URI, CREATOR, IPFS_URI, USER1, ZERO_ADDRESS, deploy_free_club, deploy_receiver,
    deploy_reentrant_payment_token, mint_erc20, setup,
};

// ── Factory
// ─────────────────────────────────────────────────────────────────

#[test]
fn test_factory_version() {
    let TestContracts = setup();
    assert!(TestContracts.factory.version() == "1.0.0", "factory version");
}

#[test]
fn test_factory_src5() {
    let TestContracts = setup();
    let src5 = ISRC5Dispatcher { contract_address: TestContracts.factory.contract_address };
    assert!(src5.supports_interface(IIP_CLUB_FACTORY_ID), "factory SRC5");
}

#[test]
fn test_deploy_club_returns_address() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr = TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 100_u256, 0_u256, Option::None, 0_u256);
    assert!(addr.into() != 0_felt252, "should return non-zero address");
}

#[test]
fn test_two_clubs_get_different_addresses() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr1 = TestContracts
        .factory
        .deploy_club("Club A", "CA", IPFS_URI(), 100_u256, 0_u256, Option::None, 0_u256);
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr2 = TestContracts
        .factory
        .deploy_club("Club B", "CB", IPFS_URI(), 50_u256, 0_u256, Option::None, 0_u256);
    assert!(addr1 != addr2, "each club gets a unique address");
}

#[test]
#[should_panic(expected: 'Name must not be empty')]
fn test_factory_rejects_empty_name() {
    let TestContracts = setup();
    TestContracts
        .factory
        .deploy_club("", "VPS", IPFS_URI(), 100_u256, 0_u256, Option::None, 0_u256);
}

#[test]
#[should_panic(expected: 'Symbol must not be empty')]
fn test_factory_rejects_empty_symbol() {
    let TestContracts = setup();
    TestContracts
        .factory
        .deploy_club("Vipers", "", IPFS_URI(), 100_u256, 0_u256, Option::None, 0_u256);
}

// ── Collection basics
// ────────────────────────────────────────────────────────

#[test]
fn test_collection_name_symbol() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let meta = IERC721MetadataDispatcher { contract_address: club.contract_address };
    assert!(meta.name() == "Vipers", "name");
    assert!(meta.symbol() == "VPS", "symbol");
}

#[test]
fn test_collection_base_uri() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    assert!(club.base_uri() == IPFS_URI(), "base_uri");
}

#[test]
fn test_collection_accepts_ar_uri() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr = TestContracts
        .factory
        .deploy_club("Vipers", "VPS", AR_URI(), 100_u256, 0_u256, Option::None, 0_u256);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    assert!(club.base_uri() == AR_URI(), "ar:// uri accepted");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_collection_rejects_http_uri() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club(
            "Vipers",
            "VPS",
            "https://example.com/club.json",
            100_u256,
            0_u256,
            Option::None,
            0_u256,
        );
}

#[test]
fn test_collection_version() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    assert!(club.version() == "3.0.0", "collection version");
}

#[test]
fn test_collection_src5() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let src5 = ISRC5Dispatcher { contract_address: club.contract_address };
    assert!(src5.supports_interface(IIP_CLUB_COLLECTION_ID), "collection SRC5");
    assert!(src5.supports_interface(IERC2981_ID), "ERC-2981 SRC5");
}

#[test]
fn test_collection_initial_state() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    assert!(club.is_open(), "starts open");
    assert!(club.total_minted() == 0, "no tokens yet");
    assert!(club.max_supply() == 100, "max supply");
    assert!(club.entry_fee() == 0, "free");
    assert!(club.payment_token().is_none(), "no payment token");
}

// ── Mint (free)
// ──────────────────────────────────────────────────────────────

#[test]
fn test_mint_free_membership() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let member = deploy_receiver();

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let token_id = club.mint(member);

    assert!(token_id == 1, "first token is 1");
    assert!(club.total_minted() == 1, "minted count");

    let erc721 = IERC721Dispatcher { contract_address: club.contract_address };
    assert!(erc721.owner_of(token_id) == member, "member owns token");
    assert!(erc721.balance_of(member) == 1, "balance");
}

#[test]
fn test_mint_increments_sequentially() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let member = deploy_receiver();

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let t1 = club.mint(member);
    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let t2 = club.mint(member);

    assert!(t1 == 1 && t2 == 2, "sequential ids");
    assert!(club.total_minted() == 2, "two minted");
}

#[test]
fn test_mint_to_different_recipient() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let payer = USER1();
    let recipient = deploy_receiver();

    cheat_caller_address(club.contract_address, payer, CheatSpan::TargetCalls(1));
    let token_id = club.mint(recipient);

    let erc721 = IERC721Dispatcher { contract_address: club.contract_address };
    assert!(erc721.owner_of(token_id) == recipient, "recipient holds the token");
}

#[test]
#[should_panic(expected: 'Recipient is zero address')]
fn test_mint_rejects_zero_recipient() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    club.mint(ZERO_ADDRESS());
}

#[test]
#[should_panic]
fn test_mint_to_non_receiver_contract_reverts() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    // The factory itself is a contract that doesn't implement ERC-721 receiver.
    cheat_caller_address(
        club.contract_address, TestContracts.factory.contract_address, CheatSpan::TargetCalls(1),
    );
    club.mint(TestContracts.factory.contract_address);
}

// ── Supply cap
// ───────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: 'Max supply reached')]
fn test_mint_beyond_max_supply_reverts() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr = TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 1_u256, 0_u256, Option::None, 0_u256);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    let m1 = deploy_receiver();
    let m2 = deploy_receiver();

    cheat_caller_address(club.contract_address, m1, CheatSpan::TargetCalls(1));
    club.mint(m1);

    cheat_caller_address(club.contract_address, m2, CheatSpan::TargetCalls(1));
    club.mint(m2);
}

#[test]
#[should_panic(expected: 'Max supply must be > 0')]
fn test_deploy_club_rejects_zero_supply() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 0_u256, 0_u256, Option::None, 0_u256);
}

// ── set_open
// ─────────────────────────────────────────────────────────────────

#[test]
fn test_set_open_closes_and_reopens() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());

    cheat_caller_address(club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    club.set_open(false);
    assert!(!club.is_open(), "closed");

    cheat_caller_address(club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    club.set_open(true);
    assert!(club.is_open(), "reopened");
}

#[test]
#[should_panic(expected: 'Club is closed')]
fn test_mint_reverts_when_closed() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let member = deploy_receiver();

    cheat_caller_address(club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    club.set_open(false);

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    club.mint(member);
}

#[test]
#[should_panic]
fn test_only_owner_can_set_open() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());

    cheat_caller_address(club.contract_address, USER1(), CheatSpan::TargetCalls(1));
    club.set_open(false);
}

// ── Paid membership
// ──────────────────────────────────────────────────────────

#[test]
fn test_mint_with_entry_fee() {
    let TestContracts = setup();
    let fee: u256 = 1000;
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr = TestContracts
        .factory
        .deploy_club(
            "Vipers",
            "VPS",
            IPFS_URI(),
            100_u256,
            fee,
            Option::Some(TestContracts.erc20.contract_address),
            0_u256,
        );
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    let member = deploy_receiver();

    mint_erc20(TestContracts.erc20.contract_address, member, fee * 2);

    cheat_caller_address(TestContracts.erc20.contract_address, member, CheatSpan::TargetCalls(1));
    TestContracts.erc20.approve(club.contract_address, fee);

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    club.mint(member);

    assert!(TestContracts.erc20.balance_of(CREATOR()) == fee, "fee goes to owner");
    assert!(TestContracts.erc20.balance_of(member) == fee, "member paid fee");
    assert!(club.total_minted() == 1, "minted");
}

#[test]
#[should_panic(expected: 'Free club cannot use token')]
fn test_free_club_rejects_payment_token() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club(
            "Vipers",
            "VPS",
            IPFS_URI(),
            100_u256,
            0_u256,
            Option::Some(TestContracts.erc20.contract_address),
            0_u256,
        );
}

#[test]
#[should_panic(expected: 'Paid club requires token')]
fn test_paid_club_requires_payment_token() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 100_u256, 1000_u256, Option::None, 0_u256);
}

#[test]
#[should_panic(expected: 'Payment token is zero')]
fn test_paid_club_rejects_zero_payment_token() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club(
            "Vipers", "VPS", IPFS_URI(), 100_u256, 1000_u256, Option::Some(ZERO_ADDRESS()), 0_u256,
        );
}

// ── Royalties
// ────────────────────────────────────────────────────────────────

#[test]
fn test_royalty_info() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr = TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 100_u256, 0_u256, Option::None, 500_u256);
    let club = IIPClubCollectionDispatcher { contract_address: addr };
    let member = deploy_receiver();

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let token_id = club.mint(member);

    let (recipient, amount) = club.royalty_info(token_id, 10_000_u256);
    assert!(recipient == CREATOR(), "royalty to owner");
    assert!(amount == 500, "5% of 10000");
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_royalty_bps_capped() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 100_u256, 0_u256, Option::None, 10001_u256);
}

// ── token_uri
// ────────────────────────────────────────────────────────────────

#[test]
fn test_token_uri_is_per_token() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let member = deploy_receiver();

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let t1 = club.mint(member);
    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let t2 = club.mint(member);

    let meta = IERC721MetadataDispatcher { contract_address: club.contract_address };
    assert!(meta.token_uri(t1) == "ipfs://bafybeiclubmetadata/1", "token 1 uri");
    assert!(meta.token_uri(t2) == "ipfs://bafybeiclubmetadata/2", "token 2 uri");
}

#[test]
#[should_panic(expected: 'Base URI must end with /')]
fn test_deploy_rejects_uri_without_trailing_slash() {
    let TestContracts = setup();
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    TestContracts
        .factory
        .deploy_club(
            "Vipers", "VPS", "ipfs://bafybeiclubmetadata", 100_u256, 0_u256, Option::None, 0_u256,
        );
}

// ── Transferability
// ──────────────────────────────────────────────────────────

#[test]
fn test_membership_card_transfers_like_standard_erc721() {
    let TestContracts = setup();
    let club = deploy_free_club(TestContracts.factory, CREATOR());
    let member = deploy_receiver();
    let buyer = deploy_receiver();

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    let token_id = club.mint(member);

    let erc721 = IERC721Dispatcher { contract_address: club.contract_address };
    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    erc721.transfer_from(member, buyer, token_id);

    assert!(erc721.owner_of(token_id) == buyer, "buyer holds the card");
    assert!(erc721.balance_of(member) == 0, "seller no longer a member");
    assert!(erc721.balance_of(buyer) == 1, "membership moved with the card");
}

// ── Reentrancy
// ───────────────────────────────────────────────────────────────

// A reentrant payment token attempting to call mint() from within transfer_from
// runs under the reentrant token's caller context. It will fail because
// safe_mint is a non-receiver contract — the whole tx reverts atomically.
// Checks-effects-interactions order means no state persists on revert.
#[test]
#[should_panic]
fn test_reentrant_payment_token_reverts_atomically() {
    let TestContracts = setup();
    let member = deploy_receiver();
    let reentry_target = deploy_receiver();

    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    // Deploy the paid club first so we know its address.
    let fee: u256 = 500;
    let placeholder: starknet::ContractAddress = 0x999.try_into().unwrap();
    let addr = TestContracts
        .factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 100_u256, fee, Option::Some(placeholder), 0_u256);
    let reentrant_token = deploy_reentrant_payment_token(addr, reentry_target);

    // Re-deploy with the reentrant token (need a second club).
    cheat_caller_address(
        TestContracts.factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1),
    );
    let addr2 = TestContracts
        .factory
        .deploy_club(
            "Vipers2", "VPS2", IPFS_URI(), 100_u256, fee, Option::Some(reentrant_token), 0_u256,
        );
    let club = IIPClubCollectionDispatcher { contract_address: addr2 };

    mint_erc20(reentrant_token, member, fee * 10);

    cheat_caller_address(club.contract_address, member, CheatSpan::TargetCalls(1));
    club.mint(member);
}
