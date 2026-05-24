pub mod Errors {
    pub const TARGET_IS_ZERO: felt252 = 'Target is zero';
    pub const AMOUNT_IS_ZERO: felt252 = 'Amount is zero';
    pub const INVALID_PAYMENT_TOKEN: felt252 = 'Invalid payment token';
    pub const INVALID_RECIPIENT: felt252 = 'Invalid recipient';
    pub const INVALID_URI: felt252 = 'URI must be ipfs:// or ar://';
    pub const IP_NOT_FOUND: felt252 = 'IP does not exist';
    pub const NOT_IP_OWNER: felt252 = 'Not IP owner';
    pub const SYNDICATION_NOT_PENDING: felt252 = 'Syndication not pending';
    pub const SYNDICATION_NOT_ACTIVE: felt252 = 'Syndication not active';
    pub const SYNDICATION_NOT_COMPLETED: felt252 = 'Syndication not completed';
    pub const SYNDICATION_NOT_CANCELLED: felt252 = 'Syndication not cancelled';
    pub const COMPLETED_OR_CANCELLED: felt252 = 'Completed or cancelled';
    pub const ADDRESS_NOT_WHITELISTED: felt252 = 'Address not whitelisted';
    pub const NOT_IN_WHITELIST_MODE: felt252 = 'Not in whitelist mode';
    pub const FUNDRAISING_COMPLETED: felt252 = 'Fundraising completed';
    pub const INSUFFICIENT_BALANCE: felt252 = 'Insufficient balance';
    pub const PAYMENT_FAILED: felt252 = 'Payment failed';
    pub const REFUND_FAILED: felt252 = 'Refund failed';
    pub const PROCEEDS_FAILED: felt252 = 'Proceeds transfer failed';
    pub const NO_REFUND_AVAILABLE: felt252 = 'No refund available';
    pub const NON_PARTICIPANT: felt252 = 'Not participant';
    pub const ALREADY_MINTED: felt252 = 'Already minted';
    pub const PROCEEDS_ALREADY_CLAIMED: felt252 = 'Proceeds already claimed';
    pub const REENTRANT_CALL: felt252 = 'Reentrant call';
}
