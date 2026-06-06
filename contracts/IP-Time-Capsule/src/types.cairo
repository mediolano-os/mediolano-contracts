use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::ContractAddress;

pub const MAX_NAME_LEN: u32 = 64;
pub const MAX_SYMBOL_LEN: u32 = 16;
pub const MAX_URI_LEN: u32 = 2048;
pub const COMMITMENT_SCHEME_POSEIDON_HASH_SALT: felt252 = 'POSEIDON_HASH_SALT';
pub const STATUS_SEALED: u8 = 0;
pub const STATUS_REVEALED: u8 = 1;

#[derive(Drop, Serde, starknet::Store)]
pub struct TimeCapsule {
    pub token_id: u256,
    pub creator: ContractAddress,
    pub encrypted_uri: ByteArray,
    pub content_commitment: felt252,
    pub reveal_at: u64,
    pub revealed_uri: ByteArray,
    pub revealed_at: u64,
    pub content_hash: felt252,
    pub content_salt: felt252,
    pub status: u8,
}

#[derive(Drop, Serde)]
pub struct TimeCapsuleData {
    pub token_id: u256,
    pub owner: ContractAddress,
    pub creator: ContractAddress,
    pub encrypted_uri: ByteArray,
    pub content_commitment: felt252,
    pub reveal_at: u64,
    pub revealed_uri: ByteArray,
    pub revealed_at: u64,
    pub content_hash: felt252,
    pub content_salt: felt252,
    pub status: u8,
}

pub fn compute_content_commitment(content_hash: felt252, content_salt: felt252) -> felt252 {
    PoseidonTrait::new().update_with(content_hash).update_with(content_salt).finalize()
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

pub fn is_supported_uri(uri: @ByteArray) -> bool {
    bytearray_starts_with(uri, @"ipfs://") || bytearray_starts_with(uri, @"ar://")
}

#[cfg(test)]
mod tests {
    use super::{bytearray_starts_with, compute_content_commitment, is_supported_uri};

    #[test]
    fn test_bytearray_starts_with_ipfs() {
        let uri: ByteArray = "ipfs://QmFoo";
        assert(bytearray_starts_with(@uri, @"ipfs://"), 'should match ipfs');
    }

    #[test]
    fn test_bytearray_starts_with_ar() {
        let uri: ByteArray = "ar://txid123";
        assert(bytearray_starts_with(@uri, @"ar://"), 'should match ar');
    }

    #[test]
    fn test_bytearray_starts_with_http_fails() {
        let uri: ByteArray = "https://example.com";
        assert(!bytearray_starts_with(@uri, @"ipfs://"), 'should not match');
    }

    #[test]
    fn test_is_supported_uri_rejects_empty() {
        let uri: ByteArray = "";
        assert(!is_supported_uri(@uri), 'empty uri invalid');
    }

    #[test]
    fn test_compute_content_commitment_is_salted() {
        let commitment = compute_content_commitment(0x123, 0x456);
        let other = compute_content_commitment(0x123, 0x789);
        assert(commitment != 0, 'commitment is zero');
        assert(commitment != other, 'salt should change hash');
    }
}
