use ip_club::interface::{
    IIPClubCollectionDispatcher, IIPClubFactoryDispatcher, IIPClubFactoryDispatcherTrait,
};
use ip_club::mocks::MockERC20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use openzeppelin_token::erc20::interface::IERC20Dispatcher;
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::{ClassHash, ContractAddress};

pub fn CREATOR() -> ContractAddress {
    0x101.try_into().unwrap()
}

pub fn USER1() -> ContractAddress {
    0x102.try_into().unwrap()
}

pub fn ZERO_ADDRESS() -> ContractAddress {
    0.try_into().unwrap()
}

pub fn IPFS_URI() -> ByteArray {
    "ipfs://bafybeiclubmetadata/"
}

pub fn AR_URI() -> ByteArray {
    "ar://club-metadata/"
}

pub fn declare_and_deploy(contract_name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

pub fn deploy_erc20() -> IERC20Dispatcher {
    let mut calldata = array![];
    let name: ByteArray = "DummyERC20";
    let symbol: ByteArray = "DUMMY";
    let initial_supply: u256 = 0;
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(initial_supply);
    IERC20Dispatcher { contract_address: declare_and_deploy("MockERC20", calldata) }
}

pub fn mint_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) {
    IERC20MintDispatcher { contract_address: token }.mint(recipient, amount)
}

pub fn deploy_receiver() -> ContractAddress {
    declare_and_deploy("Receiver", array![])
}

pub fn deploy_factory() -> (IIPClubFactoryDispatcher, ClassHash) {
    let collection_class = declare("IPClubCollection").unwrap().contract_class();
    let collection_class_hash = *collection_class.class_hash;
    let mut calldata = array![];
    calldata.append_serde(collection_class_hash);
    let factory_address = declare_and_deploy("IPClubFactory", calldata);
    (IIPClubFactoryDispatcher { contract_address: factory_address }, collection_class_hash)
}

pub fn deploy_reentrant_payment_token(
    club_collection: ContractAddress, reentry_target: ContractAddress,
) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(club_collection);
    calldata.append_serde(reentry_target);
    declare_and_deploy("ReentrantPaymentToken", calldata)
}

#[derive(Drop, Clone)]
pub struct TestContracts {
    pub factory: IIPClubFactoryDispatcher,
    pub erc20: IERC20Dispatcher,
}

pub fn setup() -> TestContracts {
    let (factory, _) = deploy_factory();
    let erc20 = deploy_erc20();
    TestContracts { factory, erc20 }
}

pub fn deploy_free_club(
    factory: IIPClubFactoryDispatcher, caller: ContractAddress,
) -> IIPClubCollectionDispatcher {
    snforge_std::cheat_caller_address(
        factory.contract_address, caller, snforge_std::CheatSpan::TargetCalls(1),
    );
    let addr = factory
        .deploy_club("Vipers", "VPS", IPFS_URI(), 100_u256, 0_u256, Option::None, 0_u256);
    IIPClubCollectionDispatcher { contract_address: addr }
}
