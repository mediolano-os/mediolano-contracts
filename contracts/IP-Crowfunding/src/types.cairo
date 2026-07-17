use starknet::ContractAddress;

/// One entry per `create_campaign` call, stored at `campaigns[token_id]`.
/// `goal_amount` is zero iff the campaign was never created — used as the
/// existence check (`create_campaign` rejects a zero goal). Success and
/// failure are never stored: they derive from `end_time` and
/// `total_raised >= goal_amount`.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Campaign {
    pub goal_amount: u256,
    pub total_raised: u256,
    pub payment_token: ContractAddress,
    pub end_time: u64,
    pub cancelled: bool,
    pub proceeds_claimed: bool,
    pub metadata_uri: ByteArray,
}

/// A backer's escrow position in one campaign, stored at
/// `positions[(token_id, backer)]`. `contributed` is the live balance —
/// contributions raise it, withdrawals and refunds zero or lower it, and
/// after success it is the exact receipt balance the backer can mint.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Position {
    pub contributed: u256,
    pub receipt_minted: bool,
}

/// Derived, never stored.
#[derive(Drop, Copy, Serde, PartialEq)]
pub enum CampaignStatus {
    Active,
    Succeeded,
    Failed,
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
