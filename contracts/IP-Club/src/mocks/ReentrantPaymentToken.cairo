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
    use crate::interface::{IIPClubCollectionDispatcher, IIPClubCollectionDispatcherTrait};
    use crate::mocks::ReentrantPaymentToken::IReentrantPaymentToken;

    #[storage]
    struct Storage {
        club_collection: ContractAddress,
        reentry_target: ContractAddress,
        attempted: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(
        ref self: ContractState, club_collection: ContractAddress, reentry_target: ContractAddress,
    ) {
        self.club_collection.write(club_collection);
        self.reentry_target.write(reentry_target);
    }

    #[abi(embed_v0)]
    impl ReentrantPaymentTokenImpl of IReentrantPaymentToken<ContractState> {
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            // Attempt the reentry exactly once, then behave like a normal
            // token — bounds the attack to the realistic single nested call.
            if !self.attempted.read() {
                self.attempted.write(true);
                let collection = IIPClubCollectionDispatcher {
                    contract_address: self.club_collection.read(),
                };
                collection.mint(self.reentry_target.read());
            }
            true
        }
    }
}
