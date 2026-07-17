use starknet::{ClassHash, ContractAddress};
use crate::types::{Contribution, ContributionType};

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-colab-collection")
pub const IIP_COLAB_COLLECTION_ID: felt252 =
    0x3c588807d244faed9fe997f1b4af0df7b35b3390a833fedcaf4f9c44adb3408;

// starknet_keccak("mediolano.ip-colab-collection-factory")
pub const IIP_COLAB_COLLECTION_FACTORY_ID: felt252 =
    0x35c3bb8e927cb0ab50c70e5c6c99357be5ff4dc05ee574a2620063f08cd555d;

#[starknet::interface]
pub trait IIPCollabCollection<TContractState> {
    /// Owner-only. Opens a contribution type (a round, a brief, a category)
    /// and assigns the next sequential type ID. `submission_deadline` is
    /// optional — unset means submissions stay open indefinitely.
    fn create_contribution_type(
        ref self: TContractState,
        max_supply: u256,
        submission_deadline: Option<u64>,
        metadata_uri: ByteArray,
    ) -> u256;

    /// Anyone. Submits a piece to a type while submissions are open. The
    /// deadline gates submission only — review and minting of already
    /// submitted work stay open. `royalty_bps` is the contributor's own
    /// royalty on their piece, immutable once submitted.
    fn submit_contribution(
        ref self: TContractState, type_id: u256, token_uri: ByteArray, royalty_bps: u16,
    ) -> u256;

    /// Owner or verifier. Approves a pending contribution; approval consumes
    /// the type's supply.
    fn approve_contribution(ref self: TContractState, contribution_id: u256);

    /// Owner or verifier. Rejects a pending contribution. The contributor
    /// can submit again.
    fn reject_contribution(ref self: TContractState, contribution_id: u256);

    /// Contributor only, approved contributions only. Mints the next
    /// sequential token id to the contributor and records the on-chain
    /// registration timestamp.
    fn mint_contribution(ref self: TContractState, contribution_id: u256) -> u256;

    /// Token owner only. Permanently freezes the token in place — transfers
    /// are blocked from then on.
    fn archive(ref self: TContractState, token_id: u256);

    /// Owner-only verifier management. The owner is always a verifier.
    fn add_verifier(ref self: TContractState, verifier: ContractAddress);
    fn remove_verifier(ref self: TContractState, verifier: ContractAddress);
    fn is_verifier(self: @TContractState, verifier: ContractAddress) -> bool;

    fn is_archived(self: @TContractState, token_id: u256) -> bool;

    /// Returns the Contribution. Panics if never submitted.
    fn get_contribution(self: @TContractState, contribution_id: u256) -> Contribution;

    /// Returns the ContributionType. Panics if never created.
    fn get_contribution_type(self: @TContractState, type_id: u256) -> ContributionType;

    /// Sequential counters (ids start at 1).
    fn contribution_count(self: @TContractState) -> u256;
    fn type_count(self: @TContractState) -> u256;

    /// The contribution a minted token came from. Panics if the token does
    /// not exist.
    fn get_token_contribution(self: @TContractState, token_id: u256) -> u256;

    /// On-chain registration timestamp, set at mint. Panics if the token
    /// does not exist.
    fn token_registered_at(self: @TContractState, token_id: u256) -> u64;

    /// Collection-level metadata URI, set once at deploy.
    fn base_uri(self: @TContractState) -> ByteArray;

    /// EIP-2981. Receiver = the token's contributor; amount =
    /// sale_price * bps / 10000.
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);

    fn version(self: @TContractState) -> ByteArray;
}

#[starknet::interface]
pub trait IIPCollabCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    /// Deploys a new collection. The caller becomes its owner. `base_uri` is the
    /// collection-level metadata URI, embedded on-chain in the deploy transaction.
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> ContractAddress;
}
