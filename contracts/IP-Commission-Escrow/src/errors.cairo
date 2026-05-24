pub mod Errors {
    pub const AMOUNT_IS_ZERO: felt252 = 'Amount is zero';
    pub const INVALID_PAYMENT_TOKEN: felt252 = 'Invalid payment token';
    pub const INVALID_URI: felt252 = 'URI must be ipfs:// or ar://';
    pub const INVALID_HASH: felt252 = 'Hash is zero';
    pub const INVALID_CREATOR: felt252 = 'Invalid creator';
    pub const INVALID_MILESTONES: felt252 = 'Invalid milestones';
    pub const COMMISSION_NOT_FOUND: felt252 = 'Commission not found';
    pub const NOT_COMMISSIONER: felt252 = 'Not commissioner';
    pub const NOT_CREATOR: felt252 = 'Not creator';
    pub const NOT_INVITED_CREATOR: felt252 = 'Not invited creator';
    pub const INVALID_STATUS: felt252 = 'Invalid status';
    pub const DEADLINE_EXPIRED: felt252 = 'Deadline expired';
    pub const PAYMENT_FAILED: felt252 = 'Payment failed';
    pub const NOTHING_TO_CLAIM: felt252 = 'Nothing to claim';
    pub const MILESTONE_NOT_FOUND: felt252 = 'Milestone not found';
    pub const PREVIOUS_MILESTONE_OPEN: felt252 = 'Previous milestone open';
    pub const REVISION_LIMIT_REACHED: felt252 = 'Revision limit reached';
    pub const NON_TRANSFERABLE: felt252 = 'Offer asset non-transferable';
    pub const REENTRANT_CALL: felt252 = 'Reentrant call';
}
