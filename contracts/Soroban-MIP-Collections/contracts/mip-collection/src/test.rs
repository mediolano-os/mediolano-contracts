#![cfg(test)]

use soroban_sdk::{testutils::{Address as _, Ledger as _}, Address, Env, String, Vec};

use crate::{MipCollection, MipCollectionClient};

fn setup() -> (Env, MipCollectionClient<'static>, Address, Address) {
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
    );
    (env, client, registry, creator)
}

#[test]
fn initialize_sets_state() {
    let (env, client, registry, creator) = setup();
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
    let (env, client, registry, creator) = setup();
    client.initialize(
        &registry,
        &2u64,
        &creator,
        &String::from_str(&env, "X"),
        &String::from_str(&env, "X"),
        &String::from_str(&env, ""),
    );
}

#[test]
#[should_panic]
fn initialize_rejects_empty_name() {
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
        &String::from_str(&env, ""),
        &String::from_str(&env, "MIP"),
        &String::from_str(&env, ""),
    );
}

#[test]
fn mint_sequential_from_one_with_complete_uri() {
    let (env, client, _, creator) = setup();
    let alice = Address::generate(&env);
    let first = client.mint(&alice, &String::from_str(&env, "ipfs://token/1"), &0u32);
    let second = client.mint(&alice, &String::from_str(&env, "ipfs://token/2"), &0u32);
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
fn mint_records_registration_record() {
    let (env, client, _, creator) = setup();
    env.ledger().set_timestamp(1_720_000_000);
    let alice = Address::generate(&env);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://token/1"), &0u32);
    assert_eq!(client.get_token_registered_at(&id), 1_720_000_000);
    let (owner, uri, original_creator, registered_at) = client.get_full_token_data(&id);
    assert_eq!(owner, alice);
    assert_eq!(uri, String::from_str(&env, "ipfs://token/1"));
    assert_eq!(original_creator, creator);
    assert_eq!(registered_at, 1_720_000_000);
}

#[test]
#[should_panic]
fn mint_rejects_empty_uri() {
    let (env, client, _, _) = setup();
    let alice = Address::generate(&env);
    client.mint(&alice, &String::from_str(&env, ""), &0u32);
}

#[test]
#[should_panic]
fn mint_rejects_high_bps() {
    let (env, client, _, _) = setup();
    let alice = Address::generate(&env);
    client.mint(&alice, &String::from_str(&env, "ipfs://1"), &10_001u32);
}

#[test]
fn batch_mint() {
    let (env, client, _, creator) = setup();
    let alice = Address::generate(&env);
    let bob = Address::generate(&env);
    let mut to = Vec::new(&env);
    to.push_back(alice.clone());
    to.push_back(bob.clone());
    let mut uris = Vec::new(&env);
    uris.push_back(String::from_str(&env, "ipfs://1"));
    uris.push_back(String::from_str(&env, "ipfs://2"));
    let mut bps = Vec::new(&env);
    bps.push_back(100u32);
    bps.push_back(250u32);
    let ids = client.batch_mint(&to, &uris, &bps);
    assert_eq!(ids.len(), 2);
    assert_eq!(client.owner_of(&ids.get(1).unwrap()), bob);
    assert_eq!(client.token_uri(&ids.get(0).unwrap()), String::from_str(&env, "ipfs://1"));
    let (receiver, amount) = client.royalty_info(&ids.get(1).unwrap(), &10_000i128);
    assert_eq!(receiver, creator);
    assert_eq!(amount, 250);
}

#[test]
#[should_panic]
fn batch_mint_length_mismatch() {
    let (env, client, _, _) = setup();
    let alice = Address::generate(&env);
    let mut to = Vec::new(&env);
    to.push_back(alice);
    let uris: Vec<String> = Vec::new(&env);
    let bps: Vec<u32> = Vec::new(&env);
    client.batch_mint(&to, &uris, &bps);
}

#[test]
#[should_panic]
fn batch_mint_rejects_empty_batch() {
    let (env, client, _, _) = setup();
    let to: Vec<Address> = Vec::new(&env);
    let uris: Vec<String> = Vec::new(&env);
    let bps: Vec<u32> = Vec::new(&env);
    client.batch_mint(&to, &uris, &bps);
}

#[test]
fn transfer_and_approvals() {
    let (env, client, _, _) = setup();
    let alice = Address::generate(&env);
    let bob = Address::generate(&env);
    let operator = Address::generate(&env);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://1"), &0u32);
    client.transfer(&alice, &bob, &id);
    assert_eq!(client.owner_of(&id), bob);
    // approval-for-all lets the operator move it back
    client.approve_for_all(&bob, &operator, &1000u32);
    client.transfer_from(&operator, &bob, &alice, &id);
    assert_eq!(client.owner_of(&id), alice);
}

#[test]
fn archive_by_holder_blocks_transfer() {
    let (env, client, _, _) = setup();
    let alice = Address::generate(&env);
    let bob = Address::generate(&env);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://1"), &0u32);
    client.archive(&id);
    assert!(client.is_archived(&id));
    // record preserved, movement permanently blocked
    assert_eq!(client.owner_of(&id), alice);
    assert!(client.try_transfer(&alice, &bob, &id).is_err());
    assert!(client.try_transfer_from(&bob, &alice, &bob, &id).is_err());
    // double archive rejected
    assert!(client.try_archive(&id).is_err());
}

#[test]
fn royalty_per_token_immutable_to_creator() {
    let (env, client, _, creator) = setup();
    let alice = Address::generate(&env);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://1"), &500u32);
    let (receiver, amount) = client.royalty_info(&id, &10_000i128);
    assert_eq!(receiver, creator);
    assert_eq!(amount, 500);
    // a collection ownership transfer must not redirect existing royalties
    let bob = Address::generate(&env);
    client.transfer_ownership(&bob);
    let (receiver, amount) = client.royalty_info(&id, &10_000i128);
    assert_eq!(receiver, creator);
    assert_eq!(amount, 500);
    // tokens minted by the new owner carry the new owner as receiver
    let id2 = client.mint(&alice, &String::from_str(&env, "ipfs://2"), &100u32);
    let (receiver, amount) = client.royalty_info(&id2, &10_000i128);
    assert_eq!(receiver, bob);
    assert_eq!(amount, 100);
}

#[test]
fn transfer_ownership_moves_mint_right() {
    let (env, client, _, _) = setup();
    let alice = Address::generate(&env);
    client.transfer_ownership(&alice);
    assert_eq!(client.owner(), alice);
    let id = client.mint(&alice, &String::from_str(&env, "ipfs://1"), &0u32);
    assert_eq!(id, 1);
    assert_eq!(client.get_token_creator(&id), alice);
}

#[test]
#[should_panic]
fn transfer_ownership_rejects_same_owner() {
    let (_env, client, _, creator) = setup();
    client.transfer_ownership(&creator);
}
