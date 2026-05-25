use starknet::ContractAddress;

#[starknet::interface]
pub trait IIPNft<ContractState> {
    fn mint(
        ref self: ContractState,
        recipient: ContractAddress,
        token_id: u256,
        token_uri: ByteArray,
        creator: ContractAddress,
    );

    fn archive(ref self: ContractState, token_id: u256);

    fn is_archived(self: @ContractState, token_id: u256) -> bool;

    fn get_collection_id(self: @ContractState) -> u256;

    fn get_registry(self: @ContractState) -> ContractAddress;

    fn base_uri(self: @ContractState) -> ByteArray;

    fn all_tokens_of_owner(self: @ContractState, owner: ContractAddress) -> Span<u256>;

    fn token_exists(self: @ContractState, token_id: u256) -> bool;

    fn get_full_token_data(
        self: @ContractState, token_id: u256,
    ) -> (ContractAddress, ByteArray, ContractAddress, u64);

    fn get_token_creator(self: @ContractState, token_id: u256) -> ContractAddress;

    fn get_token_registered_at(self: @ContractState, token_id: u256) -> u64;
}
