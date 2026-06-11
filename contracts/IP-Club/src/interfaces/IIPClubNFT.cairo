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
}
