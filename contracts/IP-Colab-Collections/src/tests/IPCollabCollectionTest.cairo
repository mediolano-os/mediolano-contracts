use ip_colab_collections::interfaces::IIPCollaborativeCollection::{
    IIPCollaborativeCollectionDispatcher, IIPCollaborativeCollectionDispatcherTrait,
    IIP_COLLABORATIVE_COLLECTION_ID,
};
use ip_colab_collections::interfaces::IIPNft::{IIPNftDispatcher, IIPNftDispatcherTrait};
use ip_colab_collections::types::{
    STATUS_APPROVED, STATUS_ARCHIVED, STATUS_MINTED, STATUS_REJECTED, URI_POLICY_CONTENT_ADDRESSED,
};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin::token::erc721::extensions::erc721_enumerable::interface::{
    IERC721EnumerableDispatcher, IERC721EnumerableDispatcherTrait,
};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
};
use starknet::ContractAddress;

fn OWNER() -> ContractAddress {
    0x123.try_into().unwrap()
}

fn VERIFIER() -> ContractAddress {
    0x456.try_into().unwrap()
}

fn USER1() -> ContractAddress {
    0x789.try_into().unwrap()
}

fn USER2() -> ContractAddress {
    0xabc.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn ART_TYPE() -> felt252 {
    'ART'
}

fn MUSIC_TYPE() -> felt252 {
    'MUSIC'
}

fn IPFS_URI() -> ByteArray {
    "ipfs://bafyCollaborativeMetadata"
}

fn AR_URI() -> ByteArray {
    "ar://collaborativeMetadataTx"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/metadata.json"
}

fn IERC721_ID() -> felt252 {
    0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943
}

fn IERC721_ENUMERABLE_ID() -> felt252 {
    0x16bc0f502eeaf65ce0b3acb5eea656e2f26979ce6750e8502a82f377e538c87
}

fn deploy_contract(
    owner: ContractAddress,
) -> (IIPCollaborativeCollectionDispatcher, ContractAddress) {
    let ip_nft_class_hash = declare("IPNft").unwrap().contract_class();
    let contract = declare("IPCollabCollection").unwrap().contract_class();
    let name: ByteArray = "Collaborative IP";
    let symbol: ByteArray = "CIP";
    let base_uri: ByteArray = "ipfs://collection-base";
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    base_uri.serialize(ref calldata);
    owner.serialize(ref calldata);
    ip_nft_class_hash.serialize(ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    (IIPCollaborativeCollectionDispatcher { contract_address: address }, address)
}

fn setup() -> (IIPCollaborativeCollectionDispatcher, ContractAddress) {
    let (collection, address) = deploy_contract(OWNER());
    register_art_type(collection, address);
    (collection, address)
}

fn register_art_type(collection: IIPCollaborativeCollectionDispatcher, address: ContractAddress) {
    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    collection.register_contribution_type(ART_TYPE(), 70, 2000, 2);
}

fn submit_as(
    collection: IIPCollaborativeCollectionDispatcher,
    address: ContractAddress,
    contributor: ContractAddress,
    uri: ByteArray,
) -> u256 {
    cheat_caller_address(address, contributor, CheatSpan::TargetCalls(1));
    collection.submit_contribution(uri, ART_TYPE())
}

fn approve_as_owner(
    collection: IIPCollaborativeCollectionDispatcher,
    address: ContractAddress,
    contribution_id: u256,
    score: u8,
) {
    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    collection.approve_contribution(contribution_id, score);
}

fn approve_as_verifier(
    collection: IIPCollaborativeCollectionDispatcher,
    address: ContractAddress,
    contribution_id: u256,
    score: u8,
) {
    cheat_caller_address(address, VERIFIER(), CheatSpan::TargetCalls(1));
    collection.approve_contribution(contribution_id, score);
}

#[test]
fn test_constructor_sets_name_symbol_owner_and_issuer() {
    let (collection, address) = deploy_contract(OWNER());
    let ip_nft = collection.get_ip_nft();
    let meta = IERC721MetadataDispatcher { contract_address: ip_nft };
    let ownable = IOwnableDispatcher { contract_address: address };

    assert(meta.name() == "Collaborative IP", 'name mismatch');
    assert(meta.symbol() == "CIP", 'symbol mismatch');
    assert(ownable.owner() == OWNER(), 'owner mismatch');
    assert(collection.get_collection_issuer() == OWNER(), 'issuer mismatch');
    assert(collection.get_uri_policy() == URI_POLICY_CONTENT_ADDRESSED, 'policy mismatch');
}

#[test]
fn test_collection_config_exposes_indexer_fields() {
    let (collection, address) = setup();
    let config = collection.get_collection_config();

    assert(config.owner == OWNER(), 'owner mismatch');
    assert(config.collection_issuer == OWNER(), 'issuer mismatch');
    assert(config.ip_nft == collection.get_ip_nft(), 'ip nft mismatch');
    assert(config.total_contributions == 0, 'contributions mismatch');
    assert(config.total_minted == 0, 'minted mismatch');
    assert(config.uri_policy == URI_POLICY_CONTENT_ADDRESSED, 'policy mismatch');

    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);
    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    collection.mint_contribution(contribution_id);

    let after_mint = collection.get_collection_config();
    assert(after_mint.total_contributions == 1, 'post contribution mismatch');
    assert(after_mint.total_minted == 1, 'post minted mismatch');
}

#[test]
#[should_panic]
fn test_constructor_rejects_zero_owner() {
    deploy_contract(ZERO());
}

#[test]
fn test_owner_registers_contribution_type() {
    let (collection, address) = deploy_contract(OWNER());
    register_art_type(collection, address);
    let type_info = collection.get_contribution_type(ART_TYPE());
    assert(type_info.type_id == ART_TYPE(), 'type mismatch');
    assert(type_info.min_quality_score == 70, 'score mismatch');
    assert(type_info.max_supply == 2, 'supply mismatch');
}

#[test]
#[should_panic]
fn test_non_owner_cannot_register_type() {
    let (collection, address) = deploy_contract(OWNER());
    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    collection.register_contribution_type(ART_TYPE(), 70, 2000, 2);
}

#[test]
#[should_panic(expected: ('Type exists',))]
fn test_duplicate_type_rejected() {
    let (collection, address) = setup();
    register_art_type(collection, address);
}

#[test]
fn test_contributor_submits_metadata_uri() {
    let (collection, address) = setup();
    cheat_block_timestamp(address, 1000, CheatSpan::TargetCalls(1));
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    let contribution = collection.get_contribution(contribution_id);

    assert(contribution_id == 1, 'id mismatch');
    assert(contribution.contributor == USER1(), 'contributor mismatch');
    assert(contribution.token_uri == IPFS_URI(), 'uri mismatch');
    assert(contribution.submitted_at == 1000, 'timestamp mismatch');
    assert(collection.get_contributions_count() == 1, 'count mismatch');
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_submit_rejects_http_uri() {
    let (collection, address) = setup();
    submit_as(collection, address, USER1(), HTTP_URI());
}

#[test]
#[should_panic(expected: ('Deadline passed',))]
fn test_submit_rejects_after_deadline() {
    let (collection, address) = setup();
    cheat_block_timestamp(address, 2001, CheatSpan::TargetCalls(1));
    submit_as(collection, address, USER1(), IPFS_URI());
}

#[test]
fn test_owner_approves_contribution() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    let contribution = collection.get_contribution(contribution_id);
    let type_info = collection.get_contribution_type(ART_TYPE());

    assert(contribution.status == STATUS_APPROVED, 'status mismatch');
    assert(contribution.quality_score == 90, 'score mismatch');
    assert(type_info.approved_count == 1, 'approved count mismatch');
}

#[test]
#[should_panic(expected: ('Quality too low',))]
fn test_approval_rejects_low_score() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 69);
}

#[test]
fn test_verifier_can_approve_after_owner_adds() {
    let (collection, address) = setup();
    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    collection.add_verifier(VERIFIER());

    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_verifier(collection, address, contribution_id, 80);

    assert(collection.is_verifier(VERIFIER()), 'verifier missing');
    assert(collection.get_contribution(contribution_id).status == STATUS_APPROVED, 'not approved');
}

#[test]
#[should_panic(expected: ('Not verifier',))]
fn test_non_verifier_cannot_approve() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    collection.approve_contribution(contribution_id, 90);
}

#[test]
fn test_verifier_can_reject_low_quality_with_actual_score() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());

    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    collection.reject_contribution(contribution_id, 30);

    let contribution = collection.get_contribution(contribution_id);
    assert(contribution.status == STATUS_REJECTED, 'not rejected');
    assert(contribution.quality_score == 30, 'score mismatch');
}

#[test]
#[should_panic(expected: ('Contribution missing',))]
fn test_cannot_approve_nonexistent_contribution() {
    let (collection, address) = setup();
    approve_as_owner(collection, address, 99, 90);
}

#[test]
fn test_approved_contributor_mints_real_erc721() {
    let (collection, address) = setup();
    let user1 = USER1();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);

    let ip_nft = collection.get_ip_nft();
    let erc721 = IERC721Dispatcher { contract_address: ip_nft };
    let meta = IERC721MetadataDispatcher { contract_address: ip_nft };
    let contribution = collection.get_contribution(contribution_id);

    assert(token_id == 1, 'token id mismatch');
    assert(erc721.owner_of(token_id) == user1, 'owner mismatch');
    assert(erc721.balance_of(user1) == 1, 'balance mismatch');
    assert(meta.token_uri(token_id) == IPFS_URI(), 'uri mismatch');
    assert(contribution.status == STATUS_MINTED, 'not minted');
    assert(contribution.token_id == token_id, 'contribution token mismatch');
}

#[test]
#[should_panic(expected: ('Only contributor',))]
fn test_non_contributor_cannot_mint_approved_contribution() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    collection.mint_contribution(contribution_id);
}

#[test]
#[should_panic(expected: ('Not approved',))]
fn test_cannot_mint_rejected_contribution() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    collection.reject_contribution(contribution_id, 30);

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    collection.mint_contribution(contribution_id);
}

#[test]
#[should_panic(expected: ('Not approved',))]
fn test_cannot_mint_twice() {
    let (collection, address) = setup();
    let user1 = USER1();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    collection.mint_contribution(contribution_id);
    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    collection.mint_contribution(contribution_id);
}

#[test]
#[should_panic(expected: ('Max supply reached',))]
fn test_type_approval_respects_max_supply() {
    let (collection, address) = setup();
    let id1 = submit_as(collection, address, USER1(), IPFS_URI());
    let id2 = submit_as(collection, address, USER2(), AR_URI());
    let id3 = submit_as(collection, address, USER1(), IPFS_URI());

    approve_as_owner(collection, address, id1, 90);
    approve_as_owner(collection, address, id2, 95);
    approve_as_owner(collection, address, id3, 99);
}

#[test]
fn test_contributor_contribution_index() {
    let (collection, address) = setup();
    let id1 = submit_as(collection, address, USER1(), IPFS_URI());
    let id2 = submit_as(collection, address, USER1(), AR_URI());

    let ids = collection.get_contributor_contributions(USER1());
    assert(ids.len() == 2, 'length mismatch');
    assert(*ids.at(0) == id1, 'first mismatch');
    assert(*ids.at(1) == id2, 'second mismatch');
}

#[test]
fn test_token_data_links_back_to_contribution() {
    let (collection, address) = setup();
    let user1 = USER1();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    let ip_nft = collection.get_ip_nft();
    cheat_block_timestamp(ip_nft, 1500, CheatSpan::TargetCalls(1));
    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);
    let data = collection.get_token_data(token_id);

    assert(data.ip_nft == ip_nft, 'ip nft mismatch');
    assert(data.contribution_id == contribution_id, 'contribution mismatch');
    assert(data.owner == user1, 'owner mismatch');
    assert(data.contributor == user1, 'contributor mismatch');
    assert(data.metadata_uri == IPFS_URI(), 'uri mismatch');
    assert(data.registered_at == 1500, 'time mismatch');
    assert(collection.get_token_contribution(token_id) == contribution_id, 'token link mismatch');
}

#[test]
fn test_transfer_preserves_contributor_and_metadata() {
    let (collection, address) = setup();
    let user1 = USER1();
    let user2 = USER2();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);

    let ip_nft = collection.get_ip_nft();
    let erc721 = IERC721Dispatcher { contract_address: ip_nft };
    cheat_caller_address(ip_nft, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);

    assert(erc721.owner_of(token_id) == user2, 'owner mismatch');
    assert(collection.get_token_contributor(token_id) == user1, 'contributor changed');
}

#[test]
fn test_token_owner_can_archive_contribution_token() {
    let (collection, address) = setup();
    let user1 = USER1();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    collection.archive_contribution_token(token_id);

    let contribution = collection.get_contribution(contribution_id);
    let ip_nft = IIPNftDispatcher { contract_address: collection.get_ip_nft() };
    assert(contribution.status == STATUS_ARCHIVED, 'not archived');
    assert(ip_nft.is_archived(token_id), 'ip nft not archived');
}

#[test]
#[should_panic(expected: ('Only token owner',))]
fn test_non_owner_cannot_archive_contribution_token() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);

    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    collection.archive_contribution_token(token_id);
}

#[test]
#[should_panic(expected: ('Token is archived',))]
fn test_archived_token_cannot_transfer() {
    let (collection, address) = setup();
    let contribution_id = submit_as(collection, address, USER1(), IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);
    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    collection.archive_contribution_token(token_id);

    let ip_nft = collection.get_ip_nft();
    let erc721 = IERC721Dispatcher { contract_address: ip_nft };
    cheat_caller_address(ip_nft, USER1(), CheatSpan::TargetCalls(1));
    erc721.transfer_from(USER1(), USER2(), token_id);
}

#[test]
fn test_enumerable_and_interfaces() {
    let (collection, address) = setup();
    let user1 = USER1();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);

    let ip_nft = collection.get_ip_nft();
    let enumerable = IERC721EnumerableDispatcher { contract_address: ip_nft };
    assert(enumerable.total_supply() == 1, 'supply mismatch');
    assert(enumerable.token_by_index(0) == token_id, 'index mismatch');

    let nft_src5 = ISRC5Dispatcher { contract_address: ip_nft };
    assert(nft_src5.supports_interface(IERC721_ID()), 'missing erc721');
    assert(nft_src5.supports_interface(IERC721_ENUMERABLE_ID()), 'missing enumerable');

    let registry_src5 = ISRC5Dispatcher { contract_address: address };
    assert(registry_src5.supports_interface(IIP_COLLABORATIVE_COLLECTION_ID), 'missing ip iface');
}

#[test]
fn test_mint_emits_contribution_minted_event() {
    let (collection, address) = setup();
    let user1 = USER1();
    let contribution_id = submit_as(collection, address, user1, IPFS_URI());
    approve_as_owner(collection, address, contribution_id, 90);

    let mut spy = spy_events();
    cheat_block_timestamp(address, 1700, CheatSpan::TargetCalls(1));
    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    let token_id = collection.mint_contribution(contribution_id);

    let expected =
        ip_colab_collections::IPCollabCollection::IPCollabCollection::Event::ContributionMinted(
        ip_colab_collections::IPCollabCollection::IPCollabCollection::ContributionMinted {
            contribution_id,
            token_id,
            ip_nft: collection.get_ip_nft(),
            contributor: user1,
            token_uri: IPFS_URI(),
            minted_at: 1700,
        },
    );
    spy.assert_emitted(@array![(address, expected)]);
}
