#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, Address, Env, String,
    Vec,
};
use stellar_tokens::non_fungible::Base;

/// An IP collection: an NFT contract owned by its creator. Deployed by the
/// MIP registry, which holds no rights over it after creation. Each token
/// carries an immutable registration record — complete metadata URI (never
/// composed from the base URI), original creator, and registration timestamp —
/// plus an immutable per-token royalty set at mint with the minting owner as
/// receiver. A token's holder can archive it, permanently freezing it in
/// place while preserving the record.
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
    TokenRegisteredAt(u32),
    Archived(u32),
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum MipError {
    AlreadyInitialized = 1,
    RoyaltyBpsTooHigh = 2,
    LengthMismatch = 3,
    InvalidName = 4,
    InvalidSymbol = 5,
    InvalidUri = 6,
    TokenArchived = 7,
    AlreadyArchived = 8,
    EmptyBatch = 9,
    SameOwner = 10,
}

const MAX_NAME_LEN: u32 = 256;
const MAX_SYMBOL_LEN: u32 = 64;
const MAX_BASE_URI_LEN: u32 = 2048;
const MAX_TOKEN_URI_LEN: u32 = 2048;

#[contractimpl]
impl MipCollection {
    pub fn initialize(
        e: Env,
        registry: Address,
        collection_id: u64,
        creator: Address,
        name: String,
        symbol: String,
        base_uri: String,
    ) {
        if e.storage().instance().has(&DataKey::Owner) {
            panic_with_error!(&e, MipError::AlreadyInitialized);
        }
        if name.is_empty() || name.len() > MAX_NAME_LEN {
            panic_with_error!(&e, MipError::InvalidName);
        }
        if symbol.is_empty() || symbol.len() > MAX_SYMBOL_LEN {
            panic_with_error!(&e, MipError::InvalidSymbol);
        }
        if base_uri.len() > MAX_BASE_URI_LEN {
            panic_with_error!(&e, MipError::InvalidUri);
        }
        Base::set_metadata(&e, base_uri, name, symbol);
        e.storage().instance().set(&DataKey::Registry, &registry);
        e.storage().instance().set(&DataKey::CollectionId, &collection_id);
        e.storage().instance().set(&DataKey::Owner, &creator);
    }

    /// Mints the next sequential token to `to` with its complete metadata
    /// URI. The collection owner is the only minter; the owner at mint time
    /// is recorded as the token's creator with the ledger timestamp as its
    /// registration date. `royalty_bps` sets the token's immutable royalty
    /// with the creator as receiver — never the (mutable) collection owner,
    /// so royalties cannot be redirected by a later ownership transfer. No
    /// setter exists.
    pub fn mint(e: Env, to: Address, uri: String, royalty_bps: u32) -> u32 {
        let owner = Self::owner(e.clone());
        owner.require_auth();
        Self::mint_record(&e, &owner, &to, &uri, royalty_bps)
    }

    /// Mints one token per recipient/URI/royalty triple. Vectors must align.
    pub fn batch_mint(
        e: Env,
        to: Vec<Address>,
        uris: Vec<String>,
        royalty_bps: Vec<u32>,
    ) -> Vec<u32> {
        if to.is_empty() {
            panic_with_error!(&e, MipError::EmptyBatch);
        }
        if to.len() != uris.len() || to.len() != royalty_bps.len() {
            panic_with_error!(&e, MipError::LengthMismatch);
        }
        let owner = Self::owner(e.clone());
        owner.require_auth();
        let mut ids = Vec::new(&e);
        for i in 0..to.len() {
            let token_id = Self::mint_record(
                &e,
                &owner,
                &to.get(i).unwrap(),
                &uris.get(i).unwrap(),
                royalty_bps.get(i).unwrap(),
            );
            ids.push_back(token_id);
        }
        ids
    }

    /// Permanently freezes a token in its current wallet, preserving the
    /// registration record forever. Replaces destructive burn. Only the
    /// token's holder may archive it — archiving is the holder's right, not
    /// the collection owner's. Archived tokens cannot be transferred.
    pub fn archive(e: Env, token_id: u32) {
        let token_owner = Base::owner_of(&e, token_id);
        token_owner.require_auth();
        if Self::is_archived(e.clone(), token_id) {
            panic_with_error!(&e, MipError::AlreadyArchived);
        }
        e.storage().persistent().set(&DataKey::Archived(token_id), &true);
    }

    pub fn is_archived(e: Env, token_id: u32) -> bool {
        e.storage()
            .persistent()
            .get(&DataKey::Archived(token_id))
            .unwrap_or(false)
    }

    pub fn transfer_ownership(e: Env, new_owner: Address) {
        let owner = Self::owner(e.clone());
        owner.require_auth();
        if new_owner == owner {
            panic_with_error!(&e, MipError::SameOwner);
        }
        e.storage().instance().set(&DataKey::Owner, &new_owner);
    }

    pub fn royalty_info(e: Env, token_id: u32, sale_price: i128) -> (Address, i128) {
        Base::royalty_info(&e, token_id, sale_price)
    }

    // Standard NFT surface, delegated to the OpenZeppelin base. `token_uri`
    // is overridden: URIs are complete values set at mint. Transfers of
    // archived tokens panic.
    pub fn balance(e: Env, account: Address) -> u32 {
        Base::balance(&e, &account)
    }

    pub fn owner_of(e: Env, token_id: u32) -> Address {
        Base::owner_of(&e, token_id)
    }

    pub fn transfer(e: Env, from: Address, to: Address, token_id: u32) {
        Self::require_not_archived(&e, token_id);
        Base::transfer(&e, &from, &to, token_id);
    }

    pub fn transfer_from(e: Env, spender: Address, from: Address, to: Address, token_id: u32) {
        Self::require_not_archived(&e, token_id);
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

    pub fn get_token_registered_at(e: Env, token_id: u32) -> u64 {
        e.storage()
            .persistent()
            .get(&DataKey::TokenRegisteredAt(token_id))
            .unwrap()
    }

    /// Returns the full registration record for a token in a single call:
    /// current owner, metadata URI, original creator, registration timestamp.
    pub fn get_full_token_data(e: Env, token_id: u32) -> (Address, String, Address, u64) {
        let owner = Base::owner_of(&e, token_id);
        let uri: String = e.storage().persistent().get(&DataKey::TokenUri(token_id)).unwrap();
        let creator: Address =
            e.storage().persistent().get(&DataKey::TokenCreator(token_id)).unwrap();
        let registered_at: u64 = e
            .storage()
            .persistent()
            .get(&DataKey::TokenRegisteredAt(token_id))
            .unwrap();
        (owner, uri, creator, registered_at)
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

    /// Writes one token's immutable registration record and mints it.
    fn mint_record(e: &Env, owner: &Address, to: &Address, uri: &String, royalty_bps: u32) -> u32 {
        if uri.is_empty() || uri.len() > MAX_TOKEN_URI_LEN {
            panic_with_error!(e, MipError::InvalidUri);
        }
        if royalty_bps > 10_000 {
            panic_with_error!(e, MipError::RoyaltyBpsTooHigh);
        }
        let token_id = Self::next_token_id(e);
        Base::mint(e, to, token_id);
        e.storage().persistent().set(&DataKey::TokenUri(token_id), uri);
        e.storage().persistent().set(&DataKey::TokenCreator(token_id), owner);
        e.storage()
            .persistent()
            .set(&DataKey::TokenRegisteredAt(token_id), &e.ledger().timestamp());
        Base::set_token_royalty(e, token_id, owner, royalty_bps);
        token_id
    }

    fn require_not_archived(e: &Env, token_id: u32) {
        if Self::is_archived(e.clone(), token_id) {
            panic_with_error!(e, MipError::TokenArchived);
        }
    }

    /// Sequential token ids from 1.
    fn next_token_id(e: &Env) -> u32 {
        let next: u32 = e.storage().instance().get(&DataKey::NextTokenId).unwrap_or(1);
        e.storage().instance().set(&DataKey::NextTokenId, &(next + 1));
        next
    }
}

mod test;
