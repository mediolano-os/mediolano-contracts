use starknet::ContractAddress;

/// One entry per `create_syndication` call, stored at `syndications[token_id]`.
/// `target_amount` is zero iff the syndication was never created — used as the
/// existence check (`create_syndication` rejects a zero target).
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Syndication {
    pub target_amount: u256,
    pub total_raised: u256,
    pub payment_token: ContractAddress,
    pub whitelist: bool,
    pub status: Status,
    pub proceeds_claimed: bool,
    pub royalty_bps: u16,
    pub metadata_uri: ByteArray,
}

/// A participant's escrow position in one syndication, stored at
/// `positions[(token_id, participant)]`. `deposited` is the live escrowed
/// balance — deposits raise it, withdrawals and refunds lower it, and after
/// completion it is the exact number of shares the participant can mint.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Position {
    pub deposited: u256,
    pub shares_minted: bool,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum Status {
    #[default]
    Active,
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
