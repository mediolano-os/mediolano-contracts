// DESIGN: IPCrowdfundingCollectionFactory is the single deploy point for all
// IPCrowdfundingCollection contracts. Anyone can deploy a new crowdfunding
// collection — the caller becomes its owner and the only address that can
// create and manage campaigns inside it. The factory is fully immutable and
// ownerless: the collection class hash is fixed at deploy time. Mirrors
// IPTicketCollectionFactory (IP-Tickets).

#[starknet::contract]
pub mod IPCrowdfundingCollectionFactory {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::interface::{
        IIPCrowdfundingCollectionFactory, IIP_CROWDFUNDING_COLLECTION_FACTORY_ID,
    };

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// Class hash used to deploy new IPCrowdfundingCollection instances.
        /// Immutable — fixed at deploy.
        collection_class_hash: ClassHash,
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

    /// Emitted each time a new IPCrowdfundingCollection is deployed via
    /// `deploy_collection`.
    #[derive(Drop, starknet::Event)]
    pub struct CollectionDeployed {
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
        self.src5.register_interface(IIP_CROWDFUNDING_COLLECTION_FACTORY_ID);
        self.collection_class_hash.write(collection_class_hash);
        // deploy_nonce defaults to 0 — no explicit write needed
    }

    #[abi(embed_v0)]
    impl IPCrowdfundingCollectionFactoryImpl of IIPCrowdfundingCollectionFactory<ContractState> {
        fn collection_class_hash(self: @ContractState) -> ClassHash {
            self.collection_class_hash.read()
        }

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }

        fn deploy_collection(
            ref self: ContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name must not be empty');
            assert(symbol.len() > 0, 'Symbol must not be empty');

            let caller = get_caller_address();

            // Derive a unique salt from caller + nonce using Poseidon.
            let nonce = self.deploy_nonce.read();
            let salt = PoseidonTrait::new().update_with(caller).update_with(nonce).finalize();
            self.deploy_nonce.write(nonce + 1);

            // Serialize constructor calldata: (name, symbol, base_uri, owner).
            let mut calldata: Array<felt252> = array![];
            name.serialize(ref calldata);
            symbol.serialize(ref calldata);
            base_uri.serialize(ref calldata);
            caller.serialize(ref calldata);

            let (collection_address, _) = deploy_syscall(
                self.collection_class_hash.read(), salt, calldata.span(), false,
            )
                .unwrap_syscall();

            self.emit(CollectionDeployed { collection_address, owner: caller, name, symbol });

            collection_address
        }
    }
}
