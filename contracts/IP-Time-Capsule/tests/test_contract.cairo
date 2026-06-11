use ip_time_capsule::interfaces::{
    IIP_TIME_CAPSULE_ID, ITimeCapsuleDispatcher, ITimeCapsuleDispatcherTrait,
};
use ip_time_capsule::types::{COMMITMENT_SCHEME_POSEIDON_HASH_SALT, compute_content_commitment};
use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
};
use starknet::ContractAddress;

fn CREATOR() -> ContractAddress {
    0x123.try_into().unwrap()
}

fn OTHER() -> ContractAddress {
    0x456.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn HIDDEN_URI() -> ByteArray {
    "ipfs://bafyHiddenTimeCapsuleMetadata"
}

fn ENCRYPTED_URI() -> ByteArray {
    "ipfs://bafyEncryptedPayload"
}

fn REVEALED_URI() -> ByteArray {
    "ipfs://bafyRevealedPayload"
}

fn AR_URI() -> ByteArray {
    "ar://timeCapsulePayload"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/metadata.json"
}

fn COMMITMENT() -> felt252 {
    compute_content_commitment(CONTENT_HASH(), CONTENT_SALT())
}

fn CONTENT_HASH() -> felt252 {
    0x123456789
}

fn CONTENT_SALT() -> felt252 {
    0x987654321
}

fn MAX_LOCK() -> u64 {
    100000
}

fn IERC721_ID() -> felt252 {
    0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943
}

fn deploy_contract() -> (ITimeCapsuleDispatcher, ContractAddress) {
    let contract = declare("IPTimeCapsule").unwrap().contract_class();
    let name: ByteArray = "IP Time Capsule";
    let symbol: ByteArray = "IPTC";
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    HIDDEN_URI().serialize(ref calldata);
    MAX_LOCK().serialize(ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    (ITimeCapsuleDispatcher { contract_address: address }, address)
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

fn deploy_probing_receiver() -> ContractAddress {
    let contract = declare("ProbingReceiver").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    address
}

fn setup() -> (ITimeCapsuleDispatcher, ContractAddress, ContractAddress, ContractAddress) {
    let (capsules, address) = deploy_contract();
    let user1 = deploy_mock_account();
    let user2 = deploy_mock_account();
    (capsules, address, user1, user2)
}

fn mint_as(
    capsules: ITimeCapsuleDispatcher,
    address: ContractAddress,
    creator: ContractAddress,
    recipient: ContractAddress,
    encrypted_uri: ByteArray,
    content_commitment: felt252,
    reveal_at: u64,
) -> u256 {
    cheat_caller_address(address, creator, CheatSpan::TargetCalls(1));
    capsules.mint_capsule(recipient, encrypted_uri, content_commitment, reveal_at)
}

fn reveal_as(
    capsules: ITimeCapsuleDispatcher,
    address: ContractAddress,
    revealer: ContractAddress,
    token_id: u256,
    revealed_uri: ByteArray,
    content_hash: felt252,
    content_salt: felt252,
    now: u64,
) {
    cheat_block_timestamp(address, now, CheatSpan::TargetCalls(1));
    cheat_caller_address(address, revealer, CheatSpan::TargetCalls(1));
    capsules.reveal_capsule(token_id, revealed_uri, content_hash, content_salt);
}

#[test]
fn test_deploy_succeeds() {
    let (capsules, address) = deploy_contract();
    let meta = IERC721MetadataDispatcher { contract_address: address };

    assert(meta.name() == "IP Time Capsule", 'name mismatch');
    assert(meta.symbol() == "IPTC", 'symbol mismatch');
    assert(capsules.get_hidden_uri() == HIDDEN_URI(), 'hidden uri mismatch');
    assert(capsules.get_max_lock_duration() == MAX_LOCK(), 'max lock mismatch');
}

#[test]
fn test_mint_capsule_records_commitment_and_hidden_token_uri() {
    let (capsules, address, user1, _) = setup();
    let reveal_at: u64 = 1000;
    let token_id = mint_as(
        capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), reveal_at,
    );

    let erc721 = IERC721Dispatcher { contract_address: address };
    let meta = IERC721MetadataDispatcher { contract_address: address };
    let data = capsules.get_capsule_data(token_id);

    assert(token_id == 1, 'token id mismatch');
    assert(erc721.owner_of(token_id) == user1, 'owner mismatch');
    assert(meta.token_uri(token_id) == HIDDEN_URI(), 'token uri should hide');
    assert(capsules.get_encrypted_uri(token_id) == ENCRYPTED_URI(), 'encrypted uri mismatch');
    assert(capsules.get_token_creator(token_id) == user1, 'creator mismatch');
    assert(capsules.get_token_reveal_at(token_id) == reveal_at, 'reveal_at mismatch');
    assert(data.content_commitment == COMMITMENT(), 'commitment mismatch');
    assert(!data.revealed, 'should be sealed');
}

#[test]
fn test_mint_accepts_ar_encrypted_uri() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, AR_URI(), COMMITMENT(), 1000);

    assert(capsules.get_encrypted_uri(token_id) == AR_URI(), 'ar uri mismatch');
}

#[test]
fn test_mint_emits_time_capsule_event() {
    let (capsules, address, user1, _) = setup();
    let mut spy = spy_events();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    let expected = ip_time_capsule::time_capsule::IPTimeCapsule::Event::TimeCapsuleMinted(
        ip_time_capsule::time_capsule::IPTimeCapsule::TimeCapsuleMinted {
            token_id,
            recipient: user1,
            creator: user1,
            encrypted_uri: ENCRYPTED_URI(),
            content_commitment: COMMITMENT(),
            reveal_at: 1000,
            minted_at: 0,
        },
    );
    spy.assert_emitted(@array![(address, expected)]);
}

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_mint_rejects_zero_recipient() {
    let (capsules, address, user1, _) = setup();
    mint_as(capsules, address, user1, ZERO(), ENCRYPTED_URI(), COMMITMENT(), 1000);
}

#[test]
#[should_panic(expected: ('Invalid encrypted URI',))]
fn test_mint_rejects_http_uri() {
    let (capsules, address, user1, _) = setup();
    mint_as(capsules, address, user1, user1, HTTP_URI(), COMMITMENT(), 1000);
}

#[test]
#[should_panic(expected: ('Empty commitment',))]
fn test_mint_rejects_empty_commitment() {
    let (capsules, address, user1, _) = setup();
    mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), 0, 1000);
}

#[test]
#[should_panic(expected: ('Reveal must be future',))]
fn test_mint_rejects_past_reveal() {
    let (capsules, address, user1, _) = setup();
    cheat_block_timestamp(address, 1000, CheatSpan::TargetCalls(1));
    mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);
}

#[test]
#[should_panic(expected: ('Reveal exceeds max lock',))]
fn test_mint_rejects_reveal_after_max_lock() {
    let (capsules, address, user1, _) = setup();
    mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), MAX_LOCK() + 1);
}

#[test]
fn test_is_unlocked_false_then_true() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    cheat_block_timestamp(address, 999, CheatSpan::TargetCalls(1));
    assert(!capsules.is_unlocked(token_id), 'should be locked');

    cheat_block_timestamp(address, 1000, CheatSpan::TargetCalls(1));
    assert(capsules.is_unlocked(token_id), 'should be unlocked');
}

#[test]
#[should_panic(expected: ('Not unlocked',))]
fn test_reveal_before_unlock_rejected() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    reveal_as(
        capsules, address, user1, token_id, REVEALED_URI(), CONTENT_HASH(), CONTENT_SALT(), 999,
    );
}

#[test]
#[should_panic(expected: ('Not authorized',))]
fn test_reveal_by_non_creator_non_owner_rejected() {
    let (capsules, address, user1, user2) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    reveal_as(
        capsules, address, user2, token_id, REVEALED_URI(), CONTENT_HASH(), CONTENT_SALT(), 1000,
    );
}

#[test]
#[should_panic(expected: ('Commitment mismatch',))]
fn test_reveal_wrong_commitment_rejected() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    reveal_as(capsules, address, user1, token_id, REVEALED_URI(), 0x999, CONTENT_SALT(), 1000);
}

#[test]
#[should_panic(expected: ('Empty content salt',))]
fn test_reveal_empty_salt_rejected() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    reveal_as(capsules, address, user1, token_id, REVEALED_URI(), CONTENT_HASH(), 0, 1000);
}

#[test]
fn test_reveal_after_unlock_updates_token_uri() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);
    let meta = IERC721MetadataDispatcher { contract_address: address };

    reveal_as(
        capsules, address, user1, token_id, REVEALED_URI(), CONTENT_HASH(), CONTENT_SALT(), 1000,
    );

    let data = capsules.get_capsule_data(token_id);
    assert(capsules.is_revealed(token_id), 'should be revealed');
    assert(capsules.get_revealed_uri(token_id) == REVEALED_URI(), 'revealed uri mismatch');
    assert(meta.token_uri(token_id) == REVEALED_URI(), 'token uri should reveal');
    assert(data.revealed, 'should be revealed');
    assert(data.revealed_at == 1000, 'revealed_at mismatch');
    assert(data.content_hash == CONTENT_HASH(), 'hash mismatch');
}

#[test]
fn test_reveal_emits_time_capsule_event() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);
    let mut spy = spy_events();

    reveal_as(
        capsules, address, user1, token_id, REVEALED_URI(), CONTENT_HASH(), CONTENT_SALT(), 1000,
    );

    let expected = ip_time_capsule::time_capsule::IPTimeCapsule::Event::TimeCapsuleRevealed(
        ip_time_capsule::time_capsule::IPTimeCapsule::TimeCapsuleRevealed {
            token_id,
            revealer: user1,
            revealed_uri: REVEALED_URI(),
            content_hash: CONTENT_HASH(),
            content_salt: CONTENT_SALT(),
            revealed_at: 1000,
        },
    );
    spy.assert_emitted(@array![(address, expected)]);
}

#[test]
fn test_current_owner_can_reveal_after_transfer() {
    let (capsules, address, user1, user2) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);
    let erc721 = IERC721Dispatcher { contract_address: address };

    cheat_caller_address(address, user1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(user1, user2, token_id);

    reveal_as(
        capsules, address, user2, token_id, REVEALED_URI(), CONTENT_HASH(), CONTENT_SALT(), 1000,
    );

    let data = capsules.get_capsule_data(token_id);
    assert(data.owner == user2, 'owner should update');
    assert(data.creator == user1, 'creator preserved');
    assert(data.revealed, 'should be revealed');
}

#[test]
#[should_panic(expected: ('Already revealed',))]
fn test_reveal_twice_rejected() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    reveal_as(
        capsules, address, user1, token_id, REVEALED_URI(), CONTENT_HASH(), CONTENT_SALT(), 1000,
    );
    reveal_as(capsules, address, user1, token_id, AR_URI(), CONTENT_HASH(), CONTENT_SALT(), 1001);
}

#[test]
fn test_safe_mint_to_receiver_contract_succeeds() {
    let (capsules, address, user1, _) = setup();
    let receiver = deploy_receiver();
    let token_id = mint_as(capsules, address, user1, receiver, ENCRYPTED_URI(), COMMITMENT(), 1000);
    let erc721 = IERC721Dispatcher { contract_address: address };

    assert(erc721.owner_of(token_id) == receiver, 'receiver should own token');
}

#[test]
#[should_panic]
fn test_safe_mint_to_non_receiver_contract_rejected() {
    let (capsules, address, user1, _) = setup();
    let (_, non_receiver) = deploy_contract();

    mint_as(capsules, address, user1, non_receiver, ENCRYPTED_URI(), COMMITMENT(), 1000);
}

#[test]
fn test_supports_interfaces() {
    let (_, address) = deploy_contract();
    let src5 = ISRC5Dispatcher { contract_address: address };

    assert(src5.supports_interface(IERC721_ID()), 'missing erc721');
    assert(src5.supports_interface(IIP_TIME_CAPSULE_ID), 'missing time capsule');
}

#[test]
fn test_commitment_scheme_helpers() {
    let (capsules, _) = deploy_contract();

    assert(capsules.get_commitment_scheme() == COMMITMENT_SCHEME_POSEIDON_HASH_SALT, 'scheme');
    assert(
        capsules.compute_content_commitment(CONTENT_HASH(), CONTENT_SALT()) == COMMITMENT(),
        'commitment helper mismatch',
    );
}

#[test]
#[should_panic]
fn test_get_capsule_data_nonexistent_rejected() {
    let (capsules, _) = deploy_contract();
    capsules.get_capsule_data(1);
}

#[test]
#[should_panic(expected: ('Not revealed',))]
fn test_get_revealed_uri_before_reveal_rejected() {
    let (capsules, address, user1, _) = setup();
    let token_id = mint_as(capsules, address, user1, user1, ENCRYPTED_URI(), COMMITMENT(), 1000);

    capsules.get_revealed_uri(token_id);
}

// The probing receiver reads the capsule from inside the safe_mint callback
// and reverts if the commitment is empty — proving capsule state is written
// before the external receiver call (CEI ordering in mint_capsule).
#[test]
fn test_capsule_state_written_before_receiver_callback() {
    let (capsules, address, user1, _) = setup();
    let probe = deploy_probing_receiver();

    let token_id = mint_as(capsules, address, user1, probe, ENCRYPTED_URI(), COMMITMENT(), 1000);

    let erc721 = IERC721Dispatcher { contract_address: address };
    assert(erc721.owner_of(token_id) == probe, 'probe should own token');
    let data = capsules.get_capsule_data(token_id);
    assert(data.content_commitment == COMMITMENT(), 'commitment mismatch');
}
