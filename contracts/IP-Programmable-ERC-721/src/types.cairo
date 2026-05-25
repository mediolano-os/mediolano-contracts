use starknet::ContractAddress;

/// Represents all provenance fields for a single minted IP token.
/// Returned by `get_token_data` in a single call to avoid multiple round-trips.
#[derive(Drop, Serde, starknet::Store)]
pub struct TokenData {
    /// The unique identifier of the token within this collection.
    pub token_id: u256,
    /// Current owner of the token.
    pub owner: ContractAddress,
    /// Full content-addressed URI (ipfs:// or ar://). Written once at mint, never modified.
    pub metadata_uri: ByteArray,
    /// Original minter — immutable Berne Convention authorship record.
    pub original_creator: ContractAddress,
    /// Block timestamp at mint — immutable proof of creation date.
    pub registered_at: u64,
}

/// Returns true if `haystack` starts with `needle`, compared byte-by-byte.
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
        assert(bytearray_starts_with(@uri, @prefix), 'should match ipfs prefix');
    }

    #[test]
    fn test_bytearray_starts_with_ar() {
        let uri: ByteArray = "ar://txid123";
        let prefix: ByteArray = "ar://";
        assert(bytearray_starts_with(@uri, @prefix), 'should match ar prefix');
    }

    #[test]
    fn test_bytearray_starts_with_http_fails() {
        let uri: ByteArray = "https://example.com";
        let prefix: ByteArray = "ipfs://";
        assert(!bytearray_starts_with(@uri, @prefix), 'should not match ipfs');
    }

    #[test]
    fn test_bytearray_starts_with_shorter_than_needle() {
        let uri: ByteArray = "ip";
        let prefix: ByteArray = "ipfs://";
        assert(!bytearray_starts_with(@uri, @prefix), 'shorter should not match');
    }
}
