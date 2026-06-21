use starknet::ContractAddress;

pub const MAX_NAME_LEN: u32 = 256;
pub const MAX_SYMBOL_LEN: u32 = 64;
pub const MAX_BASE_URI_LEN: u32 = 2048;
pub const MAX_TOKEN_URI_LEN: u32 = 2048;

/// Maximum royalty in basis points (EIP-2981 denominator is 10_000 = 100%).
/// The contract bound is the protocol-neutral standard maximum; product caps
/// (e.g. the app's 50%) are enforced at the application layer.
pub const MAX_ROYALTY_BPS: u128 = 10_000;

/// Represents a collection of tokens with associated metadata and ownership.
#[derive(Drop, Serde, starknet::Store)]
pub struct Collection {
    /// Name of the collection.
    pub name: ByteArray,
    /// Symbol representing the collection.
    pub symbol: ByteArray,
    /// Informational collection-level URI. Token metadata uses immutable per-token URIs.
    pub base_uri: ByteArray,
    /// Owner of the collection.
    pub owner: ContractAddress,
    /// Address of the associated IP NFT contract.
    pub ip_nft: ContractAddress,
}

/// Represents data associated with a specific token, including immutable legal record fields.
#[derive(Drop, Serde, starknet::Store)]
pub struct TokenData {
    /// The unique identifier of the collection this token belongs to.
    pub collection_id: u256,
    /// The unique identifier of the token within the collection.
    pub token_id: u256,
    /// Current owner of the token.
    pub owner: ContractAddress,
    /// URI pointing to the token's immutable metadata.
    pub metadata_uri: ByteArray,
    /// Original creator/author — immutable Berne Convention authorship record.
    pub original_creator: ContractAddress,
    /// Block timestamp at mint — immutable proof of creation date.
    pub registered_at: u64,
}

/// Stores statistics related to a collection.
#[derive(Drop, Serde, starknet::Store)]
pub struct CollectionStats {
    /// Total number of tokens minted in the collection.
    pub total_minted: u256,
    /// Total number of tokens archived in the collection.
    pub total_archived: u256,
    /// D-3: transfers routed through IPCollection only. Direct ERC-721 transfers are NOT counted
    /// here — reconstruct the full transfer history from IPNft `Transfer` events.
    pub protocol_routed_transfers: u256,
    /// Timestamp of the last mint operation.
    pub last_mint_time: u64,
    /// Timestamp of the last archive operation.
    pub last_archive_time: u64,
    /// Timestamp of the last transfer routed through IPCollection.
    pub last_transfer_time: u64,
}
