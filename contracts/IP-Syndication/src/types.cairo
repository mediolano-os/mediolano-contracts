use starknet::ContractAddress;

#[derive(Drop, Clone, Serde, starknet::Store)]
pub struct IPMetadata {
    pub ip_id: u256,
    pub owner: ContractAddress,
    pub target_amount: u256,
    pub name: felt252,
    pub description: ByteArray,
    pub metadata_uri: ByteArray,
    pub licensing_terms: felt252,
    pub token_id: u256,
    pub exists: bool,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct SyndicationDetails {
    pub ip_id: u256,
    pub status: Status,
    pub mode: Mode,
    pub total_raised: u256,
    pub participant_count: u256,
    pub payment_token: ContractAddress,
    pub proceeds_claimed: bool,
    pub exists: bool,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct ParticipantDetails {
    pub participant: ContractAddress,
    pub amount_deposited: u256,
    pub amount_refunded: u256,
    pub share: u256,
    pub share_minted: bool,
    pub exists: bool,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum Status {
    #[default]
    Pending,
    Active,
    Completed,
    Cancelled,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum Mode {
    #[default]
    Public,
    Whitelist,
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
