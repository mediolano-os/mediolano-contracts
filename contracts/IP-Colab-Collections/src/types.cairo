use starknet::{ClassHash, ContractAddress};

pub const MAX_NAME_LEN: u32 = 64;
pub const MAX_SYMBOL_LEN: u32 = 16;
pub const MAX_BASE_URI_LEN: u32 = 2048;
pub const MAX_TOKEN_URI_LEN: u32 = 2048;
pub const URI_POLICY_CONTENT_ADDRESSED: felt252 = 'CONTENT_ADDRESSED';

pub const STATUS_PENDING: u8 = 0;
pub const STATUS_APPROVED: u8 = 1;
pub const STATUS_REJECTED: u8 = 2;
pub const STATUS_MINTED: u8 = 3;
pub const STATUS_ARCHIVED: u8 = 4;

#[derive(Drop, Serde)]
pub struct CollectionConfig {
    pub owner: ContractAddress,
    pub collection_issuer: ContractAddress,
    pub ip_nft: ContractAddress,
    pub ip_nft_class_hash: ClassHash,
    pub total_contributions: u256,
    pub total_minted: u256,
    pub uri_policy: felt252,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct ContributionType {
    pub type_id: felt252,
    pub min_quality_score: u8,
    pub submission_deadline: u64,
    pub max_supply: u256,
    pub approved_count: u256,
    pub minted_count: u256,
    pub exists: bool,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Contribution {
    pub contribution_id: u256,
    pub contributor: ContractAddress,
    pub token_uri: ByteArray,
    pub contribution_type: felt252,
    pub quality_score: u8,
    pub submitted_at: u64,
    pub reviewed_at: u64,
    pub minted_at: u64,
    pub status: u8,
    pub token_id: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct TokenData {
    pub ip_nft: ContractAddress,
    pub token_id: u256,
    pub contribution_id: u256,
    pub owner: ContractAddress,
    pub metadata_uri: ByteArray,
    pub contributor: ContractAddress,
    pub registered_at: u64,
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

#[cfg(test)]
mod tests {
    use super::bytearray_starts_with;

    #[test]
    fn test_bytearray_starts_with_ipfs() {
        let uri: ByteArray = "ipfs://QmFoo";
        let prefix: ByteArray = "ipfs://";
        assert(bytearray_starts_with(@uri, @prefix), 'should match ipfs');
    }

    #[test]
    fn test_bytearray_starts_with_ar() {
        let uri: ByteArray = "ar://txid123";
        let prefix: ByteArray = "ar://";
        assert(bytearray_starts_with(@uri, @prefix), 'should match ar');
    }

    #[test]
    fn test_bytearray_starts_with_http_fails() {
        let uri: ByteArray = "https://example.com";
        let prefix: ByteArray = "ipfs://";
        assert(!bytearray_starts_with(@uri, @prefix), 'should not match');
    }
}
