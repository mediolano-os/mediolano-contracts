use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use generative_art::GenerativeArt::GenerativeArt;
use generative_art::interfaces::IGenerativeArt::{
    IGenerativeArtDispatcher, IGenerativeArtDispatcherTrait,
};
use openzeppelin::token::common::erc2981::interface::{IERC2981Dispatcher, IERC2981DispatcherTrait};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
};
use starknet::ContractAddress;

fn COLLECTOR() -> ContractAddress {
    0xBEEF.try_into().unwrap()
}
fn ROYALTY() -> ContractAddress {
    0x999.try_into().unwrap()
}
fn NAME() -> ByteArray {
    "Generative One"
}
fn SYMBOL() -> ByteArray {
    "GEN1"
}
fn BASE_URI() -> ByteArray {
    "https://render.medialane.io/gen1/"
}
fn SCRIPT_URI() -> ByteArray {
    "ar://scriptTxId123"
}
fn SCRIPT_HASH() -> felt252 {
    0xABCDEF
}
const MAX_SUPPLY: u256 = 100;
const ROYALTY_BPS: u16 = 500; // 5%

fn deploy_with_supply(max_supply: u256) -> ContractAddress {
    let contract = declare("GenerativeArt").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    NAME().serialize(ref calldata);
    SYMBOL().serialize(ref calldata);
    BASE_URI().serialize(ref calldata);
    SCRIPT_HASH().serialize(ref calldata);
    SCRIPT_URI().serialize(ref calldata);
    max_supply.serialize(ref calldata);
    ROYALTY().serialize(ref calldata);
    ROYALTY_BPS.serialize(ref calldata);
    let (addr, _) = contract.deploy(@calldata).unwrap();
    addr
}

fn deploy() -> ContractAddress {
    deploy_with_supply(MAX_SUPPLY)
}

fn expected_seed(token_id: u256, minter: ContractAddress, ts: u64) -> felt252 {
    PoseidonTrait::new().update_with(token_id).update_with(minter).update_with(ts).finalize()
}

// ----------------------------- config -----------------------------

#[test]
fn test_deploy_stores_immutable_config() {
    let addr = deploy();
    let disp = IGenerativeArtDispatcher { contract_address: addr };
    assert(disp.script_hash() == SCRIPT_HASH(), 'wrong script_hash');
    assert(disp.script_uri() == SCRIPT_URI(), 'wrong script_uri');
    assert(disp.max_supply() == MAX_SUPPLY, 'wrong max_supply');
    assert(disp.total_minted() == 0, 'should start at 0');
}

#[test]
fn test_royalty_info_is_frozen_config() {
    let addr = deploy();
    let disp = IERC2981Dispatcher { contract_address: addr };
    // 5% of 10_000 sale price = 500.
    let (receiver, amount) = disp.royalty_info(1, 10_000);
    assert(receiver == ROYALTY(), 'wrong royalty receiver');
    assert(amount == 500, 'wrong royalty amount');
}

// ------------------------------ mint ------------------------------

#[test]
fn test_mint_assigns_sequential_ids_to_caller() {
    let addr = deploy();
    let disp = IGenerativeArtDispatcher { contract_address: addr };
    let erc721 = IERC721Dispatcher { contract_address: addr };

    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id1 = disp.mint();
    assert(id1 == 1, 'first id should be 1');
    assert(erc721.owner_of(1) == COLLECTOR(), 'collector should own 1');
    assert(disp.total_minted() == 1, 'minted should be 1');

    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id2 = disp.mint();
    assert(id2 == 2, 'second id should be 2');
    assert(disp.total_minted() == 2, 'minted should be 2');
}

#[test]
fn test_seed_is_deterministic_and_canonical() {
    let addr = deploy();
    let disp = IGenerativeArtDispatcher { contract_address: addr };

    cheat_block_timestamp(addr, 777, CheatSpan::TargetCalls(1));
    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id = disp.mint();

    let want = expected_seed(id, COLLECTOR(), 777);
    assert(disp.token_seed(id) == want, 'seed mismatch');
}

#[test]
fn test_distinct_tokens_have_distinct_seeds() {
    let addr = deploy();
    let disp = IGenerativeArtDispatcher { contract_address: addr };

    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id1 = disp.mint();
    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id2 = disp.mint();
    assert(disp.token_seed(id1) != disp.token_seed(id2), 'seeds should differ');
}

#[test]
fn test_mint_emits_event() {
    let addr = deploy();
    let disp = IGenerativeArtDispatcher { contract_address: addr };
    let mut spy = spy_events();

    cheat_block_timestamp(addr, 42, CheatSpan::TargetCalls(1));
    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id = disp.mint();

    let seed = expected_seed(id, COLLECTOR(), 42);
    spy
        .assert_emitted(
            @array![
                (
                    addr,
                    GenerativeArt::Event::Minted(
                        GenerativeArt::Minted { token_id: id, minter: COLLECTOR(), seed },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'max supply reached')]
fn test_mint_reverts_past_max_supply() {
    let addr = deploy_with_supply(1);
    let disp = IGenerativeArtDispatcher { contract_address: addr };
    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    disp.mint(); // ok, id 1
    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    disp.mint(); // should panic
}

// ---------------------------- token_uri ---------------------------

#[test]
fn test_token_uri_is_base_plus_id() {
    let addr = deploy();
    let disp = IGenerativeArtDispatcher { contract_address: addr };
    let meta = IERC721MetadataDispatcher { contract_address: addr };

    cheat_caller_address(addr, COLLECTOR(), CheatSpan::TargetCalls(1));
    let id = disp.mint();
    assert(meta.token_uri(id) == "https://render.medialane.io/gen1/1", 'wrong token_uri');
}
