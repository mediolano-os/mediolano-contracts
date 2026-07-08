use starknet::ContractAddress;

#[starknet::interface]
pub trait IIPCoin<TContractState> {
    fn deploy_ip_coin(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        supply: u256,
        decimals: u32,
        metadata_uri: ByteArray,
        post_id: u256,
    ) -> ContractAddress;
    fn get_ip_coin(self: @TContractState, post_id: u256) -> ContractAddress;
    fn get_post(self: @TContractState, ip_coin_address: ContractAddress) -> u256;
}
