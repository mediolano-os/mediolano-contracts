// IPClubFactory — ownerless, immutable deploy point for IPClubCollection
// contracts. Anyone can deploy a new club; the caller becomes its owner.
// Mirrors IPTicketCollectionFactory.

#[starknet::contract]
pub mod IPClubFactory {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::interface::{IIPClubFactory, IIP_CLUB_FACTORY_ID};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// Class hash of IPClubCollection. Fixed at deploy time.
        ip_club_collection_class_hash: ClassHash,
        /// Monotonically incrementing nonce for unique deploy salts.
        deploy_nonce: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        ClubDeployed: ClubDeployed,
    }

    /// Emitted each time a new IPClubCollection is deployed via `deploy_club`.
    #[derive(Drop, starknet::Event)]
    pub struct ClubDeployed {
        #[key]
        pub collection_address: ContractAddress,
        #[key]
        pub owner: ContractAddress,
        pub name: ByteArray,
        pub symbol: ByteArray,
    }

    #[constructor]
    fn constructor(ref self: ContractState, collection_class_hash: ClassHash) {
        assert(collection_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.src5.register_interface(IIP_CLUB_FACTORY_ID);
        self.ip_club_collection_class_hash.write(collection_class_hash);
    }

    #[abi(embed_v0)]
    impl IPClubFactoryImpl of IIPClubFactory<ContractState> {
        fn collection_class_hash(self: @ContractState) -> ClassHash {
            self.ip_club_collection_class_hash.read()
        }

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }

        fn deploy_club(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            max_supply: u256,
            entry_fee: u256,
            payment_token: Option<ContractAddress>,
            royalty_bps: u256,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name must not be empty');
            assert(symbol.len() > 0, 'Symbol must not be empty');

            let caller = get_caller_address();

            let nonce = self.deploy_nonce.read();
            let salt = PoseidonTrait::new().update_with(caller).update_with(nonce).finalize();
            self.deploy_nonce.write(nonce + 1);

            // Constructor: (name, symbol, base_uri, max_supply, entry_fee,
            //               payment_token, royalty_bps, owner)
            let mut calldata: Array<felt252> = array![];
            name.serialize(ref calldata);
            symbol.serialize(ref calldata);
            base_uri.serialize(ref calldata);
            max_supply.serialize(ref calldata);
            entry_fee.serialize(ref calldata);
            payment_token.serialize(ref calldata);
            royalty_bps.serialize(ref calldata);
            caller.serialize(ref calldata);

            let (collection_address, _) = deploy_syscall(
                self.ip_club_collection_class_hash.read(), salt, calldata.span(), false,
            )
                .unwrap_syscall();

            self.emit(ClubDeployed { collection_address, owner: caller, name, symbol });

            collection_address
        }
    }
}
