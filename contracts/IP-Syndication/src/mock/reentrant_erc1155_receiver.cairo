use starknet::ContractAddress;

#[starknet::interface]
pub trait IReentrantERC1155ReceiverConfig<TContractState> {
    fn configure_reentrant_mint(ref self: TContractState, target: ContractAddress, ip_id: u256);
}

#[starknet::contract]
mod ReentrantERC1155Receiver {
    use core::num::traits::Zero;
    use ip_syndication::interface::{IIPSyndicationDispatcher, IIPSyndicationDispatcherTrait};
    use ip_syndication::mock::reentrant_erc1155_receiver::IReentrantERC1155ReceiverConfig;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::interface::{IERC1155Receiver, IERC1155_RECEIVER_ID};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        target: ContractAddress,
        ip_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.src5.register_interface(IERC1155_RECEIVER_ID);
    }

    #[abi(embed_v0)]
    impl ReceiverImpl of IERC1155Receiver<ContractState> {
        fn on_erc1155_received(
            self: @ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>,
        ) -> felt252 {
            let target = self.target.read();
            if !target.is_zero() {
                IIPSyndicationDispatcher { contract_address: target }.mint_asset(self.ip_id.read());
            }
            IERC1155_RECEIVER_ID
        }

        fn on_erc1155_batch_received(
            self: @ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>,
        ) -> felt252 {
            IERC1155_RECEIVER_ID
        }
    }

    #[abi(embed_v0)]
    impl ConfigImpl of IReentrantERC1155ReceiverConfig<ContractState> {
        fn configure_reentrant_mint(ref self: ContractState, target: ContractAddress, ip_id: u256) {
            self.target.write(target);
            self.ip_id.write(ip_id);
        }
    }
}
