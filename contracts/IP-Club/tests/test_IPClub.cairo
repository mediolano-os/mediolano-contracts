use ip_club::interfaces::IIPClub::{IIPClubDispatcherTrait, IIP_CLUB_ID};
use ip_club::interfaces::IIPClubNFT::{
    IIPClubNFTDispatcher, IIPClubNFTDispatcherTrait, IIP_CLUB_NFT_ID,
};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc20::interface::IERC20DispatcherTrait;
use openzeppelin_token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{CheatSpan, cheat_caller_address};
use crate::utils::*;

fn IPFS_URI() -> ByteArray {
    "ipfs://bafybeiclubmetadata"
}

fn AR_URI() -> ByteArray {
    "ar://club-metadata"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/club.json"
}

#[test]
fn test_create_club_successfully() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    assert!(club_id == 1, "club id should be returned");
    assert!(ip_club.get_last_club_id() == club_id, "last club id should match");

    let club_record = ip_club.get_club_record(club_id);
    // Name/symbol/metadata live on the club's NFT contract (source of truth).
    let nft_meta = IERC721MetadataDispatcher { contract_address: club_record.club_nft };
    assert!(nft_meta.name() == "Vipers", "Club name should match");
    assert!(nft_meta.symbol() == "VPs", "Club symbol should match");
    assert!(club_record.open, "Club should be open");
    assert!(club_record.creator == CREATOR(), "creator should match");
    assert!(club_record.num_members == 0, "members should start at zero");
}

#[test]
fn test_create_club_accepts_ar_uri() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    let club_id = ip_club
        .create_club("Vipers", "VPs", AR_URI(), Option::None, Option::None, Option::None);

    let club_record = ip_club.get_club_record(club_id);
    let nft_meta = IERC721MetadataDispatcher { contract_address: club_record.club_nft };
    assert!(nft_meta.name() == "Vipers", "ar-uri club should deploy");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_club_rejects_http_metadata() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    ip_club.create_club("Vipers", "VPs", HTTP_URI(), Option::None, Option::None, Option::None);
}

#[test]
#[should_panic(expected: 'Max members cannot be zero')]
fn test_create_club_with_invalid_max_members() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    ip_club.create_club("Vipers", "VPs", IPFS_URI(), Option::Some(0), Option::None, Option::None);
}

#[test]
#[should_panic(expected: 'Invalid fee configuration')]
fn test_create_club_with_payment_token_without_fee() {
    let TestContracts { ip_club, erc20_token } = initialize_contracts();

    ip_club
        .create_club(
            "Vipers",
            "VPs",
            IPFS_URI(),
            Option::None,
            Option::None,
            Option::Some(erc20_token.contract_address),
        );
}

#[test]
#[should_panic(expected: 'Invalid fee configuration')]
fn test_create_club_with_fee_without_payment_token() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::Some(1000), Option::None);
}

#[test]
#[should_panic(expected: 'Entry fee cannot be zero')]
fn test_create_club_with_zero_entry_fee() {
    let TestContracts { ip_club, erc20_token } = initialize_contracts();

    ip_club
        .create_club(
            "Vipers",
            "VPs",
            IPFS_URI(),
            Option::None,
            Option::Some(0),
            Option::Some(erc20_token.contract_address),
        );
}

#[test]
#[should_panic(expected: 'Payment token cannot be null')]
fn test_create_club_with_invalid_payment_token() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    ip_club
        .create_club(
            "Vipers",
            "VPs",
            IPFS_URI(),
            Option::None,
            Option::Some(1000),
            Option::Some(ZERO_ADDRESS()),
        );
}

#[test]
fn test_ip_club_nft_deployed_on_club_creation() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };

    assert!(ip_club_nft.get_associated_club_id() == club_id, "club id should match");
    assert!(
        ip_club_nft.get_ip_club_manager() == ip_club.contract_address,
        "manager address should match",
    );
}

#[test]
fn test_close_and_reopen_club() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, false);

    let club_record = ip_club.get_club_record(club_id);
    assert!(!club_record.open, "club should be closed");

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, true);
    assert!(ip_club.get_club_record(club_id).open, "club should reopen");
}

#[test]
#[should_panic(expected: 'Only club creator')]
fn test_only_club_creator_can_toggle_club() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, USER1(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, false);
}

#[test]
#[should_panic(expected: 'Club does not exist')]
fn test_get_club_record_rejects_missing_club() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    ip_club.get_club_record(1);
}

#[test]
fn test_join_club_successfully() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member_1 = deploy_receiver();
    let member_2 = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member_1, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    let club_record = ip_club.get_club_record(club_id);
    assert!(club_record.num_members == 1, "first member should reflect");
    assert!(ip_club.is_member(club_id, member_1), "should be a member");

    cheat_caller_address(ip_club.contract_address, member_2, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    let club_record = ip_club.get_club_record(club_id);
    assert!(club_record.num_members == 2, "second member should reflect");
    assert!(ip_club.is_member(club_id, member_2), "should be a member");
}

#[test]
fn test_join_club_mints_safe_membership_nft() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
    assert!(ip_club_nft.get_last_minted_id() == 1, "should be 1");
    assert!(ip_club_nft.has_nft(member), "should have nft");
}

#[test]
#[should_panic]
fn test_join_club_rejects_non_receiver_contract() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(
        ip_club.contract_address, ip_club.contract_address, CheatSpan::TargetCalls(1),
    );
    ip_club.join_club(club_id);
}

#[test]
fn test_join_club_with_entry_fee() {
    let TestContracts { ip_club, erc20_token } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club(
            "Vipers",
            "VPs",
            IPFS_URI(),
            Option::None,
            Option::Some(1000),
            Option::Some(erc20_token.contract_address),
        );

    mint_erc20(erc20_token.contract_address, member, 3000);
    let member_balance_before = erc20_token.balance_of(member);

    cheat_caller_address(erc20_token.contract_address, member, CheatSpan::TargetCalls(1));
    erc20_token.approve(ip_club.contract_address, 1000);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    assert!(erc20_token.balance_of(CREATOR()) == 1000, "creator balance should increment");
    assert!(
        erc20_token.balance_of(member) == member_balance_before - 1000,
        "member balance should decrement",
    );
    assert!(ip_club.is_member(club_id, member), "member should be active");
}

// Without a lock, a payment token reentering join_club runs under its own
// caller context: it can only join for itself, and since it is not an ERC-721
// receiver, safe_mint reverts the whole transaction atomically — the member
// is never charged and no state is corrupted (CEI: state final before calls).
#[test]
#[should_panic]
fn test_join_club_reentrant_payment_token_reverts_atomically() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();
    let expected_club_id = 1;
    let reentrant_token = deploy_reentrant_payment_token(
        ip_club.contract_address, expected_club_id,
    );

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club(
            "Vipers",
            "VPs",
            IPFS_URI(),
            Option::None,
            Option::Some(1000),
            Option::Some(reentrant_token),
        );

    assert!(club_id == expected_club_id, "test token should target first club");

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
}

#[test]
#[should_panic(expected: 'Already has nft')]
fn test_cannot_join_club_twice() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
}

#[test]
#[should_panic(expected: 'Club full')]
fn test_cannot_join_club_when_max_members_reached() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member_1 = deploy_receiver();
    let member_2 = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::Some(1), Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member_1, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    cheat_caller_address(ip_club.contract_address, member_2, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
}

#[test]
#[should_panic(expected: 'Club not open')]
fn test_cannot_join_when_club_is_closed() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::Some(1), Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, false);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
}

#[test]
#[should_panic(expected: 'Not club manager')]
fn test_only_ip_club_can_mint() {
    let TestContracts { ip_club, .. } = initialize_contracts();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::Some(1), Option::None, Option::None);

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };

    cheat_caller_address(ip_club_nft.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club_nft.mint(deploy_receiver());
}

#[test]
#[should_panic(expected: 'Membership is non-transferable')]
fn test_membership_nft_is_non_transferable() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member_1 = deploy_receiver();
    let member_2 = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member_1, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    let club_record = ip_club.get_club_record(club_id);
    let erc721 = IERC721Dispatcher { contract_address: club_record.club_nft };

    cheat_caller_address(club_record.club_nft, member_1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(member_1, member_2, 1);
}

#[test]
fn test_supports_custom_interfaces() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let src5 = ISRC5Dispatcher { contract_address: ip_club.contract_address };
    assert!(src5.supports_interface(IIP_CLUB_ID), "manager interface should be supported");

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    let club_record = ip_club.get_club_record(club_id);
    let nft_src5 = ISRC5Dispatcher { contract_address: club_record.club_nft };
    assert!(nft_src5.supports_interface(IIP_CLUB_NFT_ID), "nft interface should be supported");
}

#[test]
fn test_leave_club_frees_seat_and_membership() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::Some(1), Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
    assert!(ip_club.is_member(club_id, member), "should be a member");

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
    let token_id = ip_club_nft.get_last_minted_id();

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.leave_club(club_id, token_id);

    assert!(!ip_club.is_member(club_id, member), "should no longer be member");
    assert!(ip_club.get_club_record(club_id).num_members == 0, "seat should free");

    // The freed seat in this max_members=1 club is usable again.
    let member_2 = deploy_receiver();
    cheat_caller_address(ip_club.contract_address, member_2, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
    assert!(ip_club.is_member(club_id, member_2), "new member should join");
}

#[test]
fn test_leave_club_allowed_when_closed() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, false);

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
    let token_id = ip_club_nft.get_last_minted_id();

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.leave_club(club_id, token_id);
    assert!(!ip_club.is_member(club_id, member), "exit must work when closed");
}

#[test]
#[should_panic(expected: 'Not token owner')]
fn test_leave_club_rejects_foreign_token() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();
    let outsider = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
    let token_id = ip_club_nft.get_last_minted_id();

    cheat_caller_address(ip_club.contract_address, outsider, CheatSpan::TargetCalls(1));
    ip_club.leave_club(club_id, token_id);
}

#[test]
#[should_panic(expected: 'Not club manager')]
fn test_only_registry_can_burn() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);

    let club_record = ip_club.get_club_record(club_id);
    let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
    let token_id = ip_club_nft.get_last_minted_id();

    cheat_caller_address(club_record.club_nft, member, CheatSpan::TargetCalls(1));
    ip_club_nft.burn(member, token_id);
}

#[test]
fn test_reopened_club_accepts_joins() {
    let TestContracts { ip_club, .. } = initialize_contracts();
    let member = deploy_receiver();

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let club_id = ip_club
        .create_club("Vipers", "VPs", IPFS_URI(), Option::None, Option::None, Option::None);

    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, false);
    cheat_caller_address(ip_club.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ip_club.set_club_open(club_id, true);

    cheat_caller_address(ip_club.contract_address, member, CheatSpan::TargetCalls(1));
    ip_club.join_club(club_id);
    assert!(ip_club.is_member(club_id, member), "join after reopen");
}
