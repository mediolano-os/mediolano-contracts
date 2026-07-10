use starknet::ContractAddress;

/// One entry per `create_event` call. Stored at `events[token_id]`.
/// `creator` is zero iff the event was never created — used as existence check.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct EventRecord {
    pub creator: ContractAddress,
    pub max_supply: u256,
    pub minted: u256,
    pub start_time: Option<u64>,
    pub end_time: Option<u64>,
    pub royalty_bps: u16,
    pub metadata_uri: ByteArray,
    pub active: bool,
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
