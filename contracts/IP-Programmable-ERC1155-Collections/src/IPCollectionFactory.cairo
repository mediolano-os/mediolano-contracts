// DESIGN: IPCollectionFactory is the single deploy point for all IPCollection contracts.
// Anyone can deploy a new collection — the caller becomes its owner and IP creator.
// The factory owner can update the class hash for future deployments without affecting
// already-deployed collections (which are immutable standalone contracts).

#[starknet::contract]
pub mod IPCollectionFactory {
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, get_caller_address, SyscallResultTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use core::hash::{HashStateTrait, HashStateExTrait};
    use crate::interfaces::IIPCollectionFactory::IIPCollectionFactory;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        /// Class hash used to deploy new IPCollection instances.
        /// Updatable by factory owner for protocol upgrades; existing collections unaffected.
        ip_collection_class_hash: ClassHash,
        /// Monotonically incrementing nonce for unique deploy salts.
        deploy_nonce: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        CollectionDeployed: CollectionDeployed,
        CollectionClassHashUpdated: CollectionClassHashUpdated,
    }

    /// Emitted each time a new IPCollection is deployed via `deploy_collection`.
    #[derive(Drop, starknet::Event)]
    pub struct CollectionDeployed {
        #[key]
        pub collection_address: ContractAddress,
        #[key]
        pub owner: ContractAddress,
        pub name: ByteArray,
        pub symbol: ByteArray,
        pub base_uri: ByteArray,
    }

    /// Emitted when the factory owner updates the class hash used for future deployments.
    #[derive(Drop, starknet::Event)]
    pub struct CollectionClassHashUpdated {
        pub previous_class_hash: ClassHash,
        pub new_class_hash: ClassHash,
    }

    /// Deploys a new IPCollectionFactory.
    ///
    /// # Arguments
    /// * `owner`                 - Address that owns the factory (can update class hash)
    /// * `collection_class_hash` - Class hash of the IPCollection contract to deploy
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        collection_class_hash: ClassHash,
    ) {
        assert(!owner.is_zero(), 'Owner is zero address');
        assert(collection_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.ownable.initializer(owner);
        self.ip_collection_class_hash.write(collection_class_hash);
        // deploy_nonce defaults to 0 — no explicit write needed
    }

    #[abi(embed_v0)]
    impl IPCollectionFactoryImpl of IIPCollectionFactory<ContractState> {
        fn collection_class_hash(self: @ContractState) -> ClassHash {
            self.ip_collection_class_hash.read()
        }

        fn version(self: @ContractState) -> ByteArray {
            "0.2.0"
        }

        fn update_collection_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            assert(new_class_hash.into() != 0_felt252, 'Class hash is zero');

            let previous_class_hash = self.ip_collection_class_hash.read();
            self.ip_collection_class_hash.write(new_class_hash);
            self
                .emit(
                    CollectionClassHashUpdated {
                        previous_class_hash,
                        new_class_hash,
                    },
                );
        }

        fn deploy_collection(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
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
                self.ip_collection_class_hash.read(), salt, calldata.span(), false,
            )
                .unwrap_syscall();

            self
                .emit(
                    CollectionDeployed {
                        collection_address, owner: caller, name, symbol, base_uri,
                    },
                );

            collection_address
        }
    }
}
