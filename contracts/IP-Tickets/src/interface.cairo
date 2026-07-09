use starknet::{ClassHash, ContractAddress};
use crate::types::{TicketCollection, TicketData};

// Protocol discovery ID registered via SRC5. Bumped to .v2 with the
// breaking ABI change (mint_ticket recipient param, total_supply →
// total_minted): immutable v1 deployments keep registering the .v1 ID,
// so consumers can tell the two ABIs apart via SRC5 alone.
// Derivation: starknet_keccak("mediolano.ip-ticket-collection.v2").
pub const IIP_TICKET_COLLECTION_ID: felt252 =
    0x1ef1511f39449df0a0c686da9bc0759e7c75ad8eb0da68c53ac14093a6ea757;

// Marks a collection whose metadata JSON carries the Mediolano programmable
// license trait schema (License, Commercial Use, Derivatives, Attribution,
// Territory, AI Policy, Standard, Registration). Discovery only — the license
// remains data in metadata, not contract-enforced state.
// Derivation: starknet_keccak("mediolano.licensed-collection.v1").
pub const ILICENSED_COLLECTION_ID: felt252 =
    0x3aaa3269207d0d03ca389e2a76f46c207ff513c2503ba463805d76ce52d75b8;

#[starknet::interface]
pub trait IIPTicketCollection<TContractState> {
    fn create_ticket_collection(
        ref self: TContractState,
        price: u256,
        max_supply: u256,
        expiration: u64,
        royalty_bps: u256,
        payment_token: Option<ContractAddress>,
        metadata_uri: ByteArray,
    ) -> u256;

    fn set_collection_active(ref self: TContractState, collection_id: u256, active: bool);

    fn mint_ticket(
        ref self: TContractState, collection_id: u256, recipient: ContractAddress,
    ) -> u256;

    fn redeem_ticket(ref self: TContractState, token_id: u256);

    fn has_valid_ticket(self: @TContractState, user: ContractAddress, collection_id: u256) -> bool;

    fn get_ticket_collection(self: @TContractState, collection_id: u256) -> TicketCollection;

    fn get_ticket_data(self: @TContractState, token_id: u256) -> TicketData;

    fn get_ticket_collection_id(self: @TContractState, token_id: u256) -> u256;

    fn get_active_ticket_balance(
        self: @TContractState, user: ContractAddress, collection_id: u256,
    ) -> u256;

    fn get_last_collection_id(self: @TContractState) -> u256;

    fn total_minted(self: @TContractState) -> u256;

    fn version(self: @TContractState) -> ByteArray;

    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);

    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
}

// Protocol discovery ID registered via SRC5 on the factory.
// Derivation: starknet_keccak("mediolano.ip-ticket-collection-factory.v1").
pub const IIP_TICKET_COLLECTION_FACTORY_ID: felt252 =
    0x27717c17c18e684321a4326345c6ee264d3a91a7b6f1b54e02de0332fb76f58;

#[starknet::interface]
pub trait IIPTicketCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    fn deploy_ticket_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray,
    ) -> ContractAddress;
}
