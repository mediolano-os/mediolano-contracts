use starknet::{ClassHash, ContractAddress};
use crate::types::Membership;

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-club-collection")
pub const IIP_CLUB_COLLECTION_ID: felt252 =
    0x2cee01ae4b57170456f53b518718e8c53e8b9a91aa41c555d0e8c31f217b00e;

// starknet_keccak("mediolano.ip-club-collection-factory")
pub const IIP_CLUB_COLLECTION_FACTORY_ID: felt252 =
    0x14cfd8023b9e536938a3b7bf877bfa5a7f1a993b3e8362b95e671db9f17f634;

#[starknet::interface]
pub trait IIPClubCollection<TContractState> {
    /// Owner-only. Registers a new membership tier, assigns the next
    /// sequential token ID.
    fn create_membership(
        ref self: TContractState,
        max_supply: u256,
        start_time: Option<u64>,
        end_time: Option<u64>,
        royalty_bps: u16,
        metadata_uri: ByteArray,
    ) -> u256;

    /// Owner-only. Mints `amount` of `token_id` to `to`. Enforces max_supply.
    /// The validity window does not gate minting — a tier may be minted and
    /// sold before its window opens.
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256, amount: u256);

    /// True iff `holder` holds any tier whose validity window contains the
    /// current time (a tier with no window is always valid).
    fn is_member(self: @TContractState, holder: ContractAddress) -> bool;

    /// True iff `holder` holds `token_id` and the current time is inside its
    /// validity window.
    fn is_member_of(self: @TContractState, token_id: u256, holder: ContractAddress) -> bool;

    /// Returns the Membership for `token_id`. Panics if never created.
    fn get_membership(self: @TContractState, token_id: u256) -> Membership;

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
pub trait IIPClubCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    /// Deploys a new club collection. The caller becomes its owner. `base_uri`
    /// is the collection-level metadata URI, embedded on-chain in the deploy
    /// transaction.
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> ContractAddress;
}
