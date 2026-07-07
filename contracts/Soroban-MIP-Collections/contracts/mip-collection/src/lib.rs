#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, Address, Env, String,
    Vec,
};
use stellar_tokens::non_fungible::Base;

/// An IP collection: an NFT contract owned by its creator. Deployed by the
/// MIP registry, which holds no rights over it after creation. Tokens carry
/// complete per-token metadata URIs set at mint (never composed from the base
/// URI) and the OpenZeppelin Stellar royalties interface with a creator-set,
/// owner-adjustable default.
#[contract]
pub struct MipCollection;

#[contracttype]
pub enum DataKey {
    Registry,
    CollectionId,
    Owner,
    NextTokenId,
    TokenUri(u32),
    TokenCreator(u32),
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum MipError {
    AlreadyInitialized = 1,
    RoyaltyBpsTooHigh = 2,
    LengthMismatch = 3,
}

#[contractimpl]
impl MipCollection {
    #[allow(clippy::too_many_arguments)]
    pub fn initialize(
        e: Env,
        registry: Address,
        collection_id: u64,
        creator: Address,
        name: String,
        symbol: String,
        base_uri: String,
        royalty_bps: u32,
    ) {
        if e.storage().instance().has(&DataKey::Owner) {
            panic_with_error!(&e, MipError::AlreadyInitialized);
        }
        if royalty_bps > 10_000 {
            panic_with_error!(&e, MipError::RoyaltyBpsTooHigh);
        }
        Base::set_metadata(&e, base_uri, name, symbol);
        e.storage().instance().set(&DataKey::Registry, &registry);
        e.storage().instance().set(&DataKey::CollectionId, &collection_id);
        e.storage().instance().set(&DataKey::Owner, &creator);
        if royalty_bps > 0 {
            Base::set_default_royalty(&e, &creator, royalty_bps);
        }
    }

    /// Mints the next sequential token to `to` with its complete metadata
    /// URI. The collection owner is the only minter; the owner at mint time
    /// is recorded as the token's creator.
    pub fn mint(e: Env, to: Address, uri: String) -> u32 {
        let owner = Self::owner(e.clone());
        owner.require_auth();
        let token_id = Self::next_token_id(&e);
        Base::mint(&e, &to, token_id);
        e.storage().persistent().set(&DataKey::TokenUri(token_id), &uri);
        e.storage().persistent().set(&DataKey::TokenCreator(token_id), &owner);
        token_id
    }

    /// Mints one token per recipient/URI pair. Vectors must align.
    pub fn batch_mint(e: Env, to: Vec<Address>, uris: Vec<String>) -> Vec<u32> {
        if to.len() != uris.len() {
            panic_with_error!(&e, MipError::LengthMismatch);
        }
        let owner = Self::owner(e.clone());
        owner.require_auth();
        let mut ids = Vec::new(&e);
        for i in 0..to.len() {
            let token_id = Self::next_token_id(&e);
            Base::mint(&e, &to.get(i).unwrap(), token_id);
            e.storage()
                .persistent()
                .set(&DataKey::TokenUri(token_id), &uris.get(i).unwrap());
            e.storage()
                .persistent()
                .set(&DataKey::TokenCreator(token_id), &owner);
            ids.push_back(token_id);
        }
        ids
    }

    pub fn transfer_ownership(e: Env, new_owner: Address) {
        let owner = Self::owner(e.clone());
        owner.require_auth();
        e.storage().instance().set(&DataKey::Owner, &new_owner);
    }

    pub fn set_default_royalty(e: Env, receiver: Address, royalty_bps: u32) {
        let owner = Self::owner(e.clone());
        owner.require_auth();
        if royalty_bps > 10_000 {
            panic_with_error!(&e, MipError::RoyaltyBpsTooHigh);
        }
        Base::set_default_royalty(&e, &receiver, royalty_bps);
    }

    pub fn royalty_info(e: Env, token_id: u32, sale_price: i128) -> (Address, i128) {
        Base::royalty_info(&e, token_id, sale_price)
    }

    // Standard NFT surface, delegated to the OpenZeppelin base. `token_uri`
    // is overridden: URIs are complete values set at mint.
    pub fn balance(e: Env, account: Address) -> u32 {
        Base::balance(&e, &account)
    }

    pub fn owner_of(e: Env, token_id: u32) -> Address {
        Base::owner_of(&e, token_id)
    }

    pub fn transfer(e: Env, from: Address, to: Address, token_id: u32) {
        Base::transfer(&e, &from, &to, token_id);
    }

    pub fn transfer_from(e: Env, spender: Address, from: Address, to: Address, token_id: u32) {
        Base::transfer_from(&e, &spender, &from, &to, token_id);
    }

    pub fn approve(e: Env, approver: Address, approved: Address, token_id: u32, live_until_ledger: u32) {
        Base::approve(&e, &approver, &approved, token_id, live_until_ledger);
    }

    pub fn approve_for_all(e: Env, owner: Address, operator: Address, live_until_ledger: u32) {
        Base::approve_for_all(&e, &owner, &operator, live_until_ledger);
    }

    pub fn token_uri(e: Env, token_id: u32) -> String {
        e.storage().persistent().get(&DataKey::TokenUri(token_id)).unwrap()
    }

    pub fn token_exists(e: Env, token_id: u32) -> bool {
        e.storage().persistent().has(&DataKey::TokenUri(token_id))
    }

    pub fn get_token_creator(e: Env, token_id: u32) -> Address {
        e.storage().persistent().get(&DataKey::TokenCreator(token_id)).unwrap()
    }

    pub fn name(e: Env) -> String {
        Base::name(&e)
    }

    pub fn symbol(e: Env) -> String {
        Base::symbol(&e)
    }

    /// Collection-level metadata pointer; token URIs are complete URIs.
    pub fn collection_base_uri(e: Env) -> String {
        Base::base_uri(&e)
    }

    pub fn owner(e: Env) -> Address {
        e.storage().instance().get(&DataKey::Owner).unwrap()
    }

    pub fn registry(e: Env) -> Address {
        e.storage().instance().get(&DataKey::Registry).unwrap()
    }

    pub fn collection_id(e: Env) -> u64 {
        e.storage().instance().get(&DataKey::CollectionId).unwrap()
    }

    pub fn version(e: Env) -> String {
        String::from_str(&e, "1.0.0")
    }

    /// Sequential token ids from 1.
    fn next_token_id(e: &Env) -> u32 {
        let next: u32 = e.storage().instance().get(&DataKey::NextTokenId).unwrap_or(1);
        e.storage().instance().set(&DataKey::NextTokenId, &(next + 1));
        next
    }
}

mod test;
