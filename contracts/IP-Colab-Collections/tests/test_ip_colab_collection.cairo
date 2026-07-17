use ip_colab_collections::interface::{
    IIPCollabCollectionDispatcher, IIPCollabCollectionDispatcherTrait, IIP_COLAB_COLLECTION_ID,
};
use ip_colab_collections::types::ContributionStatus;
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
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

fn OTHER() -> ContractAddress {
    0x333.try_into().unwrap()
}

fn deploy_mock_account() -> ContractAddress {
    let class = declare("MockAccount").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

fn deploy_collection_with_owner(owner: ContractAddress) -> ContractAddress {
    let class = declare("IPCollabCollection").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    let name: ByteArray = "Collab Test";
    let symbol: ByteArray = "COLAB";
    let base_uri: ByteArray = "ipfs://QmCollectionMeta/";
    cd.append_serde(name);
    cd.append_serde(symbol);
    cd.append_serde(base_uri);
    cd.append_serde(owner);
    let (addr, _) = class.deploy(@cd).unwrap();
    addr
}

/// owner + collection + one contributor account.
fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    let owner = deploy_mock_account();
    let collection = deploy_collection_with_owner(owner);
    let contributor = deploy_mock_account();
    (owner, collection, contributor)
}

fn create_type(
    collection: ContractAddress, owner: ContractAddress, max_supply: u256, deadline: Option<u64>,
) -> u256 {
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    let id = dispatcher.create_contribution_type(max_supply, deadline, "ipfs://QmBrief");
    stop_cheat_caller_address(collection);
    id
}

fn submit_as(collection: ContractAddress, contributor: ContractAddress, type_id: u256) -> u256 {
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, contributor);
    let id = dispatcher.submit_contribution(type_id, "ipfs://QmPiece", 500_u16);
    stop_cheat_caller_address(collection);
    id
}

fn approve_as(collection: ContractAddress, reviewer: ContractAddress, contribution_id: u256) {
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, reviewer);
    dispatcher.approve_contribution(contribution_id);
    stop_cheat_caller_address(collection);
}

fn mint_as(
    collection: ContractAddress, contributor: ContractAddress, contribution_id: u256,
) -> u256 {
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, contributor);
    let token_id = dispatcher.mint_contribution(contribution_id);
    stop_cheat_caller_address(collection);
    token_id
}

// ──────────────── create_contribution_type
// ────────────────

#[test]
fn test_create_type_assigns_sequential_ids() {
    let (owner, collection, _) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let id1 = create_type(collection, owner, 10_u256, Option::None);
    let id2 = create_type(collection, owner, 20_u256, Option::Some(1000_u64));
    assert(id1 == 1_u256, 'first type id should be 1');
    assert(id2 == 2_u256, 'second type id should be 2');
    assert(dispatcher.type_count() == 2_u256, 'type count should be 2');
    let t = dispatcher.get_contribution_type(id2);
    assert(t.max_supply == 20_u256, 'wrong max supply');
    assert(t.submission_deadline == Option::Some(1000_u64), 'wrong deadline');
    assert(t.metadata_uri == "ipfs://QmBrief", 'wrong type uri');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_create_type_non_owner_panics() {
    let (_, collection, _) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, OTHER());
    dispatcher.create_contribution_type(10_u256, Option::None, "ipfs://QmBrief");
}

#[test]
#[should_panic(expected: 'Max supply is zero')]
fn test_create_type_zero_supply_panics() {
    let (owner, collection, _) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_contribution_type(0_u256, Option::None, "ipfs://QmBrief");
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_type_bad_uri_panics() {
    let (owner, collection, _) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    start_cheat_caller_address(collection, owner);
    dispatcher.create_contribution_type(10_u256, Option::None, "https://example.com");
}

#[test]
#[should_panic(expected: 'Type not found')]
fn test_get_unknown_type_panics() {
    let (_, collection, _) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    dispatcher.get_contribution_type(99_u256);
}

// ──────────────── submit_contribution
// ────────────────

#[test]
fn test_submit_records_contribution() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    assert(id == 1_u256, 'first contribution id 1');
    assert(dispatcher.contribution_count() == 1_u256, 'count should be 1');
    let c = dispatcher.get_contribution(id);
    assert(c.contributor == contributor, 'wrong contributor');
    assert(c.type_id == type_id, 'wrong type');
    assert(c.status == ContributionStatus::Pending, 'should be pending');
    assert(c.royalty_bps == 500_u16, 'wrong royalty');
    assert(c.token_id == 0_u256, 'token id should be 0');
}

#[test]
fn test_submit_open_ended_type_late() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    start_cheat_block_timestamp(collection, 999_999_u64);
    let id = submit_as(collection, contributor, type_id);
    assert(id == 1_u256, 'open-ended accepts late submit');
}

#[test]
fn test_submit_before_deadline() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::Some(1000_u64));
    start_cheat_block_timestamp(collection, 999_u64);
    let id = submit_as(collection, contributor, type_id);
    assert(id == 1_u256, 'submit before deadline works');
}

#[test]
#[should_panic(expected: 'Submissions closed')]
fn test_submit_after_deadline_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::Some(1000_u64));
    start_cheat_block_timestamp(collection, 1000_u64);
    submit_as(collection, contributor, type_id);
}

#[test]
#[should_panic(expected: 'Type not found')]
fn test_submit_unknown_type_panics() {
    let (_, collection, contributor) = setup();
    submit_as(collection, contributor, 42_u256);
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_submit_bad_uri_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    start_cheat_caller_address(collection, contributor);
    dispatcher.submit_contribution(type_id, "https://example.com", 0_u16);
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_submit_royalty_overflow_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    start_cheat_caller_address(collection, contributor);
    dispatcher.submit_contribution(type_id, "ipfs://QmPiece", 10001_u16);
}

// ──────────────── approve / reject
// ────────────────

#[test]
fn test_owner_approves_pending() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    assert(dispatcher.get_contribution(id).status == ContributionStatus::Approved, 'not approved');
    assert(dispatcher.get_contribution_type(type_id).approved_count == 1_u256, 'count not up');
}

#[test]
fn test_verifier_approves_pending() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let verifier = deploy_mock_account();
    start_cheat_caller_address(collection, owner);
    dispatcher.add_verifier(verifier);
    stop_cheat_caller_address(collection);
    assert(dispatcher.is_verifier(verifier), 'should be verifier');

    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, verifier, id);
    assert(dispatcher.get_contribution(id).status == ContributionStatus::Approved, 'not approved');
}

#[test]
#[should_panic(expected: 'Not a verifier')]
fn test_non_verifier_approve_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, OTHER(), id);
}

#[test]
#[should_panic(expected: 'Not a verifier')]
fn test_removed_verifier_approve_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let verifier = deploy_mock_account();
    start_cheat_caller_address(collection, owner);
    dispatcher.add_verifier(verifier);
    dispatcher.remove_verifier(verifier);
    stop_cheat_caller_address(collection);

    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, verifier, id);
}

#[test]
fn test_reject_then_resubmit() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);

    start_cheat_caller_address(collection, owner);
    dispatcher.reject_contribution(id);
    stop_cheat_caller_address(collection);
    assert(dispatcher.get_contribution(id).status == ContributionStatus::Rejected, 'not rejected');
    assert(dispatcher.get_contribution_type(type_id).approved_count == 0_u256, 'no supply used');

    let id2 = submit_as(collection, contributor, type_id);
    assert(id2 == 2_u256, 'resubmit gets new id');
}

#[test]
#[should_panic(expected: 'Not pending')]
fn test_double_approve_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    approve_as(collection, owner, id);
}

#[test]
#[should_panic(expected: 'Not pending')]
fn test_reject_after_approve_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    start_cheat_caller_address(collection, owner);
    dispatcher.reject_contribution(id);
}

#[test]
#[should_panic(expected: 'Max supply reached')]
fn test_approve_beyond_supply_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 1_u256, Option::None);
    let id1 = submit_as(collection, contributor, type_id);
    let id2 = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id1);
    approve_as(collection, owner, id2);
}

#[test]
fn test_approve_after_deadline_allowed() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::Some(1000_u64));
    start_cheat_block_timestamp(collection, 500_u64);
    let id = submit_as(collection, contributor, type_id);
    start_cheat_block_timestamp(collection, 2000_u64);
    approve_as(collection, owner, id);
    assert(
        dispatcher.get_contribution(id).status == ContributionStatus::Approved,
        'review open after deadline',
    );
}

#[test]
#[should_panic(expected: 'Contribution not found')]
fn test_approve_unknown_contribution_panics() {
    let (owner, collection, _) = setup();
    approve_as(collection, owner, 42_u256);
}

// ──────────────── mint_contribution
// ────────────────

#[test]
fn test_mint_approved_contribution() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let erc721 = IERC721Dispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);

    start_cheat_block_timestamp(collection, 777_u64);
    let token_id = mint_as(collection, contributor, id);

    assert(token_id == 1_u256, 'first token id should be 1');
    assert(erc721.owner_of(token_id) == contributor, 'contributor should own');
    let c = dispatcher.get_contribution(id);
    assert(c.status == ContributionStatus::Minted, 'not minted');
    assert(c.token_id == token_id, 'wrong token id');
    assert(dispatcher.get_token_contribution(token_id) == id, 'wrong back-reference');
    assert(dispatcher.token_registered_at(token_id) == 777_u64, 'wrong provenance time');
    assert(dispatcher.get_contribution_type(type_id).minted_count == 1_u256, 'minted count');
}

#[test]
fn test_token_uri_resolves_per_contribution() {
    let (owner, collection, contributor) = setup();
    let metadata = IERC721MetadataDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);
    assert(metadata.token_uri(token_id) == "ipfs://QmPiece", 'wrong token uri');
    assert(metadata.name() == "Collab Test", 'wrong name');
    assert(metadata.symbol() == "COLAB", 'wrong symbol');
}

#[test]
#[should_panic(expected: 'Only contributor')]
fn test_mint_by_other_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    mint_as(collection, OTHER(), id);
}

#[test]
#[should_panic(expected: 'Not approved')]
fn test_mint_pending_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    mint_as(collection, contributor, id);
}

#[test]
#[should_panic(expected: 'Not approved')]
fn test_double_mint_panics() {
    let (owner, collection, contributor) = setup();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    mint_as(collection, contributor, id);
    mint_as(collection, contributor, id);
}

// ──────────────── archive
// ────────────────

#[test]
fn test_archive_blocks_transfer() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);

    start_cheat_caller_address(collection, contributor);
    dispatcher.archive(token_id);
    stop_cheat_caller_address(collection);
    assert(dispatcher.is_archived(token_id), 'should be archived');
}

#[test]
#[should_panic(expected: 'Token is archived')]
fn test_transfer_archived_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let erc721 = IERC721Dispatcher { contract_address: collection };
    let recipient = deploy_mock_account();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);

    start_cheat_caller_address(collection, contributor);
    dispatcher.archive(token_id);
    erc721.transfer_from(contributor, recipient, token_id);
}

#[test]
fn test_transfer_unarchived_works() {
    let (owner, collection, contributor) = setup();
    let erc721 = IERC721Dispatcher { contract_address: collection };
    let recipient = deploy_mock_account();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);

    start_cheat_caller_address(collection, contributor);
    erc721.transfer_from(contributor, recipient, token_id);
    stop_cheat_caller_address(collection);
    assert(erc721.owner_of(token_id) == recipient, 'transfer should work');
}

#[test]
#[should_panic(expected: 'Only token owner')]
fn test_archive_by_non_owner_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);
    start_cheat_caller_address(collection, OTHER());
    dispatcher.archive(token_id);
}

#[test]
#[should_panic(expected: 'Already archived')]
fn test_double_archive_panics() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);
    start_cheat_caller_address(collection, contributor);
    dispatcher.archive(token_id);
    dispatcher.archive(token_id);
}

// ──────────────── royalty + views + discovery
// ────────────────

#[test]
fn test_royalty_receiver_is_contributor() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);

    let (receiver, amount) = dispatcher.royalty_info(token_id, 20000_u256);
    assert(receiver == contributor, 'receiver should be contributor');
    assert(amount == 1000_u256, 'wrong royalty amount'); // 5% of 20000
}

#[test]
fn test_royalty_survives_transfer() {
    let (owner, collection, contributor) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    let erc721 = IERC721Dispatcher { contract_address: collection };
    let recipient = deploy_mock_account();
    let type_id = create_type(collection, owner, 10_u256, Option::None);
    let id = submit_as(collection, contributor, type_id);
    approve_as(collection, owner, id);
    let token_id = mint_as(collection, contributor, id);

    start_cheat_caller_address(collection, contributor);
    erc721.transfer_from(contributor, recipient, token_id);
    stop_cheat_caller_address(collection);

    let (receiver, _) = dispatcher.royalty_info(token_id, 20000_u256);
    assert(receiver == contributor, 'creator royalty is immutable');
}

#[test]
fn test_collection_identity_views() {
    let (_, collection, _) = setup();
    let dispatcher = IIPCollabCollectionDispatcher { contract_address: collection };
    assert(dispatcher.base_uri() == "ipfs://QmCollectionMeta/", 'wrong base uri');
    assert(dispatcher.version() == "1.0.0", 'wrong version');
    assert(dispatcher.type_count() == 0_u256, 'type count should be 0');
    assert(dispatcher.contribution_count() == 0_u256, 'count should be 0');
}

#[test]
fn test_src5_interfaces_registered() {
    let (_, collection, _) = setup();
    let src5 = ISRC5Dispatcher { contract_address: collection };
    assert(src5.supports_interface(IIP_COLAB_COLLECTION_ID), 'service id missing');
    assert(src5.supports_interface(IERC2981_ID), 'erc2981 id missing');
}
