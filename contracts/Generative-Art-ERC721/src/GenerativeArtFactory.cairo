// DESIGN: Ownerless deployer for GenerativeArt collections. No admin, no
// update_class_hash, no privileged state — a pure deploy helper. Mirrors the
// IP-Programmable-ERC1155 v0.3.0 factory pattern.

#[starknet::contract]
pub mod GenerativeArtFactory {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::interfaces::IGenerativeArtFactory::IGenerativeArtFactory;

    #[storage]
    struct Storage {
        collection_class_hash: ClassHash,
        /// Monotonic nonce for unique deploy salts.
        deploy_nonce: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CollectionDeployed: CollectionDeployed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollectionDeployed {
        #[key]
        pub collection_address: ContractAddress,
        #[key]
        pub creator: ContractAddress,
        pub script_hash: felt252,
        pub max_supply: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, collection_class_hash: ClassHash) {
        assert(collection_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.collection_class_hash.write(collection_class_hash);
    }

    #[abi(embed_v0)]
    impl FactoryImpl of IGenerativeArtFactory<ContractState> {
        fn collection_class_hash(self: @ContractState) -> ClassHash {
            self.collection_class_hash.read()
        }

        fn deploy_collection(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            script_hash: felt252,
            script_uri: ByteArray,
            max_supply: u256,
            royalty_receiver: ContractAddress,
            royalty_bps: u16,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name must not be empty');
            assert(symbol.len() > 0, 'Symbol must not be empty');

            let caller = get_caller_address();
            let nonce = self.deploy_nonce.read();
            let salt = PoseidonTrait::new().update_with(caller).update_with(nonce).finalize();
            self.deploy_nonce.write(nonce + 1);

            // Constructor calldata order MUST match GenerativeArt::constructor.
            let mut calldata: Array<felt252> = array![];
            name.serialize(ref calldata);
            symbol.serialize(ref calldata);
            base_uri.serialize(ref calldata);
            script_hash.serialize(ref calldata);
            script_uri.serialize(ref calldata);
            max_supply.serialize(ref calldata);
            royalty_receiver.serialize(ref calldata);
            royalty_bps.serialize(ref calldata);

            let (collection_address, _) = deploy_syscall(
                self.collection_class_hash.read(), salt, calldata.span(), false,
            )
                .unwrap_syscall();

            self
                .emit(
                    CollectionDeployed {
                        collection_address, creator: caller, script_hash, max_supply,
                    },
                );
            collection_address
        }
    }
}
