use core::num::traits::Zero;
use ip_ticket::interface::{
    IIPTicketCollectionDispatcher, IIPTicketCollectionDispatcherTrait,
    IIPTicketCollectionFactoryDispatcher, IIPTicketCollectionFactoryDispatcherTrait,
    IIP_TICKET_COLLECTION_FACTORY_ID,
};
use openzeppelin_utils::serde::SerializedAppend;
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn deploy_mock_account() -> ContractAddress {
    let class = declare("MockAccount").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

fn deploy_factory() -> ContractAddress {
    let collection_class = declare("IPTicketCollection").unwrap().contract_class();
    let factory_class = declare("IPTicketCollectionFactory").unwrap().contract_class();
    let mut cd: Array<felt252> = array![];
    cd.append_serde(*collection_class.class_hash);
    let (addr, _) = factory_class.deploy(@cd).unwrap();
    addr
}

// ──────────────── deploy_collection ───────────────────────────────────────

#[test]
fn test_deploy_collection_returns_address() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    let caller = deploy_mock_account();
    start_cheat_caller_address(factory_addr, caller);
    let col = factory.deploy_collection("Fest Tickets", "FEST");
    stop_cheat_caller_address(factory_addr);
    assert(!col.is_zero(), 'collection address is zero');
}

#[test]
fn test_deployed_collection_owner_is_caller() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    let caller = deploy_mock_account();
    start_cheat_caller_address(factory_addr, caller);
    let col_addr = factory.deploy_collection("My Tickets", "TICK");
    stop_cheat_caller_address(factory_addr);
    // Caller should be able to create an event without panic
    let ticket = IIPTicketCollectionDispatcher { contract_address: col_addr };
    start_cheat_caller_address(col_addr, caller);
    let id = ticket.create_event(10_u256, Option::None, Option::None, 0_u16, "ipfs://QmTest");
    stop_cheat_caller_address(col_addr);
    assert(id == 1_u256, 'first event id = 1');
}

#[test]
fn test_two_deployments_have_different_addresses() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    let caller = deploy_mock_account();
    start_cheat_caller_address(factory_addr, caller);
    let col1 = factory.deploy_collection("Event A", "EVA");
    let col2 = factory.deploy_collection("Event B", "EVB");
    stop_cheat_caller_address(factory_addr);
    assert(col1 != col2, 'addresses must differ');
}

#[test]
fn test_different_callers_get_different_addresses() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    let caller1 = deploy_mock_account();
    let caller2 = deploy_mock_account();
    start_cheat_caller_address(factory_addr, caller1);
    let col1 = factory.deploy_collection("Tickets", "TIX");
    stop_cheat_caller_address(factory_addr);
    start_cheat_caller_address(factory_addr, caller2);
    let col2 = factory.deploy_collection("Tickets", "TIX");
    stop_cheat_caller_address(factory_addr);
    assert(col1 != col2, 'different callers differ');
}

#[test]
fn test_factory_version() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    assert(factory.version() == "3.0.0", 'factory version 3.0.0');
}

#[test]
fn test_factory_src5_registered() {
    let factory_addr = deploy_factory();
    let src5 = ISRC5Dispatcher { contract_address: factory_addr };
    assert(src5.supports_interface(IIP_TICKET_COLLECTION_FACTORY_ID), 'factory SRC5 registered');
}

#[test]
#[should_panic(expected: 'Name must not be empty')]
fn test_deploy_empty_name_panics() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    let caller = deploy_mock_account();
    start_cheat_caller_address(factory_addr, caller);
    factory.deploy_collection("", "TIX");
}

#[test]
#[should_panic(expected: 'Symbol must not be empty')]
fn test_deploy_empty_symbol_panics() {
    let factory_addr = deploy_factory();
    let factory = IIPTicketCollectionFactoryDispatcher { contract_address: factory_addr };
    let caller = deploy_mock_account();
    start_cheat_caller_address(factory_addr, caller);
    factory.deploy_collection("My Tickets", "");
}
