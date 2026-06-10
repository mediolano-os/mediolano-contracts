use starknet::ContractAddress;

// A series exists iff `creator != 0` (create_ticket_series rejects a zero
// caller). `active` gates minting only — never transfers or redemption.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct TicketSeries {
    pub creator: ContractAddress,
    pub price: u256,
    pub max_supply: u256,
    pub minted: u256,
    pub expiration: u64,
    pub royalty_bps: u256,
    pub payment_token: Option<ContractAddress>,
    pub metadata_uri: ByteArray,
    pub active: bool,
}

#[derive(Drop, Serde)]
pub struct TicketData {
    pub token_id: u256,
    pub owner: ContractAddress,
    pub series_id: u256,
    pub creator: ContractAddress,
    pub metadata_uri: ByteArray,
    pub expiration: u64,
    pub redeemed: bool,
    pub valid: bool,
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
