use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct PlanRecord {
    pub id: u256,
    pub price: u256,
    pub duration: u64,
    pub tier: felt252,
    pub payment_token: Option<ContractAddress>,
    pub recipient: ContractAddress,
    pub metadata_uri: ByteArray,
    pub active: bool,
    pub exists: bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SubscriptionRecord {
    pub subscriber: ContractAddress,
    pub plan_id: u256,
    pub started_at: u64,
    pub expires_at: u64,
    pub active: bool,
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
