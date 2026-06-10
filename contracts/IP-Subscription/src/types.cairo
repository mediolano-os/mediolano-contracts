use starknet::ContractAddress;

// A plan exists iff `creator != 0` (create_plan rejects a zero caller).
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct PlanRecord {
    pub creator: ContractAddress,
    pub recipient: ContractAddress,
    pub price: u256,
    pub duration: u64,
    pub payment_token: Option<ContractAddress>,
    pub metadata_uri: ByteArray,
    pub active: bool,
}

// A subscription exists iff `expires_at != 0`. It is active iff `expires_at >= now`.
// Renewal extends `expires_at`; `started_at` marks the beginning of the current streak.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SubscriptionRecord {
    pub started_at: u64,
    pub expires_at: u64,
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
