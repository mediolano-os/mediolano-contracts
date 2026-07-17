use starknet::ContractAddress;

/// One entry per `create_commission` call, stored at
/// `commissions[commission_id]`. `commissioner` is zero iff the commission
/// was never created. The full amount is escrowed in the creation
/// transaction; `creator_claim` and `commissioner_refund` are the two
/// parties' unclaimed balances — earned milestones and refundable escrow
/// respectively.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Commission {
    pub commissioner: ContractAddress,
    pub invited_creator: ContractAddress,
    pub creator: ContractAddress,
    pub payment_token: ContractAddress,
    pub total_amount: u256,
    pub released_amount: u256,
    pub milestone_count: u32,
    pub approved_milestone_count: u32,
    pub revisions_allowed: u32,
    pub deadline: u64,
    pub review_period: u64,
    pub status: CommissionStatus,
    pub brief_uri: ByteArray,
    pub creator_claim: u256,
    pub commissioner_refund: u256,
}

/// One entry per milestone, stored at `milestones[(commission_id, index)]`.
/// `amount` is zero iff the milestone was never created (`create_commission`
/// rejects zero milestone amounts). `submitted_at` starts the commissioner's
/// review window.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Milestone {
    pub amount: u256,
    pub status: MilestoneStatus,
    pub revision_count: u32,
    pub submitted_at: u64,
    pub deliverable_uri: ByteArray,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum CommissionStatus {
    #[default]
    Open,
    InProgress,
    Completed,
    Cancelled,
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
