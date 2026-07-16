use starknet::{ClassHash, ContractAddress};
use crate::types::Ticket;

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-ticket-collection")
pub const IIP_TICKET_COLLECTION_ID: felt252 =
    0x3fa3bcc658b1652be19ff630d5e6f577335cf31baa2c520c0dd8694a64f5711;

// starknet_keccak("mediolano.ip-ticket-collection-factory")
pub const IIP_TICKET_COLLECTION_FACTORY_ID: felt252 =
    0x6d61010de9cb760487aa7a674953e17e9bcb4e1e5a1db1cc54177420f14a22;

#[starknet::interface]
pub trait IIPTicketCollection<TContractState> {
    /// Owner-only. Registers a new ticket, assigns the next sequential token ID.
    fn create_ticket(
        ref self: TContractState,
        max_supply: u256,
        start_time: Option<u64>,
        end_time: Option<u64>,
        royalty_bps: u16,
        metadata_uri: ByteArray,
    ) -> u256;

    /// Owner-only. Mints `amount` of `token_id` to `to`. Enforces max_supply.
    /// The validity window does not gate minting — a ticket may be minted and
    /// sold before its window opens.
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256, amount: u256);

    /// True iff `holder` has balance > 0 and the current time is inside the
    /// ticket's validity window.
    fn is_valid(self: @TContractState, token_id: u256, holder: ContractAddress) -> bool;

    /// Returns the Ticket for `token_id`. Panics if never created.
    fn get_ticket(self: @TContractState, token_id: u256) -> Ticket;

    /// Number of tickets created so far (ids are sequential from 1).
    fn ticket_count(self: @TContractState) -> u256;

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
pub trait IIPTicketCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    /// Deploys a new collection. The caller becomes its owner. `base_uri` is the
    /// collection-level metadata URI, embedded on-chain in the deploy transaction.
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> ContractAddress;
}
