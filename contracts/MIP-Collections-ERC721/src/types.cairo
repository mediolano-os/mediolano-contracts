use starknet::ContractAddress;

pub const MAX_NAME_LEN: u32 = 256;
pub const MAX_SYMBOL_LEN: u32 = 64;
pub const MAX_BASE_URI_LEN: u32 = 2048;
pub const MAX_TOKEN_URI_LEN: u32 = 2048;

/// Represents a unique identifier for a token within a collection.
/// The format is `<collection_id:token_id>`, where:
/// - `collection_id`: The unique identifier of the collection.
/// - `:`: A separator indicating the token component.
/// - `token_id`: The unique identifier of the token within the collection.
#[derive(Drop, Copy, Serde)]
pub struct Token {
    /// The unique identifier of the collection.
    pub collection_id: u256,
    /// The unique identifier of the token within the collection.
    pub token_id: u256,
}

/// Trait implementation for Token, providing utility functions.
#[generate_trait]
pub impl TokenImpl of TokenTrait {
    /// Constructs a `Token` from a `ByteArray` formatted as `<collection_id:token_id>`.
    /// Exactly one `:` separator must be present and both segments must be non-empty digits.
    ///
    /// # Arguments
    /// * `data` - A `ByteArray` containing the string representation of the token.
    ///
    /// # Returns
    /// * `Token` - The parsed token with `collection_id` and `token_id` fields.
    fn from_bytes(data: ByteArray) -> Token {
        let colon: u8 = 58; // ':' in ASCII
        let mut col_bytes: ByteArray = "";
        let mut tok_bytes: ByteArray = "";
        let mut colon_count: u32 = 0;

        // Single pass: count colons and split simultaneously
        for i in 0..data.len() {
            let byte = data.at(i).unwrap();
            if byte == colon {
                colon_count += 1;
                continue;
            }
            if colon_count == 0 {
                col_bytes.append_byte(byte);
            } else {
                tok_bytes.append_byte(byte);
            }
        };

        // Validate: exactly one colon, both segments non-empty
        assert(
            colon_count == 1 && col_bytes.len() > 0 && tok_bytes.len() > 0,
            'Invalid token format',
        );

        Token {
            collection_id: bytearray_to_u256(col_bytes),
            token_id: bytearray_to_u256(tok_bytes),
        }
    }
}

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
    /// Transfers routed through IPCollection. Direct ERC-721 transfers are emitted by IPNft only.
    pub total_transfers: u256,
    /// Timestamp of the last mint operation.
    pub last_mint_time: u64,
    /// Timestamp of the last archive operation.
    pub last_archive_time: u64,
    /// Timestamp of the last transfer routed through IPCollection.
    pub last_transfer_time: u64,
}

/// Converts a `ByteArray` containing only ASCII decimal digits to `u256`.
/// Panics with a clear message if any non-digit byte is encountered.
///
/// # Arguments
/// * `bytes` - A `ByteArray` representing a decimal number as a string.
///
/// # Returns
/// * `u256` - The parsed unsigned integer value.
fn bytearray_to_u256(bytes: ByteArray) -> u256 {
    let mut result = 0_u256;
    for i in 0..bytes.len() {
        let byte = bytes.at(i).unwrap();
        // M-04: validate digit range before subtracting to avoid underflow
        assert(byte >= 48_u8 && byte <= 57_u8, 'Invalid digit in token ID');
        let digit = byte - 48;
        result = result * 10_u256 + digit.into();
    };
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bytearray_to_u256_single_digit() {
        let data: ByteArray = "7";
        let result = bytearray_to_u256(data);
        assert(result == 7_u256, 'single_digit_failed');
    }

    #[test]
    fn test_bytearray_to_u256_multiple_digits() {
        let data: ByteArray = "123456";
        let result = bytearray_to_u256(data);
        assert(result == 123456_u256, 'multi_digit_failed');
    }

    #[test]
    #[should_panic(expected: ('Invalid digit in token ID',))]
    fn test_bytearray_to_u256_non_digit_panics() {
        let data: ByteArray = "12a3";
        bytearray_to_u256(data);
    }

    #[test]
    fn test_token_id_from_bytes_basic() {
        let data: ByteArray = "42:314";
        let token_id = TokenTrait::from_bytes(data);
        assert(token_id.collection_id == 42_u256, 'collection_id_parse_failed');
        assert(token_id.token_id == 314_u256, 'token_id_parse_failed');
    }

    #[test]
    fn test_token_id_from_bytes_large_numbers() {
        let data: ByteArray = "98765432109876543210:12345678901234567890";
        let token_id = TokenTrait::from_bytes(data);
        let expected_col: u256 = 98765432109876543210_u256;
        let expected_tok: u256 = 12345678901234567890_u256;
        assert(token_id.collection_id == expected_col, 'large_col_id_failed');
        assert(token_id.token_id == expected_tok, 'large_token_id_failed');
    }

    #[test]
    fn test_token_id_from_bytes_leading_zeros() {
        let data: ByteArray = "00042:0000314";
        let token_id = TokenTrait::from_bytes(data);
        assert(token_id.collection_id == 42_u256, 'leading_zeros_col_failed');
        assert(token_id.token_id == 314_u256, 'leading_zeros_token_failed');
    }

    #[test]
    #[should_panic(expected: ('Invalid token format',))]
    fn test_from_bytes_no_separator_panics() {
        let data: ByteArray = "123";
        TokenTrait::from_bytes(data);
    }

    #[test]
    #[should_panic(expected: ('Invalid token format',))]
    fn test_from_bytes_multiple_colons_panics() {
        let data: ByteArray = "1:2:3";
        TokenTrait::from_bytes(data);
    }

    #[test]
    #[should_panic(expected: ('Invalid token format',))]
    fn test_from_bytes_leading_colon_panics() {
        let data: ByteArray = ":123";
        TokenTrait::from_bytes(data);
    }

    #[test]
    #[should_panic(expected: ('Invalid token format',))]
    fn test_from_bytes_trailing_colon_panics() {
        let data: ByteArray = "123:";
        TokenTrait::from_bytes(data);
    }
}
