#![cfg(test)]

use soroban_sdk::{testutils::Address as _, Address, Env, String, Vec};

use crate::{MipCollection, MipCollectionClient};

fn setup(royalty_bps: u32) -> (Env, MipCollectionClient<'static>, Address, Address) {
    let env = Env::default();
    env.mock_all_auths();
    let registry = Address::generate(&env);
    let creator = Address::generate(&env);
    let contract_id = env.register(MipCollection, ());
    let client = MipCollectionClient::new(&env, &contract_id);
    client.initialize(
        &registry,
        &1u64,
        &creator,
        &String::from_str(&env, "My IP"),
        &String::from_str(&env, "MIP"),
        &String::from_str(&env, "ipfs://base/"),
        &royalty_bps,
    );
    (env, client, registry, creator)
}

#[test]
fn initialize_sets_state() {
    let (env, client, registry, creator) = setup(500);
    assert_eq!(client.registry(), registry);
    assert_eq!(client.collection_id(), 1);
    assert_eq!(client.owner(), creator);
    assert_eq!(client.name(), String::from_str(&env, "My IP"));
    assert_eq!(client.symbol(), String::from_str(&env, "MIP"));
    assert_eq!(client.collection_base_uri(), String::from_str(&env, "ipfs://base/"));
    assert_eq!(client.version(), String::from_str(&env, "1.0.0"));
}

#[test]
#[should_panic]
fn initialize_cannot_run_twice() {
    let (env, client, registry, creator) = setup(0);
    client.initialize(
        &registry,
        &2u64,
        &creator,
        &String::from_str(&env, "X"),
        &String::from_str(&env, "X"),
        &String::from_str(&env, ""),
        &0u32,
    );
}

#[test]
#[should_panic]
fn initialize_rejects_high_bps() {
    setup(10_001);
}

#[test]
fn mint_sequential_from_one_with_complete_uri() {
    let (env, client, _, creator) = setup(500);
    let alice = Address::generate(&env);
    let first = client.mint(&alice, &String::from_str(&env, "ipfs://token/1"));
    let second = client.mint(&alice, &String::from_str(&env, "ipfs://token/2"));
    assert_eq!(first, 1);
    assert_eq!(second, 2);
    assert_eq!(client.owner_of(&1), alice);
    // Complete URI, never prefixed with the base URI.
    assert_eq!(client.token_uri(&2), String::from_str(&env, "ipfs://token/2"));
    assert!(client.token_exists(&1));
    assert!(!client.token_exists(&3));
    assert_eq!(client.get_token_creator(&1), creator);
}

#[test]
fn batch_mint() {
    let (env, client, _, _) = setup(0);
    let alice = Address::generate(&env);
    let bob = Address::generate(&env);
    let mut to = Vec::new(&env);
    to.push_back(alice.clone());
    to.push_back(bob.clone());
    let mut uris = Vec::new(&env);
    uris.push_back(String::from_str(&env, "ipfs://1"));
    uris.push_back(String::from_str(&env, "ipfs://2"));
    let ids = client.batch_mint(&to, &uris);
    assert_eq!(ids.len(), 2);
    assert_eq!(client.owner_of(&ids.get(1).unwrap()), bob);
    assert_eq!(client.token_uri(&ids.get(0).unwrap()), String::from_str(&env, "ipfs://1"));
}

#[test]
#[should_panic]
fn batch_mint_length_mismatch() {
    let (env, client, _, _) = setup(0);
    let alice = Address::generate(&env);
    let mut to = Vec::new(&env);
    to.push_back(alice);
    let uris: Vec<String> = Vec::new(&env);
    client.batch_mint(&to, &uris);
}

#[test]
fn transfer_and_approvals() {
    let (env, client, _, _) = setup(0);
    let alice = Address::generate(&env);
    let bob = Address::generate(&env);
    let operator = Address::generate(&env);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://1"));
    client.transfer(&alice, &bob, &id);
    assert_eq!(client.owner_of(&id), bob);
    // approval-for-all lets the operator move it back
    client.approve_for_all(&bob, &operator, &1000u32);
    client.transfer_from(&operator, &bob, &alice, &id);
    assert_eq!(client.owner_of(&id), alice);
}

#[test]
fn royalty_default_and_adjustable() {
    let (env, client, _, creator) = setup(500);
    let bob = Address::generate(&env);
    let id = client.mint(&creator, &String::from_str(&env, "ipfs://1"));
    let (receiver, amount) = client.royalty_info(&id, &10_000i128);
    assert_eq!(receiver, creator);
    assert_eq!(amount, 500);
    client.set_default_royalty(&bob, &100u32);
    let (receiver, amount) = client.royalty_info(&id, &10_000i128);
    assert_eq!(receiver, bob);
    assert_eq!(amount, 100);
}

#[test]
fn transfer_ownership_moves_mint_right() {
    let (env, client, _, _) = setup(0);
    let alice = Address::generate(&env);
    client.transfer_ownership(&alice);
    assert_eq!(client.owner(), alice);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://1"));
    assert_eq!(id, 1);
    assert_eq!(client.get_token_creator(&id), alice);
}
