pub mod Errors {
    pub const PRICE_IS_ZERO: felt252 = 'Price is zero';
    pub const INVALID_PAYMENT_TOKEN: felt252 = 'Invalid payment token';
    pub const INVALID_ASSET: felt252 = 'Invalid asset';
    pub const INVALID_URI: felt252 = 'URI must be ipfs:// or ar://';
    pub const INVALID_HASH: felt252 = 'Hash is zero';
    pub const NEGOTIATION_NOT_FOUND: felt252 = 'Negotiation not found';
    pub const ACTIVE_LISTING_EXISTS: felt252 = 'Active listing exists';
    pub const NOT_SELLER: felt252 = 'Not seller';
    pub const NOT_BUYER: felt252 = 'Not buyer';
    pub const INVALID_BUYER: felt252 = 'Invalid buyer';
    pub const INVALID_STATUS: felt252 = 'Invalid status';
    pub const DEADLINE_EXPIRED: felt252 = 'Deadline expired';
    pub const PAYMENT_FAILED: felt252 = 'Payment failed';
    pub const NOTHING_TO_CLAIM: felt252 = 'Nothing to claim';
    pub const NON_TRANSFERABLE: felt252 = 'Listing asset non-transferable';
    pub const REENTRANT_CALL: felt252 = 'Reentrant call';
}
