#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, Address,
    BytesN, Env, IntoVal, String, Symbol, Val, Vec,
};

/// Permissionless registry of IP collections. Anyone can create a collection;
/// the caller becomes its owner. The registry itself has no owner, takes no
/// fees, and holds no rights over created collections. A protocol upgrade is
/// a fresh registry + collection-WASM deployment.
#[contract]
pub struct MipRegistry;

#[contracttype]
pub enum DataKey {
    CollectionWasm,
    Count,
    Collection(u64),
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum RegistryError {
    AlreadyInitialized = 1,
    NotInitialized = 2,
}

const EVT_CREATED: Symbol = symbol_short!("created");

#[contractimpl]
impl MipRegistry {
    /// One-time setup: stores the collection contract's WASM hash the
    /// registry deploys instances from.
    pub fn init(e: Env, collection_wasm: BytesN<32>) {
        if e.storage().instance().has(&DataKey::CollectionWasm) {
            panic_with_error!(&e, RegistryError::AlreadyInitialized);
        }
        e.storage().instance().set(&DataKey::CollectionWasm, &collection_wasm);
    }

    /// Deploys a new collection owned by the caller. `royalty_bps` sets the
    /// collection's default royalty with the caller as receiver (0 = none).
    pub fn create_collection(
        e: Env,
        creator: Address,
        name: String,
        symbol: String,
        base_uri: String,
        royalty_bps: u32,
    ) -> (u64, Address) {
        creator.require_auth();
        let wasm: BytesN<32> = e
            .storage()
            .instance()
            .get(&DataKey::CollectionWasm)
            .unwrap_or_else(|| panic_with_error!(&e, RegistryError::NotInitialized));

        let collection_id: u64 = e.storage().instance().get(&DataKey::Count).unwrap_or(0) + 1;
        e.storage().instance().set(&DataKey::Count, &collection_id);

        let salt: BytesN<32> = {
            let mut bytes = [0u8; 32];
            bytes[24..].copy_from_slice(&collection_id.to_be_bytes());
            BytesN::from_array(&e, &bytes)
        };
        let address = e
            .deployer()
            .with_current_contract(salt)
            .deploy_v2(wasm, ());

        let init_args: Vec<Val> = (
            e.current_contract_address(),
            collection_id,
            creator.clone(),
            name.clone(),
            symbol,
            base_uri,
            royalty_bps,
        )
            .into_val(&e);
        let _: Val = e.invoke_contract(&address, &Symbol::new(&e, "initialize"), init_args);

        e.storage()
            .persistent()
            .set(&DataKey::Collection(collection_id), &(address.clone(), creator.clone()));

        e.events()
            .publish((EVT_CREATED, collection_id), (address.clone(), creator, name));

        (collection_id, address)
    }

    pub fn get_collection(e: Env, collection_id: u64) -> (Address, Address) {
        e.storage().persistent().get(&DataKey::Collection(collection_id)).unwrap()
    }

    pub fn collection_count(e: Env) -> u64 {
        e.storage().instance().get(&DataKey::Count).unwrap_or(0)
    }

    pub fn is_valid_collection(e: Env, collection_id: u64) -> bool {
        e.storage().persistent().has(&DataKey::Collection(collection_id))
    }

    pub fn version(e: Env) -> String {
        String::from_str(&e, "1.0.0")
    }
}

mod test;
