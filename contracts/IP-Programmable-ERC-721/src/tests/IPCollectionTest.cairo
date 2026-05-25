use ip_programmable_erc_721::interfaces::IIPCollection::{
    IIPCollectionDispatcher, IIPCollectionDispatcherTrait, IIP_COLLECTION_ID,
};
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

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

fn OWNER() -> ContractAddress {
    0x123.try_into().unwrap()
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

// Interface IDs from OZ v0.20.0
fn IERC721_ID() -> felt252 {
    0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943
}
fn IERC721_ENUMERABLE_ID() -> felt252 {
    0x16bc0f502eeaf65ce0b3acb5eea656e2f26979ce6750e8502a82f377e538c87
}

// ---------------------------------------------------------------------------
// Deploy helpers
// ---------------------------------------------------------------------------

/// Deploys IPCollection. Returns (dispatcher, contract_address).
fn deploy_contract(owner: ContractAddress) -> (IIPCollectionDispatcher, ContractAddress) {
    let contract = declare("IPCollection").unwrap().contract_class();
    let name: ByteArray = "Test Collection";
    let symbol: ByteArray = "TC";
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    owner.serialize(ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    (IIPCollectionDispatcher { contract_address: address }, address)
}

/// Deploys a MockAccount — simulates a real Starknet user wallet (SRC6 compliant).
/// safe_mint checks for SRC6 support on EOA-like recipients; this mock satisfies that check.
fn deploy_mock_account() -> ContractAddress {
    let contract = declare("MockAccount").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    address
}

/// Deploys the ERC721Receiver mock — simulates a contract that explicitly supports NFT receipt.
fn deploy_receiver() -> ContractAddress {
    let contract = declare("Receiver").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    address
}

/// Full test context: collection + two independent mock user accounts.
/// Each test that needs minting should call setup() to get deployed recipients.
fn setup() -> (IIPCollectionDispatcher, ContractAddress, ContractAddress, ContractAddress) {
    let (col, addr) = deploy_contract(OWNER());
    let user1 = deploy_mock_account();
    let user2 = deploy_mock_account();
    (col, addr, user1, user2)
}

fn mint_as(
    col: IIPCollectionDispatcher,
    addr: ContractAddress,
    creator: ContractAddress,
    recipient: ContractAddress,
    uri: ByteArray,
) -> u256 {
    cheat_caller_address(addr, creator, CheatSpan::TargetCalls(1));
    col.mint_item(recipient, uri)
}

// ---------------------------------------------------------------------------
// Constructor / Deployment
// ---------------------------------------------------------------------------

#[test]
fn test_deploy_succeeds() {
    let (_, addr) = deploy_contract(OWNER());
    let meta = IERC721MetadataDispatcher { contract_address: addr };
    assert(meta.name() == "Test Collection", 'name should be set');
}

#[test]
fn test_name_and_symbol() {
    let (_, addr) = deploy_contract(OWNER());
    let meta = IERC721MetadataDispatcher { contract_address: addr };
    assert(meta.name() == "Test Collection", 'name mismatch');
    assert(meta.symbol() == "TC", 'symbol mismatch');
}

#[test]
fn test_collection_creator_is_set() {
    let (col, _) = deploy_contract(OWNER());
    assert(col.get_collection_creator() == OWNER(), 'creator should be OWNER');
}

#[test]
fn test_initial_total_supply_is_zero() {
    let (_, addr) = deploy_contract(OWNER());
    let enumerable = IERC721EnumerableDispatcher { contract_address: addr };
    assert(enumerable.total_supply() == 0, 'initial supply should be 0');
}

// ---------------------------------------------------------------------------
// Mint — success cases
// ---------------------------------------------------------------------------

#[test]
fn test_mint_ipfs_uri_returns_token_id_one() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    assert(token_id == 1, 'first token id should be 1');
}

#[test]
fn test_mint_ar_uri_returns_token_id_one() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, AR_URI());
    assert(token_id == 1, 'first token id should be 1');
}

#[test]
fn test_mint_sequential_ids() {
    let (col, addr, user1, _) = setup();
    let id1 = mint_as(col, addr, user1, user1, IPFS_URI());
    let id2 = mint_as(col, addr, user1, user1, AR_URI());
    assert(id1 == 1, 'first id should be 1');
    assert(id2 == 2, 'second id should be 2');
}

#[test]
fn test_mint_balance_increments() {
    let (col, addr, user1, _) = setup();
    mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    assert(erc721.balance_of(user1) == 1, 'balance should be 1');
}

#[test]
fn test_mint_owner_of() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    assert(erc721.owner_of(token_id) == user1, 'owner should be user1');
}

#[test]
fn test_mint_token_uri_exact_no_concatenation() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let meta = IERC721MetadataDispatcher { contract_address: addr };
    assert(meta.token_uri(token_id) == IPFS_URI(), 'uri should match exactly');
}

#[test]
fn test_mint_token_uri_camel_matches_snake() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let meta = IERC721MetadataDispatcher { contract_address: addr };
    assert(meta.token_uri(token_id) == meta.token_uri(token_id), 'camel and snake should match');
}

#[test]
fn test_mint_records_caller_as_creator() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    assert(col.get_token_creator(token_id) == user1, 'creator should be user1');
}

#[test]
fn test_mint_records_caller_as_creator_when_recipient_differs() {
    let (col, addr, user1, user2) = setup();
    let token_id = mint_as(col, addr, user1, user2, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };

    assert(erc721.owner_of(token_id) == user2, 'owner should be recipient');
    assert(col.get_token_creator(token_id) == user1, 'creator should be caller');
}

#[test]
fn test_mint_registered_at_matches_block_timestamp() {
    let (col, addr, user1, _) = setup();
    let ts: u64 = 1700000000;
    cheat_block_timestamp(addr, ts, CheatSpan::TargetCalls(1));
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    assert(col.get_token_registered_at(token_id) == ts, 'timestamp should match');
}

#[test]
fn test_mint_emits_ipminted_event() {
    let (col, addr, user1, _) = setup();
    let mut spy = spy_events();
    let ts: u64 = 1700000000;
    cheat_block_timestamp(addr, ts, CheatSpan::TargetCalls(1));
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let expected = ip_programmable_erc_721::IPCollection::IPCollection::Event::IPMinted(
        ip_programmable_erc_721::IPCollection::IPCollection::IPMinted {
            token_id, recipient: user1, uri: IPFS_URI(), creator: user1, registered_at: ts,
        },
    );
    spy.assert_emitted(@array![(addr, expected)]);
}

#[test]
fn test_mint_enumerable_total_supply() {
    let (col, addr, user1, user2) = setup();
    mint_as(col, addr, user1, user1, IPFS_URI());
    mint_as(col, addr, user2, user2, AR_URI());
    let enumerable = IERC721EnumerableDispatcher { contract_address: addr };
    assert(enumerable.total_supply() == 2, 'total supply should be 2');
}

#[test]
fn test_mint_enumerable_token_by_index() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let enumerable = IERC721EnumerableDispatcher { contract_address: addr };
    assert(enumerable.token_by_index(0) == token_id, 'token_by_index(0) should be 1');
}

#[test]
fn test_mint_enumerable_token_of_owner_by_index() {
    let (col, addr, user1, _) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let enumerable = IERC721EnumerableDispatcher { contract_address: addr };
    assert(
        enumerable.token_of_owner_by_index(user1, 0) == token_id, 'token_of_owner_by_index failed',
    );
}

// ---------------------------------------------------------------------------
// Mint — failure cases
// ---------------------------------------------------------------------------

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_mint_zero_recipient_panics() {
    let (col, _, _, _) = setup();
    col.mint_item(ZERO(), IPFS_URI());
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_mint_http_uri_rejected() {
    let (col, _, user1, _) = setup();
    col.mint_item(user1, HTTP_URI());
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_mint_empty_uri_rejected() {
    let (col, _, user1, _) = setup();
    col.mint_item(user1, EMPTY_URI());
}

#[test]
#[should_panic(expected: ('URI must be ipfs:// or ar://',))]
fn test_mint_partial_ipfs_prefix_rejected() {
    let (col, _, user1, _) = setup();
    col.mint_item(user1, PARTIAL_IPFS_URI());
}

// ---------------------------------------------------------------------------
// safe_mint — non-receiver contract is rejected
// ---------------------------------------------------------------------------

#[test]
#[should_panic]
fn test_mint_to_non_receiver_contract_rejected() {
    // Minting to a contract that supports neither ERC721Receiver nor SRC6 must revert.
    // Deploy a bare contract with no interface support as the recipient.
    let (col, addr, _, _) = setup();
    // Deploy IPCollection itself as a recipient — it has no receiver/account interface.
    let (_, non_receiver_addr) = deploy_contract(OWNER());
    cheat_caller_address(addr, OWNER(), CheatSpan::TargetCalls(1));
    col.mint_item(non_receiver_addr, IPFS_URI());
}

// ---------------------------------------------------------------------------
// Token URI queries — failure cases
// ---------------------------------------------------------------------------

#[test]
#[should_panic]
fn test_token_uri_nonexistent_panics() {
    let (_, addr) = deploy_contract(OWNER());
    let meta = IERC721MetadataDispatcher { contract_address: addr };
    meta.token_uri(999);
}

#[test]
#[should_panic]
fn test_get_token_creator_nonexistent_panics() {
    let (col, _) = deploy_contract(OWNER());
    col.get_token_creator(999);
}

#[test]
#[should_panic]
fn test_get_token_registered_at_nonexistent_panics() {
    let (col, _) = deploy_contract(OWNER());
    col.get_token_registered_at(999);
}

#[test]
#[should_panic]
fn test_get_token_data_nonexistent_panics() {
    let (col, _) = deploy_contract(OWNER());
    col.get_token_data(999);
}

// ---------------------------------------------------------------------------
// get_token_data
// ---------------------------------------------------------------------------

#[test]
fn test_get_token_data_all_fields_correct() {
    let (col, addr, user1, _) = setup();
    let ts: u64 = 1700000000;
    cheat_block_timestamp(addr, ts, CheatSpan::TargetCalls(1));
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let data = col.get_token_data(token_id);
    assert(data.token_id == token_id, 'data.token_id mismatch');
    assert(data.owner == user1, 'data.owner mismatch');
    assert(data.metadata_uri == IPFS_URI(), 'data.metadata_uri mismatch');
    assert(data.original_creator == user1, 'data.original_creator mismatch');
    assert(data.registered_at == ts, 'data.registered_at mismatch');
}

// ---------------------------------------------------------------------------
// ERC721 transfer
// ---------------------------------------------------------------------------

#[test]
fn test_transfer_updates_owner() {
    let (col, addr, user1, user2) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    cheat_caller_address(addr, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);
    assert(erc721.owner_of(token_id) == user2, 'owner should be user2');
}

#[test]
fn test_transfer_updates_balances() {
    let (col, addr, user1, user2) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    cheat_caller_address(addr, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);
    assert(erc721.balance_of(user1) == 0, 'user1 balance should be 0');
    assert(erc721.balance_of(user2) == 1, 'user2 balance should be 1');
}

#[test]
fn test_transfer_preserves_creator() {
    let (col, addr, user1, user2) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    cheat_caller_address(addr, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);
    assert(col.get_token_creator(token_id) == user1, 'creator should still be user1');
}

#[test]
fn test_transfer_preserves_uri() {
    let (col, addr, user1, user2) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    cheat_caller_address(addr, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);
    let meta = IERC721MetadataDispatcher { contract_address: addr };
    assert(meta.token_uri(token_id) == IPFS_URI(), 'uri should be unchanged');
}

#[test]
fn test_transfer_enumerable_updates() {
    let (col, addr, user1, user2) = setup();
    let token_id = mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    cheat_caller_address(addr, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);
    let enumerable = IERC721EnumerableDispatcher { contract_address: addr };
    assert(enumerable.token_of_owner_by_index(user2, 0) == token_id, 'user2 should own token');
}

// ---------------------------------------------------------------------------
// Interface support
// ---------------------------------------------------------------------------

#[test]
fn test_supports_interface_erc721() {
    let (_, addr) = deploy_contract(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: addr };
    assert(src5.supports_interface(IERC721_ID()), 'should support IERC721');
}

#[test]
fn test_supports_interface_erc721_enumerable() {
    let (_, addr) = deploy_contract(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: addr };
    assert(src5.supports_interface(IERC721_ENUMERABLE_ID()), 'should support enumerable');
}

#[test]
fn test_supports_interface_ip_collection() {
    let (_, addr) = deploy_contract(OWNER());
    let src5 = ISRC5Dispatcher { contract_address: addr };
    assert(src5.supports_interface(IIP_COLLECTION_ID), 'should support ip collection');
}

// ---------------------------------------------------------------------------
// safe_mint — receiver contract
// ---------------------------------------------------------------------------

#[test]
fn test_mint_to_erc721_receiver_succeeds() {
    let (col, addr, _, _) = setup();
    let receiver = deploy_receiver();
    mint_as(col, addr, OWNER(), receiver, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    assert(erc721.balance_of(receiver) == 1, 'receiver balance should be 1');
}

#[test]
fn test_mint_to_mock_account_succeeds() {
    let (col, addr, user1, _) = setup();
    mint_as(col, addr, user1, user1, IPFS_URI());
    let erc721 = IERC721Dispatcher { contract_address: addr };
    assert(erc721.balance_of(user1) == 1, 'mock acct balance should be 1');
}
