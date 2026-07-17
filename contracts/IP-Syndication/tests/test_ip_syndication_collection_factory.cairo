use ip_syndication::interface::{
    IIPSyndicationCollectionDispatcher, IIPSyndicationCollectionDispatcherTrait,
    IIPSyndicationCollectionFactoryDispatcher, IIPSyndicationCollectionFactoryDispatcherTrait,
    IIP_SYNDICATION_COLLECTION_FACTORY_ID,
};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress};

fn deploy_mock_account() -> ContractAddress {
    let class = declare("MockAccount").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

fn collection_class_hash() -> ClassHash {
    *declare("IPSyndicationCollection").unwrap().contract_class().class_hash
}

fn deploy_factory() -> ContractAddress {
    let class = declare("IPSyndicationCollectionFactory").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![collection_class_hash().into()]).unwrap();
    addr
}

fn deploy_via_factory(factory: ContractAddress, caller: ContractAddress) -> ContractAddress {
    let dispatcher = IIPSyndicationCollectionFactoryDispatcher { contract_address: factory };
    start_cheat_caller_address(factory, caller);
    let collection = dispatcher.deploy_collection("My Syndications", "SYND", "ipfs://QmMeta/");
    stop_cheat_caller_address(factory);
    collection
}

#[test]
fn test_deploy_collection_sets_owner_and_identity() {
    let factory = deploy_factory();
    let creator = deploy_mock_account();
    let collection = deploy_via_factory(factory, creator);

    let owner = IOwnableDispatcher { contract_address: collection }.owner();
    assert(owner == creator, 'caller should be owner');

    let dispatcher = IIPSyndicationCollectionDispatcher { contract_address: collection };
    assert(dispatcher.name() == "My Syndications", 'wrong name');
    assert(dispatcher.symbol() == "SYND", 'wrong symbol');
    assert(dispatcher.base_uri() == "ipfs://QmMeta/", 'wrong base uri');
    assert(dispatcher.syndication_count() == 0_u256, 'count should be 0');
}

#[test]
fn test_two_deploys_get_distinct_addresses() {
    let factory = deploy_factory();
    let creator = deploy_mock_account();
    let first = deploy_via_factory(factory, creator);
    let second = deploy_via_factory(factory, creator);
    assert(first != second, 'addresses should differ');
}

#[test]
fn test_factory_views() {
    let factory = deploy_factory();
    let dispatcher = IIPSyndicationCollectionFactoryDispatcher { contract_address: factory };
    assert(dispatcher.collection_class_hash() == collection_class_hash(), 'wrong class hash');
    assert(dispatcher.version() == "1.0.0", 'wrong version');
}

#[test]
fn test_factory_src5_registered() {
    let factory = deploy_factory();
    let src5 = ISRC5Dispatcher { contract_address: factory };
    assert(src5.supports_interface(IIP_SYNDICATION_COLLECTION_FACTORY_ID), 'factory id missing');
}

#[test]
#[should_panic(expected: 'Name must not be empty')]
fn test_deploy_empty_name_panics() {
    let factory = deploy_factory();
    let dispatcher = IIPSyndicationCollectionFactoryDispatcher { contract_address: factory };
    dispatcher.deploy_collection("", "SYND", "ipfs://QmMeta/");
}

#[test]
#[should_panic(expected: 'Symbol must not be empty')]
fn test_deploy_empty_symbol_panics() {
    let factory = deploy_factory();
    let dispatcher = IIPSyndicationCollectionFactoryDispatcher { contract_address: factory };
    dispatcher.deploy_collection("My Syndications", "", "ipfs://QmMeta/");
}

#[test]
fn test_factory_zero_class_hash_rejected() {
    let class = declare("IPSyndicationCollectionFactory").unwrap().contract_class();
    let result = class.deploy(@array![0]);
    assert(result.is_err(), 'deploy should fail');
}
