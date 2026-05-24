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
    use crate::interface::{IIPTicketServiceDispatcher, IIPTicketServiceDispatcherTrait};
    use crate::mock::reentrant_payment_token::IReentrantPaymentToken;

    #[storage]
    struct Storage {
        ticket_service: ContractAddress,
        series_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, ticket_service: ContractAddress, series_id: u256) {
        self.ticket_service.write(ticket_service);
        self.series_id.write(series_id);
    }

    #[abi(embed_v0)]
    impl ReentrantPaymentTokenImpl of IReentrantPaymentToken<ContractState> {
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let ticket_service = IIPTicketServiceDispatcher {
                contract_address: self.ticket_service.read(),
            };
            ticket_service.mint_ticket(self.series_id.read());
            true
        }
    }
}
