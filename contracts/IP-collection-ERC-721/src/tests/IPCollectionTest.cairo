use ip_collection::interfaces::IIPCollection::{
    IIPCollectionDispatcher, IIPCollectionDispatcherTrait, IIP_COLLECTION_ID,
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

fn NEW_OWNER() -> ContractAddress {
    0x456.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn IPFS_URI() -> ByteArray {
    "ipfs://QmTestMetadataHash"
}

fn AR_URI() -> ByteArray {
    "ar://txid123456"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/metadata.json"
}

fn EMPTY_URI() -> ByteArray {
    ""
}

fn PARTIAL_IPFS_URI() -> ByteArray {
    "ipfs:/QmFoo"
}

fn IERC721_ID() -> felt252 {
    0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943
}

fn IERC721_ENUMERABLE_ID() -> felt252 {
    0x16bc0f502eeaf65ce0b3acb5eea656e2f26979ce6750e8502a82f377e538c87
}

fn deploy_contract(owner: ContractAddress) -> (IIPCollectionDispatcher, ContractAddress) {
    let contract = declare("IPCollection").unwrap().contract_class();
    let name: ByteArray = "Owner Minted IP";
    let symbol: ByteArray = "OMIP";
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    owner.serialize(ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    (IIPCollectionDispatcher { contract_address: address }, address)
}

fn deploy_mock_account() -> ContractAddress {
    let contract = declare("MockAccount").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    address
}

fn deploy_receiver() -> ContractAddress {
    let contract = declare("Receiver").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    address
}

fn setup() -> (IIPCollectionDispatcher, ContractAddress, ContractAddress, ContractAddress) {
    let (collection, address) = deploy_contract(OWNER());
    let user1 = deploy_mock_account();
    let user2 = deploy_mock_account();
    (collection, address, user1, user2)
}

fn mint_as_owner(
    collection: IIPCollectionDispatcher,
    address: ContractAddress,
    recipient: ContractAddress,
    uri: ByteArray,
) -> u256 {
    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    collection.mint_item(recipient, uri)
}

#[test]
fn test_constructor_sets_name_symbol_owner_and_issuer() {
    let (collection, address) = deploy_contract(OWNER());
    let meta = IERC721MetadataDispatcher { contract_address: address };
    let ownable = IOwnableDispatcher { contract_address: address };

    assert(meta.name() == "Owner Minted IP", 'name mismatch');
    assert(meta.symbol() == "OMIP", 'symbol mismatch');
    assert(ownable.owner() == OWNER(), 'owner mismatch');
    assert(collection.get_collection_issuer() == OWNER(), 'issuer mismatch');
}

#[test]
#[should_panic]
fn test_constructor_rejects_zero_owner() {
    deploy_contract(ZERO());
}

#[test]
fn test_initial_total_supply_is_zero() {
    let (_, address) = deploy_contract(OWNER());
    let enumerable = IERC721EnumerableDispatcher { contract_address: address };
    assert(enumerable.total_supply() == 0, 'initial supply should be 0');
}

#[test]
fn test_owner_mint_ipfs_uri_returns_token_id_one() {
    let (collection, address, user1, _) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    assert(token_id == 1, 'first token id should be 1');
}

#[test]
fn test_owner_mint_ar_uri_returns_token_id_one() {
    let (collection, address, user1, _) = setup();
    let token_id = mint_as_owner(collection, address, user1, AR_URI());
    assert(token_id == 1, 'first token id should be 1');
}

#[test]
fn test_owner_mint_sequential_ids() {
    let (collection, address, user1, _) = setup();
    let id1 = mint_as_owner(collection, address, user1, IPFS_URI());
    let id2 = mint_as_owner(collection, address, user1, AR_URI());
    assert(id1 == 1, 'first id should be 1');
    assert(id2 == 2, 'second id should be 2');
}

#[test]
#[should_panic]
fn test_non_owner_cannot_mint() {
    let (collection, address, user1, _) = setup();
    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    collection.mint_item(user1, IPFS_URI());
}

#[test]
fn test_transferred_owner_can_mint() {
    let (collection, address, user1, _) = setup();
    let ownable = IOwnableDispatcher { contract_address: address };

    cheat_caller_address(address, OWNER(), CheatSpan::TargetCalls(1));
    ownable.transfer_ownership(NEW_OWNER());

    cheat_caller_address(address, NEW_OWNER(), CheatSpan::TargetCalls(1));
    let token_id = collection.mint_item(user1, IPFS_URI());

    assert(token_id == 1, 'token id should be 1');
    assert(collection.get_collection_issuer() == OWNER(), 'initial issuer unchanged');
    assert(collection.get_token_issuer(token_id) == NEW_OWNER(), 'issuer should be new owner');
}

#[test]
fn test_mint_updates_owner_and_balance() {
    let (collection, address, user1, _) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: address };

    assert(erc721.owner_of(token_id) == user1, 'owner should be user1');
    assert(erc721.balance_of(user1) == 1, 'balance should be 1');
}

#[test]
fn test_mint_token_uri_exact_no_concatenation() {
    let (collection, address, user1, _) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    let meta = IERC721MetadataDispatcher { contract_address: address };
    assert(meta.token_uri(token_id) == IPFS_URI(), 'uri should match');
}

#[test]
fn test_mint_issuer_is_collection_owner() {
    let (collection, address, user1, _) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    assert(collection.get_token_issuer(token_id) == OWNER(), 'issuer should be owner');
}

#[test]
fn test_mint_registered_at_matches_block_timestamp() {
    let (collection, address, user1, _) = setup();
    let ts: u64 = 1700000000;
    cheat_block_timestamp(address, ts, CheatSpan::TargetCalls(1));
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    assert(collection.get_token_registered_at(token_id) == ts, 'timestamp mismatch');
}

#[test]
fn test_mint_emits_ipminted_event() {
    let (collection, address, user1, _) = setup();
    let mut spy = spy_events();
    let ts: u64 = 1700000000;

    cheat_block_timestamp(address, ts, CheatSpan::TargetCalls(1));
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());

    let expected = ip_collection::IPCollection::IPCollection::Event::IPMinted(
        ip_collection::IPCollection::IPCollection::IPMinted {
            token_id, recipient: user1, uri: IPFS_URI(), issuer: OWNER(), registered_at: ts,
        },
    );
    spy.assert_emitted(@array![(address, expected)]);
}

#[test]
fn test_get_token_data_all_fields_correct() {
    let (collection, address, user1, _) = setup();
    let ts: u64 = 1700000000;

    cheat_block_timestamp(address, ts, CheatSpan::TargetCalls(1));
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    let data = collection.get_token_data(token_id);

    assert(data.token_id == token_id, 'token id mismatch');
    assert(data.owner == user1, 'owner mismatch');
    assert(data.metadata_uri == IPFS_URI(), 'uri mismatch');
    assert(data.issuer == OWNER(), 'issuer mismatch');
    assert(data.registered_at == ts, 'timestamp mismatch');
}

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_mint_zero_recipient_panics() {
    let (collection, address, _, _) = setup();
    mint_as_owner(collection, address, ZERO(), IPFS_URI());
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_mint_http_uri_rejected() {
    let (collection, address, user1, _) = setup();
    mint_as_owner(collection, address, user1, HTTP_URI());
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_mint_empty_uri_rejected() {
    let (collection, address, user1, _) = setup();
    mint_as_owner(collection, address, user1, EMPTY_URI());
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_mint_partial_ipfs_prefix_rejected() {
    let (collection, address, user1, _) = setup();
    mint_as_owner(collection, address, user1, PARTIAL_IPFS_URI());
}

#[test]
#[should_panic]
fn test_mint_to_non_receiver_contract_rejected() {
    let (collection, address, _, _) = setup();
    let (_, non_receiver_addr) = deploy_contract(OWNER());
    mint_as_owner(collection, address, non_receiver_addr, IPFS_URI());
}

#[test]
fn test_mint_to_erc721_receiver_succeeds() {
    let (collection, address, _, _) = setup();
    let receiver = deploy_receiver();
    mint_as_owner(collection, address, receiver, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: address };
    assert(erc721.balance_of(receiver) == 1, 'receiver balance should be 1');
}

#[test]
fn test_mint_to_mock_account_succeeds() {
    let (collection, address, user1, _) = setup();
    mint_as_owner(collection, address, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: address };
    assert(erc721.balance_of(user1) == 1, 'mock balance mismatch');
}

#[test]
#[should_panic]
fn test_token_uri_nonexistent_panics() {
    let (_, address) = deploy_contract(OWNER());
    let meta = IERC721MetadataDispatcher { contract_address: address };
    meta.token_uri(999);
}

#[test]
#[should_panic]
fn test_get_token_issuer_nonexistent_panics() {
    let (collection, _) = deploy_contract(OWNER());
    collection.get_token_issuer(999);
}

#[test]
#[should_panic]
fn test_get_token_registered_at_nonexistent_panics() {
    let (collection, _) = deploy_contract(OWNER());
    collection.get_token_registered_at(999);
}

#[test]
#[should_panic]
fn test_get_token_data_nonexistent_panics() {
    let (collection, _) = deploy_contract(OWNER());
    collection.get_token_data(999);
}

#[test]
fn test_transfer_updates_owner_and_balances() {
    let (collection, address, user1, user2) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: address };

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);

    assert(erc721.owner_of(token_id) == user2, 'owner should be user2');
    assert(erc721.balance_of(user1) == 0, 'user1 balance should be 0');
    assert(erc721.balance_of(user2) == 1, 'user2 balance should be 1');
}

#[test]
fn test_transfer_preserves_issuer_and_uri() {
    let (collection, address, user1, user2) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: address };

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);

    let meta = IERC721MetadataDispatcher { contract_address: address };
    assert(collection.get_token_issuer(token_id) == OWNER(), 'issuer changed');
    assert(meta.token_uri(token_id) == IPFS_URI(), 'uri changed');
}

#[test]
fn test_enumerable_updates() {
    let (collection, address, user1, user2) = setup();
    let token_id = mint_as_owner(collection, address, user1, IPFS_URI());
    let enumerable = IERC721EnumerableDispatcher { contract_address: address };
    assert(enumerable.total_supply() == 1, 'supply should be 1');
    assert(enumerable.token_by_index(0) == token_id, 'global index mismatch');
    assert(enumerable.token_of_owner_by_index(user1, 0) == token_id, 'owner index mismatch');

    let erc721 = IERC721Dispatcher { contract_address: address };
    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);

    assert(enumerable.token_of_owner_by_index(user2, 0) == token_id, 'new owner index mismatch');
}

#[test]
fn test_supports_interface_erc721() {
    let (_, address) = deploy_contract(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: address };
    assert(src5.supports_interface(IERC721_ID()), 'should support IERC721');
}

#[test]
fn test_supports_interface_erc721_enumerable() {
    let (_, address) = deploy_contract(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: address };
    assert(src5.supports_interface(IERC721_ENUMERABLE_ID()), 'should support enumerable');
}

#[test]
fn test_supports_interface_ip_collection() {
    let (_, address) = deploy_contract(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: address };
    assert(src5.supports_interface(IIP_COLLECTION_ID), 'should support ip collection');
}
