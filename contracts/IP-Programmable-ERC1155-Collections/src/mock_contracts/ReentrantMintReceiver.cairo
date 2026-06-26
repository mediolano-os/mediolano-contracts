/// Malicious ERC-1155 receiver that re-enters `mint_edition` on first receipt.
/// Used to prove the F2 CEI fix: a reentrant mint must NOT reuse a token_id or
/// overwrite the write-once provenance record.
#[starknet::contract]
pub mod ReentrantMintReceiver {
    use ip_programmable_erc1155_collections::interfaces::IIPCollection::{
        IIPCollectionDispatcher, IIPCollectionDispatcherTrait,
    };
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc1155::interface::IERC1155_RECEIVER_ID;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        target: ContractAddress,
        reentered: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // Advertise the receiver interface so mint_with_acceptance_check invokes the hook.
        self.src5.register_interface(IERC1155_RECEIVER_ID);
    }

    #[starknet::interface]
    pub trait IReentrantConfig<TState> {
        fn set_target(ref self: TState, target: ContractAddress);
    }

    #[abi(embed_v0)]
    impl Config of IReentrantConfig<ContractState> {
        fn set_target(ref self: ContractState, target: ContractAddress) {
            self.target.write(target);
        }
    }

    #[starknet::interface]
    pub trait IReceiver<TState> {
        fn on_erc1155_received(
            ref self: TState,
            operator: ContractAddress,
            from: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>,
        ) -> felt252;
        fn on_erc1155_batch_received(
            ref self: TState,
            operator: ContractAddress,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>,
        ) -> felt252;
    }

    #[abi(embed_v0)]
    impl Receiver of IReceiver<ContractState> {
        fn on_erc1155_received(
            ref self: ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>,
        ) -> felt252 {
            if !self.reentered.read() {
                self.reentered.write(true);
                let t = self.target.read();
                // Re-enter: mint a second edition to self during the acceptance callback.
                IIPCollectionDispatcher { contract_address: t }
                    .mint_edition(get_contract_address(), 1, "ipfs://reentrant");
            }
            IERC1155_RECEIVER_ID
        }

        fn on_erc1155_batch_received(
            ref self: ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>,
        ) -> felt252 {
            IERC1155_RECEIVER_ID
        }
    }
}
