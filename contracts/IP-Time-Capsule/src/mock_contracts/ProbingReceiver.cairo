// Test mock: an ERC-721 receiver that reads the capsule record from inside
// the safe_mint callback and reverts if it observes an empty commitment.
// Proves capsule state is written before the external receiver call
// (checks-effects-interactions in mint_capsule).
#[starknet::contract]
pub mod ProbingReceiver {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::interface::IERC721_RECEIVER_ID;
    use starknet::{ContractAddress, get_caller_address};
    use crate::interfaces::{ITimeCapsuleDispatcher, ITimeCapsuleDispatcherTrait};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.src5.register_interface(IERC721_RECEIVER_ID);
    }

    #[starknet::interface]
    pub trait IProbe<TContractState> {
        fn on_erc721_received(
            self: @TContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) -> felt252;
    }

    #[abi(embed_v0)]
    impl ProbeImpl of IProbe<ContractState> {
        fn on_erc721_received(
            self: @ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) -> felt252 {
            let capsules = ITimeCapsuleDispatcher { contract_address: get_caller_address() };
            let observed = capsules.get_capsule_data(token_id);
            assert(observed.content_commitment != 0, 'Capsule empty during mint');
            IERC721_RECEIVER_ID
        }
    }
}
