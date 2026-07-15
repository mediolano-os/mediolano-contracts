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

/// The on-chain record for an issued sponsorship license — the current
/// holder is the token's ERC-721 owner. Only what a real, atomic mechanism
/// needs stays on-chain: the royalty receiver/rate (EIP-2981, enforced at
/// marketplace trade time) and the token's own metadata URI. Everything
/// else about the deal — the licensed asset, its expiry, its transferable
/// intent — is declarative, carried in that same URI's metadata and in the
/// LicenseMinted event, never contract-enforced state (license terms are
/// data, not an on-chain entity).
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct LicenseRecord {
    /// The IP author who issued the license (royalty recipient on resale).
    pub author: ContractAddress,
    /// EIP-2981 royalty to the author on license resale, basis points.
    pub royalty_bps: u256,
    /// Content-addressed license terms (ipfs:// or ar://) — the token URI.
    pub license_terms_uri: ByteArray,
}

// A sponsor-initiated proposal on an asset with no open offer yet — the
// symmetric counterpart to SponsorshipOffer. Existence: `proposer != 0`.
// `open` gates acceptance/rejection; a withdrawn or accepted proposal is
// closed and cannot be reopened — a new one is proposed instead. The
// proposal binds to the asset, not a person: whoever owns the asset at
// acceptance time is the author who is paid and issues the license.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct SponsorshipProposal {
    pub proposer: ContractAddress,
    pub nft_contract: ContractAddress,
    pub token_id: u256,
    pub amount: u256,
    pub duration: u64,
    /// Acceptance deadline (unix seconds; 0 = no deadline). An expired
    /// proposal can no longer be accepted.
    pub valid_until: u64,
    pub payment_token: ContractAddress,
    pub license_terms_uri: ByteArray,
    pub transferable: bool,
    pub open: bool,
    pub royalty_bps: u256,
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
