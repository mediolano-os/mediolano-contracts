use starknet::{ClassHash, ContractAddress};
use crate::types::EventRecord;

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-ticket-collection.v3") — verify before mainnet deploy.
pub const IIP_TICKET_COLLECTION_ID: felt252 =
    0x2f5a9e3b8c1d6047a98f2e3c5b7d1089f4a2e6c8b0d3f5a7e9c1b4d6f8a0e2;

// Protocol discovery ID for factory.
// starknet_keccak("mediolano.ip-ticket-collection-factory.v3") — verify before mainnet deploy.
pub const IIP_TICKET_COLLECTION_FACTORY_ID: felt252 =
    0x1a8f3c5e7b9d2046f8a0c2e4b6d8f0a2c4e6b8d0f2a4c6e8b0d2f4a6c8e0b2;

#[starknet::interface]
pub trait IIPTicketCollection<TContractState> {
    /// Owner-only. Registers a new event, assigns next token ID.
    fn create_event(
        ref self: TContractState,
        max_supply: u256,
        start_time: Option<u64>,
        end_time: Option<u64>,
        royalty_bps: u16,
        metadata_uri: ByteArray,
    ) -> u256;

    /// Owner-only. Mints `amount` of `token_id` to `to`. Enforces max_supply and time window.
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256, amount: u256);

    /// Owner-only. Pauses or resumes minting for one event.
    fn pause_event(ref self: TContractState, token_id: u256, active: bool);

    /// Read. True iff holder has balance > 0 AND current time is within the event window.
    fn is_valid(self: @TContractState, token_id: u256, holder: ContractAddress) -> bool;

    /// Returns the EventRecord for `token_id`. Panics if not created.
    fn get_event(self: @TContractState, token_id: u256) -> EventRecord;

    /// EIP-2981 royalty info. Receiver = event creator, amount = sale_price * bps / 10000.
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);

    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);

    fn version(self: @TContractState) -> ByteArray;
}

#[starknet::interface]
pub trait IIPTicketCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray,
    ) -> ContractAddress;
}
