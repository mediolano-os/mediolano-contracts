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
    use crate::interface::{IIPTicketCollectionDispatcher, IIPTicketCollectionDispatcherTrait};
    use crate::mock::reentrant_payment_token::IReentrantPaymentToken;

    #[storage]
    struct Storage {
        ticket_collection: ContractAddress,
        collection_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(
        ref self: ContractState, ticket_collection: ContractAddress, collection_id: u256,
    ) {
        self.ticket_collection.write(ticket_collection);
        self.collection_id.write(collection_id);
    }

    #[abi(embed_v0)]
    impl ReentrantPaymentTokenImpl of IReentrantPaymentToken<ContractState> {
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let ticket_collection = IIPTicketCollectionDispatcher {
                contract_address: self.ticket_collection.read(),
            };
            ticket_collection.mint_ticket(self.collection_id.read(), sender);
            true
        }
    }
}
