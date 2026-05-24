#[starknet::interface]
pub trait ISignatureAccountAdmin<TContractState> {
    fn set_expected_hash(ref self: TContractState, expected_hash: felt252);
    fn set_valid(ref self: TContractState, valid: bool);
}

#[starknet::contract]
mod SignatureAccount {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, VALIDATED, get_caller_address};
    use super::ISignatureAccountAdmin;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        expected_hash: felt252,
        valid: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, expected_hash: felt252) {
        self.owner.write(owner);
        self.expected_hash.write(expected_hash);
        self.valid.write(true);
    }

    #[abi(embed_v0)]
    impl SignatureAccountAdminImpl of ISignatureAccountAdmin<ContractState> {
        fn set_expected_hash(ref self: ContractState, expected_hash: felt252) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.expected_hash.write(expected_hash);
        }

        fn set_valid(ref self: ContractState, valid: bool) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.valid.write(valid);
        }
    }

    #[external(v0)]
    fn is_valid_signature(
        self: @ContractState, hash: felt252, signature: Array<felt252>,
    ) -> felt252 {
        assert(self.valid.read(), 'Mock invalid signature');
        assert(hash == self.expected_hash.read(), 'Unexpected hash');
        assert(signature.len() > 0, 'Missing signature');
        VALIDATED
    }
}
