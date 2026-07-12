use starknet::ContractAddress;

// Protocol discovery ID registered via SRC5.
// Derivation: starknet_keccak("mediolano.ip-club-nft.v2").
pub const IIP_CLUB_NFT_ID: felt252 =
    0x03ec0e4175cbdefdf73fd14b4d6cfe3ada3a099f0e85bc971bba220a62caffbd;

#[starknet::interface]
pub trait IIPClubNFT<TContractState> {
    // Manager-only (the IPClub registry)
    fn mint(ref self: TContractState, recipient: ContractAddress);
    fn burn(ref self: TContractState, member: ContractAddress, token_id: u256);

    // Get functions
    fn has_nft(self: @TContractState, user: ContractAddress) -> bool;
    fn get_nft_creator(self: @TContractState) -> ContractAddress;
    fn get_ip_club_manager(self: @TContractState) -> ContractAddress;
    fn get_associated_club_id(self: @TContractState) -> u256;
    fn get_last_minted_id(self: @TContractState) -> u256;
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn version(self: @TContractState) -> ByteArray;
}

// Marks a collection whose metadata JSON carries the Mediolano programmable
// license trait schema (License, Commercial Use, Derivatives, Attribution,
// Territory, AI Policy, Standard, Registration). Discovery only — the license
// remains data in metadata, not contract-enforced state.
// Derivation: starknet_keccak("mediolano.licensed-collection.v1").
pub const ILICENSED_COLLECTION_ID: felt252 =
    0x3aaa3269207d0d03ca389e2a76f46c207ff513c2503ba463805d76ce52d75b8;
