use starknet::ContractAddress;

#[derive(Drop, Clone, Serde, starknet::Store)]
pub struct Negotiation {
    pub negotiation_id: u256,
    pub seller: ContractAddress,
    pub buyer: ContractAddress,
    pub ip_asset_contract: ContractAddress,
    pub ip_token_id: u256,
    pub payment_token: ContractAddress,
    pub price: u256,
    pub escrowed_amount: u256,
    pub released_amount: u256,
    pub refunded_amount: u256,
    pub deadline: u64,
    pub status: NegotiationStatus,
    pub listing_uri: ByteArray,
    pub listing_hash: felt252,
    pub terms_uri: ByteArray,
    pub terms_hash: felt252,
    pub fulfillment_hash: felt252,
    pub exists: bool,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum NegotiationStatus {
    #[default]
    Open,
    Funded,
    FulfillmentSubmitted,
    Completed,
    Cancelled,
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
