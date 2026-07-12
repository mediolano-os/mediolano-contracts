use ip_ticket::IPTicketCollectionFactory::IPTicketCollectionFactory::{CollectionDeployed, Event};
use ip_ticket::interface::{
    IIPTicketCollectionDispatcher, IIPTicketCollectionDispatcherTrait,
    IIPTicketCollectionFactoryDispatcher, IIPTicketCollectionFactoryDispatcherTrait,
    IIP_TICKET_COLLECTION_FACTORY_ID,
};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc721::interface::{
    IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_caller_address, declare, spy_events,
};
use starknet::{ClassHash, ContractAddress};

fn USER1() -> ContractAddress {
    0x200.try_into().unwrap()
}
fn USER2() -> ContractAddress {
    0x300.try_into().unwrap()
}

fn COLLECTION_NAME() -> ByteArray {
    "General Admission"
}
fn COLLECTION_SYMBOL() -> ByteArray {
    "GA"
}
fn COLLECTION_NAME_2() -> ByteArray {
    "VIP Passes"
}
fn COLLECTION_SYMBOL_2() -> ByteArray {
    "VIP"
}

fn collection_class_hash() -> ClassHash {
    let declare_result = declare("IPTicketCollection").unwrap();
    *declare_result.contract_class().class_hash
}

fn deploy_factory() -> (IIPTicketCollectionFactoryDispatcher, ContractAddress) {
    let class_hash = collection_class_hash();
    let mut calldata: Array<felt252> = array![];
    class_hash.serialize(ref calldata);

    let declare_result = declare("IPTicketCollectionFactory").unwrap();
    let contract_class = declare_result.contract_class();
    let (address, _) = contract_class.deploy(@calldata).unwrap();

    (IIPTicketCollectionFactoryDispatcher { contract_address: address }, address)
}

#[test]
fn test_factory_constructor_class_hash() {
    let (factory, _) = deploy_factory();
    assert_eq!(factory.collection_class_hash(), collection_class_hash());
}

#[test]
fn test_factory_version() {
    let (factory, _) = deploy_factory();
    assert_eq!(factory.version(), "2.0.0");
}

#[test]
fn test_deploy_ticket_collection_returns_nonzero_address() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    assert!(collection_address.into() != 0_felt252, "Collection address must be non-zero");
}

#[test]
fn test_deploy_ticket_collection_caller_is_owner() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    let ownable = IOwnableDispatcher { contract_address: collection_address };
    assert_eq!(ownable.owner(), USER1());
}

#[test]
fn test_deploy_ticket_collection_stores_name_symbol() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    let metadata = IERC721MetadataDispatcher { contract_address: collection_address };
    assert_eq!(metadata.name(), COLLECTION_NAME());
    assert_eq!(metadata.symbol(), COLLECTION_SYMBOL());
}

#[test]
fn test_deploy_ticket_collection_emits_collection_deployed_event() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let mut spy = spy_events();
    let collection_address = factory
        .deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

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
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_deploy_two_ticket_collections_different_addresses() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory.deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr2 = factory.deploy_ticket_collection(COLLECTION_NAME_2(), COLLECTION_SYMBOL_2());

    assert!(addr1 != addr2, "Each deploy must produce a unique address");
}

#[test]
fn test_deploy_ticket_collection_by_different_callers() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory.deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    let addr2 = factory.deploy_ticket_collection(COLLECTION_NAME_2(), COLLECTION_SYMBOL_2());

    let ownable1 = IOwnableDispatcher { contract_address: addr1 };
    let ownable2 = IOwnableDispatcher { contract_address: addr2 };
    assert_eq!(ownable1.owner(), USER1());
    assert_eq!(ownable2.owner(), USER2());
}

#[test]
fn test_deployed_ticket_collection_owner_can_create_collection() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let collection_address = factory
        .deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    let collection = IIPTicketCollectionDispatcher { contract_address: collection_address };
    let metadata_uri: ByteArray = "ipfs://bafybeiticketcollection";

    cheat_caller_address(collection_address, USER1(), CheatSpan::TargetCalls(1));
    let collection_id = collection
        .create_ticket_collection(0, 100, 999_999_999, 0, Option::None, metadata_uri);

    assert_eq!(collection_id, 1);
    assert_eq!(collection.get_ticket_collection(collection_id).creator, USER1());
}

#[test]
#[should_panic(expected: 'Name must not be empty')]
fn test_deploy_ticket_collection_empty_name_rejected() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    factory.deploy_ticket_collection("", COLLECTION_SYMBOL());
}

#[test]
#[should_panic(expected: 'Symbol must not be empty')]
fn test_deploy_ticket_collection_empty_symbol_rejected() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    factory.deploy_ticket_collection(COLLECTION_NAME(), "");
}

#[test]
fn test_any_address_can_deploy_ticket_collection() {
    let (factory, address) = deploy_factory();

    cheat_caller_address(address, USER1(), CheatSpan::TargetCalls(1));
    let addr1 = factory.deploy_ticket_collection(COLLECTION_NAME(), COLLECTION_SYMBOL());

    cheat_caller_address(address, USER2(), CheatSpan::TargetCalls(1));
    let addr2 = factory.deploy_ticket_collection(COLLECTION_NAME_2(), COLLECTION_SYMBOL_2());

    assert!(addr1.into() != 0_felt252);
    assert!(addr2.into() != 0_felt252);
    assert!(addr1 != addr2);
}

#[test]
fn test_factory_registers_src5_discovery_id() {
    let (_, factory_address) = deploy_factory();
    let src5 = ISRC5Dispatcher { contract_address: factory_address };
    assert(src5.supports_interface(IIP_TICKET_COLLECTION_FACTORY_ID), 'factory id missing');
}
