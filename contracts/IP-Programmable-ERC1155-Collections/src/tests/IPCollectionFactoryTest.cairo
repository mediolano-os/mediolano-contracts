use ip_programmable_erc1155_collections::IPCollectionFactory::IPCollectionFactory::{
    CollectionDeployed, Event,
};
use ip_programmable_erc1155_collections::interfaces::IIPCollection::{
    IIPCollectionDispatcher, IIPCollectionDispatcherTrait,
};
use ip_programmable_erc1155_collections::interfaces::IIPCollectionFactory::{
    IIPCollectionFactoryDispatcher, IIPCollectionFactoryDispatcherTrait,
};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_caller_address, declare, spy_events,
};
use starknet::{ClassHash, ContractAddress};

// ─── Constants
// ─────────────────────────────────────────────────────────────────

fn FACTORY_OWNER() -> ContractAddress {
    0x100.try_into().unwrap()
}
fn USER1() -> ContractAddress {
    0x200.try_into().unwrap()
}
fn USER2() -> ContractAddress {
    0x300.try_into().unwrap()
}

fn COLLECTION_NAME() -> ByteArray {
    "My IP Collection"
}
fn COLLECTION_SYMBOL() -> ByteArray {
    "MIP"
}
fn COLLECTION_BASE_URI() -> ByteArray {
    "ipfs://QmCollectionMetadata/collection.json"
}
fn COLLECTION_NAME_2() -> ByteArray {
    "Second Collection"
}
fn COLLECTION_SYMBOL_2() -> ByteArray {
    "SC2"
}
fn ZERO_CLASS_HASH() -> ClassHash {
    0.try_into().unwrap()
}

// ─── Helpers
// ───────────────────────────────────────────────────────────────────

fn collection_class_hash() -> ClassHash {
    let declare_result = declare("IPCollection").unwrap();
    *declare_result.contract_class().class_hash
}

fn deploy_factory() -> (IIPCollectionFactoryDispatcher, ContractAddress) {
    let class_hash = collection_class_hash();
    deploy_factory_with_class_hash(class_hash)
}

fn deploy_factory_with_class_hash(
    class_hash: ClassHash,
) -> (IIPCollectionFactoryDispatcher, ContractAddress) {
    let mut calldata: Array<felt252> = array![];
    class_hash.serialize(ref calldata);

    let declare_result = declare("IPCollectionFactory").unwrap();
    let contract_class = declare_result.contract_class();
    let (address, _) = contract_class.deploy(@calldata).unwrap();

    let dispatcher = IIPCollectionFactoryDispatcher { contract_address: address };
    (dispatcher, address)
}

fn deploy_receiver() -> ContractAddress {
    let declare_result = declare("ERC1155Receiver").unwrap();
    let contract_class = declare_result.contract_class();
    let (address, _) = contract_class.deploy(@array![]).unwrap();
    address
}

// ─── Constructor
// ───────────────────────────────────────────────────────────────

#[test]
fn test_factory_constructor_class_hash() {
    let (factory, _) = deploy_factory();
    assert_eq!(factory.collection_class_hash(), collection_class_hash());
}

#[test]
fn test_factory_version() {
    let (factory, _) = deploy_factory();
    assert_eq!(factory.version(), "0.4.0");
}

// ─── deploy_collection
// ─────────────────────────────────────────────────────────

#[test]
fn test_deploy_collection_returns_nonzero_address() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    assert!(collection_address.into() != 0_felt252, "Collection address must be non-zero");
}

#[test]
fn test_deploy_collection_caller_is_owner() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    let ownable = IOwnableDispatcher { contract_address: collection_address };
    assert_eq!(ownable.owner(), USER1());
}

#[test]
fn test_deploy_collection_creator_is_caller() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    let collection = IIPCollectionDispatcher { contract_address: collection_address };
    assert_eq!(collection.get_collection_creator(), USER1());
}

#[test]
fn test_deploy_collection_stores_name_symbol_base_uri() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    let collection = IIPCollectionDispatcher { contract_address: collection_address };
    assert_eq!(collection.name(), COLLECTION_NAME());
    assert_eq!(collection.symbol(), COLLECTION_SYMBOL());
    assert_eq!(collection.base_uri(), COLLECTION_BASE_URI());
}

#[test]
fn test_deploy_collection_empty_base_uri_allowed() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory.deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), "");

    let collection = IIPCollectionDispatcher { contract_address: collection_address };
    assert_eq!(collection.base_uri(), "");
}

#[test]
fn test_deploy_collection_emits_collection_deployed_event() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let mut spy = spy_events();
    let collection_address = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    spy
        .assert_emitted(
            @array![
                (
                    address,
                    Event::CollectionDeployed(
                        CollectionDeployed {
                            collection_address,
                            owner: USER1(),
                            name: COLLECTION_NAME(),
                            symbol: COLLECTION_SYMBOL(),
                            base_uri: COLLECTION_BASE_URI(),
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_deploy_two_collections_different_addresses() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr2 = factory
        .deploy_collection(COLLECTION_NAME_2(), COLLECTION_SYMBOL_2(), COLLECTION_BASE_URI());

    assert!(addr1 != addr2, "Each deploy must produce a unique address");
}

#[test]
fn test_same_caller_same_name_produces_different_addresses() {
    // The nonce ensures uniqueness even when name, symbol, and caller are identical.
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr2 = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    assert!(addr1 != addr2, "Same caller + same name must still produce different addresses");
}

#[test]
fn test_deploy_collection_by_different_callers() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    let addr2 = factory
        .deploy_collection(COLLECTION_NAME_2(), COLLECTION_SYMBOL_2(), COLLECTION_BASE_URI());

    let ownable1 = IOwnableDispatcher { contract_address: addr1 };
    let ownable2 = IOwnableDispatcher { contract_address: addr2 };
    assert_eq!(ownable1.owner(), USER1());
    assert_eq!(ownable2.owner(), USER2());
}

#[test]
fn test_deployed_collection_can_mint() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    let collection = IIPCollectionDispatcher { contract_address: collection_address };
    let recipient = deploy_receiver();
    let token_uri: ByteArray = "ipfs://QmDeployedCollectionToken";

    cheat_caller_address(collection_address, USER1(), CheatSpan::TargetCalls(1));
    let token_id = collection.mint_edition(recipient, 10, token_uri);

    let erc1155 = IERC1155Dispatcher { contract_address: collection_address };
    assert_eq!(token_id, 1);
    assert_eq!(erc1155.balance_of(recipient, 1), 10);
}

// ─── Input validation
// ──────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: 'Name must not be empty')]
fn test_deploy_collection_empty_name_rejected() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    factory.deploy_collection("", COLLECTION_SYMBOL(), COLLECTION_BASE_URI());
}

#[test]
#[should_panic(expected: 'Symbol must not be empty')]
fn test_deploy_collection_empty_symbol_rejected() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    factory.deploy_collection(COLLECTION_NAME(), "", COLLECTION_BASE_URI());
}

// ─── Anyone can deploy
// ─────────────────────────────────────────────────────────

#[test]
fn test_any_address_can_deploy_collection() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory
        .deploy_collection(COLLECTION_NAME(), COLLECTION_SYMBOL(), COLLECTION_BASE_URI());

    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    let addr2 = factory
        .deploy_collection(COLLECTION_NAME_2(), COLLECTION_SYMBOL_2(), COLLECTION_BASE_URI());

    assert!(addr1.into() != 0_felt252);
    assert!(addr2.into() != 0_felt252);
    assert!(addr1 != addr2);
}
