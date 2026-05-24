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
    use crate::interfaces::IIPClub::{IIPClubDispatcher, IIPClubDispatcherTrait};
    use crate::mocks::ReentrantPaymentToken::IReentrantPaymentToken;

    #[storage]
    struct Storage {
        ip_club: ContractAddress,
        club_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, ip_club: ContractAddress, club_id: u256) {
        self.ip_club.write(ip_club);
        self.club_id.write(club_id);
    }

    #[abi(embed_v0)]
    impl ReentrantPaymentTokenImpl of IReentrantPaymentToken<ContractState> {
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let ip_club = IIPClubDispatcher { contract_address: self.ip_club.read() };
            ip_club.join_club(self.club_id.read());
            true
        }
    }
}
