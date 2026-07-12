use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
pub trait IGenerativeArtFactory<TContractState> {
    fn deploy_collection(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        script_hash: felt252,
        script_uri: ByteArray,
        max_supply: u256,
        royalty_receiver: ContractAddress,
        royalty_bps: u16,
    ) -> ContractAddress;
    fn collection_class_hash(self: @TContractState) -> ClassHash;
}
