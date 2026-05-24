use starknet::ContractAddress;

#[derive(Drop, Clone, Serde, starknet::Store)]
pub struct Commission {
    pub commission_id: u256,
    pub commissioner: ContractAddress,
    pub invited_creator: ContractAddress,
    pub creator: ContractAddress,
    pub payment_token: ContractAddress,
    pub total_amount: u256,
    pub escrowed_amount: u256,
    pub released_amount: u256,
    pub refunded_amount: u256,
    pub milestone_count: u32,
    pub approved_milestone_count: u32,
    pub revisions_allowed: u32,
    pub deadline: u64,
    pub status: CommissionStatus,
    pub mode: OfferMode,
    pub brief_uri: ByteArray,
    pub brief_hash: felt252,
    pub license_uri: ByteArray,
    pub license_hash: felt252,
    pub exists: bool,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct MilestoneDetails {
    pub commission_id: u256,
    pub milestone_index: u32,
    pub amount: u256,
    pub status: MilestoneStatus,
    pub revision_count: u32,
    pub deliverable_hash: felt252,
    pub submitted_at: u64,
    pub approved_at: u64,
    pub exists: bool,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum CommissionStatus {
    #[default]
    Open,
    Funded,
    InProgress,
    Completed,
    Cancelled,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum OfferMode {
    #[default]
    Open,
    Exclusive,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum MilestoneStatus {
    #[default]
    Pending,
    Submitted,
    RevisionRequested,
    Approved,
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
