use starknet::ContractAddress;

pub const MAX_TOKEN_URI_LEN: u32 = 2048;

/// All IP provenance fields for a token, returned in a single call.
/// Avoids multiple cross-contract calls for indexers and frontends.
#[derive(Drop, Serde)]
pub struct TokenData {
    pub token_id: u256,
    pub metadata_uri: ByteArray,
    /// Address that first minted this token type — immutable Berne Convention authorship record.
    pub original_creator: ContractAddress,
    /// Block timestamp at first mint — immutable proof of registration date.
    pub registered_at: u64,
}
