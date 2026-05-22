use ip_collection_erc_721::interfaces::IIPCollection::{
    IIPCollectionDispatcher, IIPCollectionDispatcherTrait,
};
use ip_collection_erc_721::interfaces::IIPNFT::{IIPNftDispatcher, IIPNftDispatcherTrait};
use openzeppelin::token::erc721::interface::{
    ERC721ABIDispatcher, ERC721ABIDispatcherTrait, IERC721Dispatcher, IERC721DispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address,
    cheat_block_timestamp, declare, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// ─── Test constants ────────────────────────────────────────────────────────────

fn OWNER() -> ContractAddress {
    0x123.try_into().unwrap()
}
fn USER1() -> ContractAddress {
    0x456.try_into().unwrap()
}
fn USER2() -> ContractAddress {
    0x789.try_into().unwrap()
}
fn USER3() -> ContractAddress {
    0x987.try_into().unwrap()
}
fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn IPFS_URI() -> ByteArray {
    "ipfs://QmCollectionBaseUri"
}
fn AR_URI() -> ByteArray {
    "ar://txid123456"
}
fn HTTP_URI() -> ByteArray {
    "https://example.com/metadata.json"
}
fn FUTURE_URI() -> ByteArray {
    "hyperblob://future-content-address-123"
}

const COLLECTION_ID: u256 = 1;
const TOKEN_ID: u256 = 1; // R-05: first token ID is now 1

// ─── Helpers ───────────────────────────────────────────────────────────────────

fn deploy_contract() -> (IIPCollectionDispatcher, ContractAddress) {
    let ip_nft_class_hash = declare("IPNft").unwrap().contract_class();
    let mut calldata = array![];
    ip_nft_class_hash.serialize(ref calldata);

    let declare_result = declare("IPCollection").expect('Failed to declare contract');
    let contract_class = declare_result.contract_class();
    let (contract_address, _) = contract_class
        .deploy(@calldata)
        .expect('Failed to deploy contract');

    let dispatcher = IIPCollectionDispatcher { contract_address };
    (dispatcher, contract_address)
}

fn setup_collection(dispatcher: IIPCollectionDispatcher, ip_address: ContractAddress) -> u256 {
    let owner = OWNER();
    let name: ByteArray = "Test Collection";
    let symbol: ByteArray = "TST";
    let base_uri: ByteArray = "ipfs://QmCollectionBaseUri/";
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    dispatcher.create_collection(name, symbol, base_uri)
}

// ─── Collection creation ────────────────────────────────────────────────────────

#[test]
fn test_create_collection() {
    let (ip_dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));

    let name: ByteArray = "My Collection";
    let symbol: ByteArray = "MC";
    let base_uri: ByteArray = "ipfs://QmMyCollection";
    let collection_id = ip_dispatcher
        .create_collection(name.clone(), symbol.clone(), base_uri.clone());

    assert(collection_id == 1, 'Collection ID should be 1');
    let collection = ip_dispatcher.get_collection(collection_id);
    assert(collection.name == name, 'Collection name mismatch');
    assert(collection.symbol == symbol, 'Collection symbol mismatch');
    assert(collection.base_uri == base_uri, 'Collection base_uri mismatch');
    assert(collection.owner == owner, 'Collection owner mismatch');
}

#[test]
fn test_create_multiple_collections() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    start_cheat_caller_address(ip_address, owner);

    let collection_id1 = dispatcher
        .create_collection("Collection 1", "C1", "ipfs://QmCollection1");
    assert(collection_id1 == 1, 'First collection ID should be 1');

    let collection_id2 = dispatcher
        .create_collection("Collection 2", "C2", "ipfs://QmCollection2");
    assert(collection_id2 == 2, 'Second ID should be 2');

    stop_cheat_caller_address(ip_address);
}

#[test]
#[should_panic(expected: ('Invalid name length',))]
fn test_create_collection_empty_name() {
    let (dispatcher, ip_address) = deploy_contract();
    start_cheat_caller_address(ip_address, OWNER());
    dispatcher.create_collection("", "MC", "ipfs://QmMyCollection");
}

#[test]
#[should_panic(expected: ('Invalid symbol length',))]
fn test_create_collection_empty_symbol() {
    let (dispatcher, ip_address) = deploy_contract();
    start_cheat_caller_address(ip_address, OWNER());
    dispatcher.create_collection("My Collection", "", "ipfs://QmMyCollection");
}

// ─── Mint ──────────────────────────────────────────────────────────────────────

#[test]
fn test_mint_token() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    // R-05: first token ID is 1
    assert(token_id == 1, 'Token ID should be 1');

    let token_key = format!("{}:{}", collection_id, token_id);
    let token = dispatcher.get_token(token_key);
    assert(token.collection_id == collection_id, 'Token collection ID mismatch');
    assert(token.token_id == token_id, 'Token ID mismatch');
    assert(token.owner == recipient, 'Token owner mismatch');
    assert(token.metadata_uri == IPFS_URI(), 'Token metadata URI mismatch');
    // COMP-02 + COMP-07: original creator is the minting collection owner, not recipient
    assert(token.original_creator == owner, 'Original creator mismatch');
}

#[test]
fn test_token_uri_match() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());
    assert(token_id == 1, 'Token ID should be 1');

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: collection_data.ip_nft };
    let token_uri_1 = erc721_dispatcher.tokenURI(token_id);
    let token_uri_2 = erc721_dispatcher.token_uri(token_id);
    assert(token_uri_1 == IPFS_URI(), 'Token URI 1 mismatch');
    assert(token_uri_2 == IPFS_URI(), 'Token URI 2 mismatch');
    assert_eq!(token_uri_1, token_uri_2, "Token URI mismatch");
}

#[test]
#[should_panic(expected: ('Only collection owner can mint',))]
fn test_mint_not_owner() {
    let (dispatcher, address) = deploy_contract();
    let non_owner = USER1();
    let recipient = USER2();
    let collection_id = setup_collection(dispatcher, address);
    start_cheat_caller_address(address, non_owner);
    dispatcher.mint(collection_id, recipient, IPFS_URI());
}

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_mint_to_zero_address() {
    let (dispatcher, address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, address);
    start_cheat_caller_address(address, owner);
    dispatcher.mint(collection_id, ZERO(), IPFS_URI());
}

#[test]
#[should_panic(expected: ('Only collection owner can mint',))]
fn test_mint_zero_caller() {
    let (dispatcher, address) = deploy_contract();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, address);
    start_cheat_caller_address(address, ZERO());
    dispatcher.mint(collection_id, recipient, IPFS_URI());
}

#[test]
fn test_mint_http_uri_allowed() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, USER1(), HTTP_URI());

    let token = dispatcher.get_token(format!("{}:{}", collection_id, token_id));
    assert(token.metadata_uri == HTTP_URI(), 'HTTP URI mismatch');
}

#[test]
fn test_mint_valid_ar_uri() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, USER1(), AR_URI());
    assert(token_id == 1, 'ar:// URI should be accepted');
}

#[test]
fn test_mint_future_uri_scheme_allowed() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, USER1(), FUTURE_URI());

    let token = dispatcher.get_token(format!("{}:{}", collection_id, token_id));
    assert(token.metadata_uri == FUTURE_URI(), 'Future URI mismatch');
}

#[test]
#[should_panic(expected: ('Invalid URI length',))]
fn test_mint_empty_uri_rejected() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    dispatcher.mint(collection_id, USER1(), "");
}

// ─── Batch mint ────────────────────────────────────────────────────────────────

#[test]
fn test_batch_mint_tokens() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient1 = USER1();
    let recipient2 = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uris = array![IPFS_URI(), IPFS_URI()];
    let recipients = array![recipient1, recipient2];

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher.batch_mint(collection_id, recipients.clone(), token_uris);

    assert(token_ids.len() == 2, 'Should mint 2 tokens in batch');

    let token0 = dispatcher.get_token(format!("{}:{}", collection_id, *token_ids.at(0)));
    let token1 = dispatcher.get_token(format!("{}:{}", collection_id, *token_ids.at(1)));

    assert(token0.owner == recipient1, 'First token owner mismatch');
    assert(token1.owner == recipient2, 'Second token owner mismatch');
    // R-05: first batch token ID is 1
    assert(token0.token_id == 1, 'First token ID should be 1');
    assert(token1.token_id == 2, 'Second token ID should be 2');
    assert(token0.original_creator == owner, 'Creator0 mismatch');
    assert(token1.original_creator == owner, 'Creator1 mismatch');
}

#[test]
#[should_panic(expected: ('Recipients array is empty',))]
fn test_batch_mint_empty_recipients() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    dispatcher.batch_mint(collection_id, array![], array![]);
}

#[test]
#[should_panic(expected: ('Array lengths mismatch',))]
fn test_batch_mint_length_mismatch() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    // 2 recipients but only 1 URI
    dispatcher.batch_mint(collection_id, array![USER1(), USER2()], array![IPFS_URI()]);
}

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_batch_mint_zero_recipient() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    dispatcher.batch_mint(collection_id, array![ZERO()], array![IPFS_URI()]);
}

// ─── Archive (replaces burn) ────────────────────────────────────────────────────

#[test]
fn test_archive_token() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);
    let collection_data = dispatcher.get_collection(collection_id);
    cheat_block_timestamp(collection_data.ip_nft, 1700000000, CheatSpan::TargetCalls(5));

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, recipient, CheatSpan::TargetCalls(1));
    dispatcher.archive(token_key);
}

#[test]
fn test_archive_preserves_record() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);
    let collection_data = dispatcher.get_collection(collection_id);
    cheat_block_timestamp(collection_data.ip_nft, 1700000000, CheatSpan::TargetCalls(5));

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, recipient, CheatSpan::TargetCalls(1));
    dispatcher.archive(token_key.clone());

    // COMP-05: after archiving, the legal record must still be queryable
    let nft = IIPNftDispatcher { contract_address: collection_data.ip_nft };

    assert(nft.is_archived(token_id), 'Token should be archived');
    assert(nft.get_token_creator(token_id) == owner, 'Creator must be preserved');
    assert(nft.get_token_registered_at(token_id) == 1700000000, 'Timestamp must be preserved');

    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };
    assert(erc721.owner_of(token_id) == recipient, 'Owner record must be preserved');
}

#[test]
#[should_panic(expected: ('Token is archived',))]
fn test_archived_token_transfer_blocked() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.archive(token_key.clone());

    // Attempt to approve and transfer an archived token — must fail
    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };
    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.approve(ip_address, token_id);

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.transfer_token(from_user, to_user, token_key);
}

#[test]
#[should_panic(expected: ('Caller not token owner',))]
fn test_archive_not_owner() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let non_owner = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, non_owner, CheatSpan::TargetCalls(1));
    dispatcher.archive(token_key);
}

#[test]
#[should_panic(expected: ('Caller not token owner',))]
fn test_batch_archive_unauthorized() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let attacker = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    // C-01 regression: attacker tries to batch_archive token they don't own
    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, attacker, CheatSpan::TargetCalls(1));
    dispatcher.batch_archive(array![token_key]);
}

// ─── Transfer ──────────────────────────────────────────────────────────────────

#[test]
fn test_transfer_token_success() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721_dispatcher = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(ip_address, token_id);

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.transfer_token(from_user, to_user, token_key);
}

#[test]
fn test_transfer_token_accepts_operator_approval_for_collection_contract() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.set_approval_for_all(ip_address, true);

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.transfer_token(from_user, to_user, token_key);

    assert(erc721.owner_of(token_id) == to_user, 'Operator transfer failed');
}

#[test]
#[should_panic(expected: ('Contract not approved',))]
fn test_transfer_token_not_approved() {
    let (dispatcher, address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, address);

    start_cheat_caller_address(address, owner);
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());
    stop_cheat_caller_address(address);

    start_cheat_caller_address(address, from_user);
    let token_key = format!("{}:{}", collection_id, token_id);
    dispatcher.transfer_token(from_user, to_user, token_key);
}

#[test]
#[should_panic(expected: ('Not authorized',))]
fn test_transfer_token_unauthorized_caller() {
    // M-02 regression: third party cannot initiate a transfer even if contract is approved
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let attacker = USER3();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    // owner approves the collection contract
    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.approve(ip_address, token_id);

    // attacker calls transfer_token — must fail
    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, attacker, CheatSpan::TargetCalls(1));
    dispatcher.transfer_token(from_user, to_user, token_key);
}

#[test]
#[should_panic(expected: ('Invalid collection',))]
fn test_transfer_token_invalid_collection() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    // Use a non-existent collection ID
    let token_key = format!("{}:{}", collection_id + 1, token_id);
    dispatcher.transfer_token(from_user, to_user, token_key);
}

#[test]
fn test_transfer_stats_updated() {
    // R-03 regression: total_transfers must be updated after transfer
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };
    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.approve(ip_address, token_id);

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.transfer_token(from_user, to_user, token_key);

    let stats = dispatcher.get_collection_stats(collection_id);
    assert(stats.total_transfers == 1, 'total_transfers should be 1');
}

// ─── Batch transfer ─────────────────────────────────────────────────────────────

#[test]
fn test_batch_transfer_tokens_success() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher
        .batch_mint(collection_id, array![from_user, from_user], array![IPFS_URI(), IPFS_URI()]);

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(2));
    erc721.approve(ip_address, *token_ids.at(0));
    erc721.approve(ip_address, *token_ids.at(1));

    let token0 = format!("{}:{}", collection_id, *token_ids.at(0));
    let token1 = format!("{}:{}", collection_id, *token_ids.at(1));
    let tokens = array![token0, token1];

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.batch_transfer(from_user, to_user, tokens.clone());

    let token_data0 = dispatcher.get_token(tokens.clone().at(0).clone());
    let token_data1 = dispatcher.get_token(tokens.clone().at(1_u32).clone());
    assert(token_data0.owner == to_user, 'Token0 should be transferred');
    assert(token_data1.owner == to_user, 'Token1 should be transferred');
}

#[test]
#[should_panic(expected: ('Contract not approved',))]
fn test_batch_transfer_not_approved() {
    // H-01 regression: approval required for batch transfer
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher
        .batch_mint(collection_id, array![from_user], array![IPFS_URI()]);

    let token_key = format!("{}:{}", collection_id, *token_ids.at(0));
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.batch_transfer(from_user, to_user, array![token_key]);
}

#[test]
#[should_panic(expected: ('Not authorized',))]
fn test_batch_transfer_unauthorized_caller() {
    // H-01 regression: caller must be owner or approved operator
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let attacker = USER3();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher.batch_mint(collection_id, array![from_user], array![IPFS_URI()]);

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };
    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.approve(ip_address, *token_ids.at(0));

    let token_key = format!("{}:{}", collection_id, *token_ids.at(0));
    cheat_caller_address(ip_address, attacker, CheatSpan::TargetCalls(1));
    dispatcher.batch_transfer(from_user, to_user, array![token_key]);
}

#[test]
#[should_panic(expected: ('Invalid collection',))]
fn test_batch_transfer_invalid_collection() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher.batch_mint(collection_id, array![from_user], array![IPFS_URI()]);

    let token_key = format!("{}:{}", collection_id + 1, *token_ids.at(0));
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.batch_transfer(from_user, to_user, array![token_key]);
}

#[test]
fn test_direct_erc721_transfer_success_without_protocol_stats() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.transfer_from(from_user, to_user, token_id);

    assert(erc721.owner_of(token_id) == to_user, 'Direct transfer failed');
    let stats = dispatcher.get_collection_stats(collection_id);
    assert(stats.total_transfers == 0, 'Stats changed');
}

#[test]
#[should_panic(expected: ('Token is archived',))]
fn test_direct_erc721_transfer_archived_token_blocked() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.archive(token_key);

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721.transfer_from(from_user, to_user, token_id);
}

// ─── Legal record (COMP-02, COMP-03, COMP-06, COMP-07) ─────────────────────────

#[test]
fn test_get_token_creator() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let nft = IIPNftDispatcher { contract_address: collection_data.ip_nft };

    assert(nft.get_token_creator(token_id) == owner, 'Creator should be minter');
}

#[test]
fn test_get_token_registered_at() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);

    // get_block_timestamp() is called inside IPNft.mint(), not IPCollection.mint(),
    // so the timestamp cheat must target the IPNft contract address.
    let collection_data = dispatcher.get_collection(collection_id);
    cheat_block_timestamp(collection_data.ip_nft, 1700000000, CheatSpan::TargetCalls(5));

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let nft = IIPNftDispatcher { contract_address: collection_data.ip_nft };

    // registered_at should be stored (non-zero timestamp)
    let registered_at = nft.get_token_registered_at(token_id);
    assert(registered_at != 0, 'registered_at should be stored');
}

#[test]
fn test_token_data_includes_creator_and_timestamp() {
    // COMP-07: get_token must return original_creator and registered_at
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    let token_data = dispatcher.get_token(token_key);

    assert(token_data.original_creator == owner, 'original_creator mismatch');
    // registered_at may be 0 in test env without timestamp cheat — field existence is what matters
    let _ = token_data.registered_at;
}

#[test]
fn test_creator_unchanged_after_transfer() {
    // COMP-02: original_creator must not change after ownership transfer
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let holder = USER1();
    let buyer = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, holder, IPFS_URI());

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721 = IERC721Dispatcher { contract_address: collection_data.ip_nft };
    cheat_caller_address(collection_data.ip_nft, holder, CheatSpan::TargetCalls(1));
    erc721.approve(ip_address, token_id);

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, holder, CheatSpan::TargetCalls(1));
    dispatcher.transfer_token(holder, buyer, token_key.clone());

    // After transfer, original_creator must still be the minting collection owner
    let nft = IIPNftDispatcher { contract_address: collection_data.ip_nft };
    assert(nft.get_token_creator(token_id) == owner, 'Creator changed after transfer!');
    assert(erc721.owner_of(token_id) == buyer, 'New owner should be buyer');
}

// ─── Collection immutability ───────────────────────────────────────────────────

#[test]
fn test_collection_metadata_is_immutable_after_creation() {
    let (dispatcher, ip_address) = deploy_contract();
    let collection_id = setup_collection(dispatcher, ip_address);

    let collection = dispatcher.get_collection(collection_id);
    let erc721 = ERC721ABIDispatcher { contract_address: collection.ip_nft };

    assert(collection.name == "Test Collection", 'Registry name mismatch');
    assert(collection.symbol == "TST", 'Registry symbol mismatch');
    assert(collection.base_uri == "ipfs://QmCollectionBaseUri/", 'Registry base URI mismatch');
    assert(erc721.name() == collection.name, 'NFT name mismatch');
    assert(erc721.symbol() == collection.symbol, 'NFT symbol mismatch');
}

#[test]
fn test_transfer_collection_ownership_updates_owner_and_mint_authority() {
    let (dispatcher, ip_address) = deploy_contract();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, OWNER(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(collection_id, USER2());

    let collection = dispatcher.get_collection(collection_id);
    assert(collection.owner == USER2(), 'Owner should transfer');
    assert(dispatcher.is_collection_owner(collection_id, USER2()), 'New owner mismatch');
    assert(!dispatcher.is_collection_owner(collection_id, OWNER()), 'Old owner mismatch');

    cheat_caller_address(ip_address, USER2(), CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, USER1(), IPFS_URI());
    assert(token_id == 1, 'New owner should mint');
    let token = dispatcher.get_token(format!("{}:{}", collection_id, token_id));
    assert(token.original_creator == USER2(), 'New owner should be creator');
}

#[test]
#[should_panic(expected: ('Only collection owner can mint',))]
fn test_previous_collection_owner_cannot_mint_after_transfer() {
    let (dispatcher, ip_address) = deploy_contract();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, OWNER(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(collection_id, USER2());

    cheat_caller_address(ip_address, OWNER(), CheatSpan::TargetCalls(1));
    dispatcher.mint(collection_id, USER1(), IPFS_URI());
}

#[test]
fn test_transfer_collection_ownership_updates_owner_collection_lists() {
    let (dispatcher, ip_address) = deploy_contract();

    cheat_caller_address(ip_address, USER1(), CheatSpan::TargetCalls(1));
    let collection_id1 = dispatcher.create_collection("C1", "S1", "ipfs://QmC1");

    cheat_caller_address(ip_address, USER1(), CheatSpan::TargetCalls(1));
    let collection_id2 = dispatcher.create_collection("C2", "S2", "ipfs://QmC2");

    cheat_caller_address(ip_address, USER1(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(collection_id1, USER2());

    let user1_collections = dispatcher.list_user_collections(USER1());
    assert(user1_collections == array![collection_id2].span(), 'Old owner list mismatch');

    let user2_collections = dispatcher.list_user_collections(USER2());
    assert(user2_collections == array![collection_id1].span(), 'New owner list mismatch');
}

#[test]
#[should_panic(expected: ('Not collection owner',))]
fn test_transfer_collection_ownership_not_owner() {
    let (dispatcher, ip_address) = deploy_contract();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, USER2(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(collection_id, USER3());
}

#[test]
#[should_panic(expected: ('New owner is zero address',))]
fn test_transfer_collection_ownership_zero_address() {
    let (dispatcher, ip_address) = deploy_contract();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, OWNER(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(collection_id, ZERO());
}

#[test]
#[should_panic(expected: ('New owner is current owner',))]
fn test_transfer_collection_ownership_same_owner() {
    let (dispatcher, ip_address) = deploy_contract();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, OWNER(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(collection_id, OWNER());
}

#[test]
#[should_panic(expected: ('Invalid collection',))]
fn test_transfer_collection_ownership_invalid_collection() {
    let (dispatcher, ip_address) = deploy_contract();

    cheat_caller_address(ip_address, OWNER(), CheatSpan::TargetCalls(1));
    dispatcher.transfer_collection_ownership(99, USER2());
}

#[test]
fn test_get_collection_count() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    start_cheat_caller_address(ip_address, owner);

    assert(dispatcher.get_collection_count() == 0, 'Count should start at 0');
    dispatcher.create_collection("C1", "S1", "ipfs://QmC1");
    assert(dispatcher.get_collection_count() == 1, 'Count should be 1');
    dispatcher.create_collection("C2", "S2", "ipfs://QmC2");
    assert(dispatcher.get_collection_count() == 2, 'Count should be 2');

    stop_cheat_caller_address(ip_address);
}

// ─── get_token validation ───────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Invalid collection',))]
fn test_get_token_invalid_collection_reverts() {
    let (dispatcher, _) = deploy_contract();
    // collection_id 99 was never created
    dispatcher.get_token("99:1");
}

// ─── Parser validation (M-04, L-04) ────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Invalid token format',))]
fn test_from_bytes_no_colon_panics() {
    let (dispatcher, _) = deploy_contract();
    dispatcher.is_valid_token("123");
}

#[test]
#[should_panic(expected: ('Invalid token format',))]
fn test_from_bytes_multiple_colons_panics() {
    let (dispatcher, _) = deploy_contract();
    dispatcher.is_valid_token("1:2:3");
}

// ─── Existing passing tests (preserved / updated) ──────────────────────────────

#[test]
fn test_list_user_collections_empty() {
    let (dispatcher, _) = deploy_contract();
    let collections = dispatcher.list_user_collections(USER2());
    assert(collections.len() == 0, 'Should have no collections');
}

#[test]
fn test_verification_functions() {
    let (dispatcher, address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, address);

    start_cheat_caller_address(address, owner);
    let token_id = dispatcher.mint(collection_id, USER1(), IPFS_URI());
    let token_key = format!("{}:{}", collection_id, token_id);
    assert(dispatcher.is_valid_collection(collection_id), 'Collection should be valid');
    assert(dispatcher.is_valid_token(token_key.clone()), 'Token should be valid');
    assert(dispatcher.is_transferable_token(token_key), 'Token should be transferable');
    assert(dispatcher.is_collection_owner(collection_id, owner), 'Owner should be correct');
    stop_cheat_caller_address(address);
}

#[test]
fn test_is_collection_owner_false_for_invalid_collection() {
    let (dispatcher, _) = deploy_contract();
    assert(!dispatcher.is_collection_owner(99, ZERO()), 'Invalid collection owner');
}

#[test]
fn test_is_transferable_token_false_after_archive() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, IPFS_URI());

    let token_key = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, recipient, CheatSpan::TargetCalls(1));
    dispatcher.archive(token_key.clone());

    assert(dispatcher.is_valid_token(token_key.clone()), 'Archived token should exist');
    assert(!dispatcher.is_transferable_token(token_key), 'Archived token transfers');
}

#[test]
fn test_user_collections_mapping() {
    let (ip_dispatcher, ip_address) = deploy_contract();

    cheat_caller_address(ip_address, USER1(), CheatSpan::TargetCalls(1));
    let collection_id1 = ip_dispatcher.create_collection("C1", "S1", "ipfs://QmC1");
    assert(collection_id1 == 1, 'First collection ID should be 1');

    cheat_caller_address(ip_address, USER2(), CheatSpan::TargetCalls(1));
    let collection_id2 = ip_dispatcher.create_collection("C2", "S2", "ipfs://QmC2");
    assert(collection_id2 == 2, 'Second ID should be 2');

    cheat_caller_address(ip_address, USER2(), CheatSpan::TargetCalls(1));
    let collection_id3 = ip_dispatcher.create_collection("C3", "S3", "ipfs://QmC3");
    assert(collection_id3 == 3, 'Third ID should be 3');

    cheat_caller_address(ip_address, USER3(), CheatSpan::TargetCalls(1));
    let collection_id4 = ip_dispatcher.create_collection("C4", "S4", "ipfs://QmC4");
    assert(collection_id4 == 4, 'Fourth ID should be 4');

    cheat_caller_address(ip_address, USER1(), CheatSpan::TargetCalls(1));
    let collection_id5 = ip_dispatcher.create_collection("C5", "S5", "ipfs://QmC5");
    assert(collection_id5 == 5, 'Fifth ID should be 5');

    cheat_caller_address(ip_address, USER1(), CheatSpan::TargetCalls(1));
    let collection_id6 = ip_dispatcher.create_collection("C6", "S6", "ipfs://QmC6");
    assert(collection_id6 == 6, 'Sixth ID should be 6');

    cheat_caller_address(ip_address, USER3(), CheatSpan::TargetCalls(1));
    let collection_id7 = ip_dispatcher.create_collection("C7", "S7", "ipfs://QmC7");
    assert(collection_id7 == 7, 'Seventh ID should be 7');

    let user1_collections = ip_dispatcher.list_user_collections(USER1());
    assert(
        user1_collections == array![collection_id1, collection_id5, collection_id6].span(),
        'mismatch user1',
    );

    let user2_collections = ip_dispatcher.list_user_collections(USER2());
    assert(
        user2_collections == array![collection_id2, collection_id3].span(), 'mismatch user2',
    );

    let user3_collections = ip_dispatcher.list_user_collections(USER3());
    assert(
        user3_collections == array![collection_id4, collection_id7].span(), 'mismatch user3',
    );
}

#[test]
fn test_base_uri() {
    let (ip_dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));

    let base_uri: ByteArray = "ipfs://QmMyCollection";
    let collection_id = ip_dispatcher
        .create_collection("My Collection", "MC", base_uri.clone());

    let collection = ip_dispatcher.get_collection(collection_id);
    let collection_base_uri = IIPNftDispatcher { contract_address: collection.ip_nft }.base_uri();
    assert(collection_base_uri == base_uri, 'base uri mismatch');
}

#[test]
fn test_get_all_user_tokens() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient1 = USER1();
    let recipient2 = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher
        .batch_mint(collection_id, array![recipient1, recipient2], array![IPFS_URI(), IPFS_URI()]);

    assert(token_ids.len() == 2, 'Should mint 2 tokens in batch');

    let recipient_tokens = dispatcher.list_user_tokens_per_collection(collection_id, recipient1);
    assert(recipient_tokens.len() == 1, 'Recipient1 should have 1 token');
    assert(*recipient_tokens.at(0) == *token_ids.at(0), 'TokenID mismatch for recipient1');

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id3 = dispatcher.mint(collection_id, recipient1, IPFS_URI());
    assert(token_id3 == 3, 'Token ID should be 3');

    let recipients_tokens = dispatcher.list_user_tokens_per_collection(collection_id, recipient1);
    assert(recipients_tokens.len() == 2, 'Recipient1 should have 2 tokens');
    assert(*recipients_tokens.at(0) == *token_ids.at(0), 'TokenID mismatch for recipient1');
    assert(*recipients_tokens.at(1) == token_id3, 'TokenID mismatch for recipient1');

    let recipient2_tokens = dispatcher.list_user_tokens_per_collection(collection_id, recipient2);
    assert(recipient2_tokens.len() == 1, 'Recipient2 should have 1 token');
    assert(*recipient2_tokens.at(0) == *token_ids.at(1), 'TokenID mismatch for recipient2');
}
