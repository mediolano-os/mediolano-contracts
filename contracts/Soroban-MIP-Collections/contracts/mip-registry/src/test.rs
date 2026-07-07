#![cfg(test)]

use mip_collection::MipCollectionClient;
use soroban_sdk::{testutils::Address as _, Address, Bytes, BytesN, Env, String};

use crate::{MipRegistry, MipRegistryClient};

const COLLECTION_WASM: &[u8] =
    include_bytes!("../../../target/wasm32v1-none/release/mip_collection.wasm");

fn setup() -> (Env, MipRegistryClient<'static>) {
    let env = Env::default();
    env.mock_all_auths();
    let wasm_bytes = Bytes::from_slice(&env, COLLECTION_WASM);
    let wasm_hash: BytesN<32> = env.deployer().upload_contract_wasm(wasm_bytes);
    let contract_id = env.register(MipRegistry, ());
    let client = MipRegistryClient::new(&env, &contract_id);
    client.init(&wasm_hash);
    (env, client)
}

fn create(
    env: &Env,
    client: &MipRegistryClient<'static>,
    creator: &Address,
    royalty_bps: u32,
) -> (u64, Address) {
    client.create_collection(
        creator,
        &String::from_str(env, "My IP"),
        &String::from_str(env, "MIP"),
        &String::from_str(env, "ipfs://base/"),
        &royalty_bps,
    )
}

#[test]
fn create_collection_is_permissionless_and_sequential() {
    let (env, client) = setup();
    let first = Address::generate(&env);
    let second = Address::generate(&env);
    let (id_a, addr_a) = create(&env, &client, &first, 250);
    let (id_b, addr_b) = create(&env, &client, &second, 0);
    assert_eq!(id_a, 1);
    assert_eq!(id_b, 2);
    assert!(addr_a != addr_b);
    assert_eq!(client.collection_count(), 2);
    let (stored_addr, stored_creator) = client.get_collection(&1);
    assert_eq!(stored_addr, addr_a);
    assert_eq!(stored_creator, first);
    assert!(client.is_valid_collection(&2));
    assert!(!client.is_valid_collection(&99));
}

#[test]
fn created_collection_is_initialized_for_creator() {
    let (env, client) = setup();
    let creator = Address::generate(&env);
    let (id, addr) = create(&env, &client, &creator, 250);
    let c = MipCollectionClient::new(&env, &addr);
    assert_eq!(c.owner(), creator);
    assert_eq!(c.collection_id(), id);
    assert_eq!(c.registry(), client.address);
    assert_eq!(c.name(), String::from_str(&env, "My IP"));
    let token_id = c.mint(&creator, &String::from_str(&env, "ipfs://a/1"));
    assert_eq!(token_id, 1);
    let (receiver, amount) = c.royalty_info(&token_id, &10_000i128);
    assert_eq!(receiver, creator);
    assert_eq!(amount, 250);
}

#[test]
#[should_panic]
fn init_cannot_run_twice() {
    let (env, client) = setup();
    let wasm_bytes = Bytes::from_slice(&env, COLLECTION_WASM);
    let wasm_hash: BytesN<32> = env.deployer().upload_contract_wasm(wasm_bytes);
    client.init(&wasm_hash);
}

#[test]
fn registry_has_no_authority_over_collections() {
    let (env, client) = setup();
    let creator = Address::generate(&env);
    let (_, addr) = create(&env, &client, &creator, 0);
    let c = MipCollectionClient::new(&env, &addr);
    assert_eq!(c.owner(), creator);
    assert_eq!(client.version(), String::from_str(&env, "1.0.0"));
}
