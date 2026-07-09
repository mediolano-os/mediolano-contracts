use starknet::ContractAddress;

// An offer exists iff `author != 0` (create_offer rejects a zero caller).
// `open` gates new bids and acceptance — a closed offer is inert and can be
// reopened by its author. Economic terms are immutable; new terms = new offer.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct SponsorshipOffer {
    pub author: ContractAddress,
    pub nft_contract: ContractAddress,
    pub token_id: u256,
    pub min_amount: u256,
    pub duration: u64,
    pub payment_token: ContractAddress,
    pub license_terms_uri: ByteArray,
    pub transferable: bool,
    pub specific_sponsor: Option<ContractAddress>,
    pub open: bool,
    /// EIP-2981 royalty carried onto the issued license, basis points.
    pub royalty_bps: u256,
}

/// The on-chain facts of an issued sponsorship license. Stored per-token on
/// IPSponsorshipLicense; the current holder is the token's ERC-721 owner.
/// The human/machine-readable terms live in the content-addressed
/// license_terms_uri metadata (the token's URI).
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct LicenseData {
    /// The IP author who issued the license (royalty recipient on resale).
    pub author: ContractAddress,
    /// The licensed IP asset.
    pub asset_contract: ContractAddress,
    pub asset_token_id: u256,
    /// License validity end (unix seconds). Expiry is contract-enforced:
    /// an expired license cannot transfer and reads as invalid.
    pub expires_at: u64,
    /// Whether the holder may transfer the license (set from the offer).
    pub transferable: bool,
    /// EIP-2981 royalty to the author on license resale, basis points.
    pub royalty_bps: u256,
    /// Content-addressed license terms (ipfs:// or ar://) — the token URI.
    pub license_terms_uri: ByteArray,
}

pub fn bytearray_starts_with(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let n = needle.len();
    if haystack.len() < n {
        return false;
    }
    let mut i: u32 = 0;
    let mut matches = true;
    while i < n {
        if haystack.at(i).unwrap() != needle.at(i).unwrap() {
            matches = false;
            break;
        }
        i += 1;
    }
    matches
}
