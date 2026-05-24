#[starknet::interface]
pub trait IReentrantPaymentToken<TContractState> {
    fn transfer_from(
        ref self: TContractState,
        sender: starknet::ContractAddress,
        recipient: starknet::ContractAddress,
        amount: u256,
    ) -> bool;
}

#[starknet::contract]
pub mod ReentrantPaymentToken {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::interface::{ISubscriptionDispatcher, ISubscriptionDispatcherTrait};
    use crate::mocks::ReentrantPaymentToken::IReentrantPaymentToken;

    #[storage]
    struct Storage {
        subscription: ContractAddress,
        plan_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, subscription: ContractAddress, plan_id: u256) {
        self.subscription.write(subscription);
        self.plan_id.write(plan_id);
    }

    #[abi(embed_v0)]
    impl ReentrantPaymentTokenImpl of IReentrantPaymentToken<ContractState> {
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let subscription = ISubscriptionDispatcher {
                contract_address: self.subscription.read(),
            };
            subscription.subscribe(self.plan_id.read());
            true
        }
    }
}
