#[starknet::interface]
pub trait IGenerativeArt<TContractState> {
    /// Poseidon hash of the generative script — the immutable tamper-proof anchor.
    fn script_hash(self: @TContractState) -> felt252;
    /// Permanent-storage pointer (Arweave/IPFS) to the script source.
    fn script_uri(self: @TContractState) -> ByteArray;
    /// Immutable hard cap on the number of tokens.
    fn max_supply(self: @TContractState) -> u256;
    /// Number of tokens minted so far.
    fn total_minted(self: @TContractState) -> u256;
    /// Deterministic seed bound at the token's mint.
    fn token_seed(self: @TContractState, token_id: u256) -> felt252;
    /// Permissionless collector mint. Returns the new token id.
    fn mint(ref self: TContractState) -> u256;
}
