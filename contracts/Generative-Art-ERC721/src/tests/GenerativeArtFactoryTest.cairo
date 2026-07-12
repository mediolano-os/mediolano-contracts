use generative_art::interfaces::IGenerativeArt::{
    IGenerativeArtDispatcher, IGenerativeArtDispatcherTrait,
};
use generative_art::interfaces::IGenerativeArtFactory::{
    IGenerativeArtFactoryDispatcher, IGenerativeArtFactoryDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
};
use starknet::{ClassHash, ContractAddress};

fn CREATOR() -> ContractAddress {
    0xCEED.try_into().unwrap()
}
fn ROYALTY() -> ContractAddress {
    0x999.try_into().unwrap()
}

fn gen_class_hash() -> ClassHash {
    *declare("GenerativeArt").unwrap().contract_class().class_hash
}

fn deploy_factory() -> ContractAddress {
    let factory = declare("GenerativeArtFactory").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    gen_class_hash().serialize(ref calldata);
    let (addr, _) = factory.deploy(@calldata).unwrap();
    addr
}

#[test]
fn test_factory_deploys_working_collection() {
    let factory_addr = deploy_factory();
    let factory = IGenerativeArtFactoryDispatcher { contract_address: factory_addr };

    cheat_caller_address(factory_addr, CREATOR(), CheatSpan::TargetCalls(1));
    let coll = factory
        .deploy_collection("Gen", "G", "https://r/", 0xABC, "ar://s", 50, ROYALTY(), 250);

    let disp = IGenerativeArtDispatcher { contract_address: coll };
    assert(disp.script_hash() == 0xABC, 'wrong script_hash');
    assert(disp.max_supply() == 50, 'wrong max_supply');
    assert(disp.total_minted() == 0, 'should start empty');

    // The deployed collection mints normally (factory holds no control over it).
    cheat_caller_address(coll, CREATOR(), CheatSpan::TargetCalls(1));
    let id = disp.mint();
    assert(id == 1, 'mint should work');
}

#[test]
fn test_factory_reports_class_hash() {
    let factory_addr = deploy_factory();
    let factory = IGenerativeArtFactoryDispatcher { contract_address: factory_addr };
    assert(factory.collection_class_hash() == gen_class_hash(), 'wrong class hash');
}
