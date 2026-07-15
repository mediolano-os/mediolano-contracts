use starknet::{ClassHash, ContractAddress};

// starknet_keccak("mediolano.ip-club-collection.v3")
pub const IIP_CLUB_COLLECTION_ID: felt252 =
    0x4b7aad07052a830d89731d485a019e4035c06a1699b800a0e74f732e8158ad;

// starknet_keccak("mediolano.ip-club-factory.v1")
pub const IIP_CLUB_FACTORY_ID: felt252 =
    0x228cd17a62a26bc1bbc9f07724633fa45b6326759b4f6b44e856ade9ff59db1;

#[starknet::interface]
pub trait IIPClubCollection<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress) -> u256;
    fn set_open(ref self: TContractState, open: bool);
    fn base_uri(self: @TContractState) -> ByteArray;
    fn entry_fee(self: @TContractState) -> u256;
    fn payment_token(self: @TContractState) -> Option<ContractAddress>;
    fn max_supply(self: @TContractState) -> u256;
    fn total_minted(self: @TContractState) -> u256;
    fn is_open(self: @TContractState) -> bool;
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn royaltyInfo(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
    fn version(self: @TContractState) -> ByteArray;
}

#[starknet::interface]
pub trait IIPClubFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    fn deploy_club(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        max_supply: u256,
        entry_fee: u256,
        payment_token: Option<ContractAddress>,
        royalty_bps: u256,
    ) -> ContractAddress;
}
