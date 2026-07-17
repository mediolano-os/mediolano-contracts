use starknet::{ClassHash, ContractAddress};
use crate::types::{Position, Syndication};

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-syndication-collection")
pub const IIP_SYNDICATION_COLLECTION_ID: felt252 =
    0x81a59cb693f1445e616eee7c588bb5df2fb944bd06f5596f7eef06f20fadf0;

// starknet_keccak("mediolano.ip-syndication-collection-factory")
pub const IIP_SYNDICATION_COLLECTION_FACTORY_ID: felt252 =
    0x3159ddd4f8ff760d907ca2163bff029ecc782536835307398c21e237106b0e9;

#[starknet::interface]
pub trait IIPSyndicationCollection<TContractState> {
    /// Owner-only. Registers a new syndication campaign and assigns the next
    /// sequential token ID. The campaign is active immediately — a whitelist
    /// campaign accepts no deposits until addresses are listed.
    fn create_syndication(
        ref self: TContractState,
        target_amount: u256,
        payment_token: ContractAddress,
        whitelist: bool,
        royalty_bps: u16,
        metadata_uri: ByteArray,
    ) -> u256;

    /// Deposits up to `amount` of the campaign's payment token, clamped to the
    /// amount still needed. Reaching the target completes the campaign.
    /// Returns the amount actually deposited.
    fn deposit(ref self: TContractState, token_id: u256, amount: u256) -> u256;

    /// Returns `amount` of the caller's deposit while the campaign is active.
    /// No one but the participant controls this exit.
    fn withdraw(ref self: TContractState, token_id: u256, amount: u256);

    /// Owner-only. Cancels an active campaign; deposits become refundable.
    fn cancel_syndication(ref self: TContractState, token_id: u256);

    /// Refunds the caller's full remaining deposit after cancellation.
    fn claim_refund(ref self: TContractState, token_id: u256) -> u256;

    /// Owner-only, once per campaign. Pays out the full raise after completion.
    fn claim_proceeds(ref self: TContractState, token_id: u256) -> u256;

    /// Mints the caller's shares after completion — `deposited` units of the
    /// campaign's token id, once per participant. Shares are ordinary
    /// transferable ERC-1155 balances.
    fn mint_shares(ref self: TContractState, token_id: u256);

    /// Owner-only, whitelist campaigns, while active.
    fn set_whitelist(
        ref self: TContractState, token_id: u256, account: ContractAddress, allowed: bool,
    );

    fn is_whitelisted(self: @TContractState, token_id: u256, account: ContractAddress) -> bool;

    /// Returns the Syndication for `token_id`. Panics if never created.
    fn get_syndication(self: @TContractState, token_id: u256) -> Syndication;

    /// Returns the caller-independent escrow position; all-zero for addresses
    /// that never deposited.
    fn get_position(
        self: @TContractState, token_id: u256, participant: ContractAddress,
    ) -> Position;

    /// Number of syndications created so far (ids are sequential from 1).
    fn syndication_count(self: @TContractState) -> u256;

    /// Collection identity, set once at deploy.
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn base_uri(self: @TContractState) -> ByteArray;

    /// EIP-2981. Receiver = the collection owner; amount = sale_price * bps / 10000.
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);

    fn version(self: @TContractState) -> ByteArray;
}

#[starknet::interface]
pub trait IIPSyndicationCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    /// Deploys a new collection. The caller becomes its owner. `base_uri` is the
    /// collection-level metadata URI, embedded on-chain in the deploy transaction.
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> ContractAddress;
}
