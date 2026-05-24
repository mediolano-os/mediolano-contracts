use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct TokenData {
    pub token_id: u256,
    pub owner: ContractAddress,
    pub metadata_uri: ByteArray,
    pub issuer: ContractAddress,
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

    #[test]
    fn test_bytearray_starts_with_shorter_than_needle() {
        let uri: ByteArray = "ip";
        let prefix: ByteArray = "ipfs://";
        assert(!bytearray_starts_with(@uri, @prefix), 'shorter fails');
    }
}
