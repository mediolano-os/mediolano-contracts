use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Default)]
pub enum IPProtectionLevel {
    #[default]
    STANDARD,
    ADVANCED,
}

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct PublicUserSettings {
    pub user: ContractAddress,
    pub default_ip_protection_level: IPProtectionLevel,
    pub automatic_ip_registration: bool,
    pub encrypted_preferences_uri: ByteArray,
    pub encrypted_preferences_hash: felt252,
    pub revision: u64,
    pub updated_at: u64,
    pub exists: bool,
}

pub fn bytearray_starts_with(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let n = needle.len();
    if haystack.len() < n {
        return false;
    }

    let mut i: u32 = 0;
    let mut matches = true;
    while i < n {
        if haystack.at(i).unwrap() != needle.at(i).unwrap() {
            matches = false;
            break;
        }
        i += 1;
    }

    matches
}

pub fn hash_bytearray(data: @ByteArray) -> felt252 {
    let mut serialized = array![];
    data.serialize(ref serialized);

    let len = serialized.len();
    let mut state = PoseidonTrait::new();
    for elem in serialized {
        state = state.update_with(elem);
    }
    state.update_with(len).finalize()
}
