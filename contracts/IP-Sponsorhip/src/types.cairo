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
}

// A license exists iff `author != 0` and is valid while `expires_at >= now`.
// Once issued it cannot be revoked by anyone; it simply runs to expiry.
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct License {
    pub author: ContractAddress,
    pub sponsor: ContractAddress,
    pub nft_contract: ContractAddress,
    pub token_id: u256,
    pub amount_paid: u256,
    pub expires_at: u64,
    pub transferable: bool,
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
