use starknet::ContractAddress;

/// One entry per `create_contribution_type` call, stored at
/// `types[type_id]`. `max_supply` is zero iff the type was never created —
/// used as the existence check (`create_contribution_type` rejects a zero
/// max_supply). `max_supply` caps approvals; `minted_count` can only trail
/// `approved_count`.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct ContributionType {
    pub max_supply: u256,
    pub approved_count: u256,
    pub minted_count: u256,
    pub submission_deadline: Option<u64>,
    pub metadata_uri: ByteArray,
}

/// One entry per `submit_contribution` call, stored at
/// `contributions[contribution_id]`. `contributor` is zero iff the
/// contribution was never submitted. `token_id` is set when the approved
/// contributor mints.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Contribution {
    pub contributor: ContractAddress,
    pub type_id: u256,
    pub token_uri: ByteArray,
    pub royalty_bps: u16,
    pub status: ContributionStatus,
    pub token_id: u256,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum ContributionStatus {
    #[default]
    Pending,
    Approved,
    Rejected,
    Minted,
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
