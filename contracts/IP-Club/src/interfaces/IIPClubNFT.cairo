use starknet::ContractAddress;

pub const IIP_CLUB_NFT_ID: felt252 =
    0x02ad826916536b2ddefafc363444005820a6fc6fd5eb34b4f4131b02a8a3cdf4;

#[starknet::interface]
pub trait IIPClubNFT<TContractState> {
    // Mintable functions
    fn mint(ref self: TContractState, recipient: ContractAddress);

    // Get functions
    fn has_nft(self: @TContractState, user: ContractAddress) -> bool;
    fn get_nft_creator(self: @TContractState) -> ContractAddress;
    fn get_ip_club_manager(self: @TContractState) -> ContractAddress;
    fn get_associated_club_id(self: @TContractState) -> u256;
    fn get_last_minted_id(self: @TContractState) -> u256;
}
