use starknet::ContractAddress;

// A club exists iff `creator != 0` (create_club rejects a zero caller).
// `open` gates new joins only — never existing memberships or leaving.
// Name, symbol, and metadata live on the club's NFT contract (the asset is
// the source of truth); the registry record holds only what it enforces.
#[derive(Debug, Drop, Serde, starknet::Store, Clone)]
pub struct ClubRecord {
    pub creator: ContractAddress,
    pub club_nft: ContractAddress,
    pub open: bool,
    pub num_members: u32,
    pub max_members: Option<u32>,
    pub entry_fee: Option<u256>,
    pub payment_token: Option<ContractAddress>,
    /// Seconds from a card's mint until it becomes transferable.
    /// None = permanently non-transferable. Immutable per club.
    pub transfer_lock: Option<u64>,
    /// EIP-2981 royalty on secondary sales of vested cards, in basis
    /// points (0..=10000). Recipient is the club creator. Immutable.
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
