// DESIGN: IPTicketCollectionFactory is the single deploy point for all
// IPTicketCollection contracts. Anyone can deploy a new ticket collection —
// the caller becomes its owner and the only address that can create ticket
// collections (event/tier batches) inside it. The factory is fully immutable
// and ownerless: the collection class hash is fixed at deploy time. Mirrors
// IPCollectionFactory (IP-Programmable-ERC1155-Collections).

#[starknet::contract]
pub mod IPTicketCollectionFactory {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::interface::{IIPTicketCollectionFactory, IIP_TICKET_COLLECTION_FACTORY_ID};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// Class hash used to deploy new IPTicketCollection instances.
        /// Immutable — fixed at deploy.
        ip_ticket_collection_class_hash: ClassHash,
        /// Monotonically incrementing nonce for unique deploy salts.
        deploy_nonce: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        CollectionDeployed: CollectionDeployed,
    }

    /// Emitted each time a new IPTicketCollection is deployed via
    /// `deploy_ticket_collection`.
    #[derive(Drop, starknet::Event)]
    pub struct CollectionDeployed {
        #[key]
        pub collection_address: ContractAddress,
        #[key]
        pub owner: ContractAddress,
        pub name: ByteArray,
        pub symbol: ByteArray,
    }

    /// Deploys a new IPTicketCollectionFactory.
    ///
    /// # Arguments
    /// * `collection_class_hash` - Class hash of the IPTicketCollection
    ///   contract to deploy. Fixed forever; the factory is ownerless and
    ///   immutable.
    #[constructor]
    fn constructor(ref self: ContractState, collection_class_hash: ClassHash) {
        assert(collection_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.src5.register_interface(IIP_TICKET_COLLECTION_FACTORY_ID);
        self.ip_ticket_collection_class_hash.write(collection_class_hash);
        // deploy_nonce defaults to 0 — no explicit write needed
    }

    #[abi(embed_v0)]
    impl IPTicketCollectionFactoryImpl of IIPTicketCollectionFactory<ContractState> {
        fn collection_class_hash(self: @ContractState) -> ClassHash {
            self.ip_ticket_collection_class_hash.read()
        }

        fn version(self: @ContractState) -> ByteArray {
            "2.0.0"
        }

        fn deploy_ticket_collection(
            ref self: ContractState, name: ByteArray, symbol: ByteArray,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name must not be empty');
            assert(symbol.len() > 0, 'Symbol must not be empty');

            let caller = get_caller_address();

            // Derive a unique salt from caller + nonce using Poseidon.
            let nonce = self.deploy_nonce.read();
            let salt = PoseidonTrait::new().update_with(caller).update_with(nonce).finalize();
            self.deploy_nonce.write(nonce + 1);

            // Serialize constructor calldata: (name, symbol, owner).
            let mut calldata: Array<felt252> = array![];
            name.serialize(ref calldata);
            symbol.serialize(ref calldata);
            caller.serialize(ref calldata);

            let (collection_address, _) = deploy_syscall(
                self.ip_ticket_collection_class_hash.read(), salt, calldata.span(), false,
            )
                .unwrap_syscall();

            self.emit(CollectionDeployed { collection_address, owner: caller, name, symbol });

            collection_address
        }
    }
}
