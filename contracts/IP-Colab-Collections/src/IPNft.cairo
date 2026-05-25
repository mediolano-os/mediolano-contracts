#[starknet::contract]
pub mod IPNft {
    use core::num::traits::Zero;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc721::extensions::ERC721EnumerableComponent;
    use openzeppelin::token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interfaces::IIPNft::IIPNft;
    use crate::types::{MAX_BASE_URI_LEN, MAX_NAME_LEN, MAX_SYMBOL_LEN, MAX_TOKEN_URI_LEN};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent,
    );

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;
    impl SRC5ComponentInternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        registry: ContractAddress,
        collection_id: u256,
        uris: Map<u256, ByteArray>,
        token_creators: Map<u256, ContractAddress>,
        token_registered_at: Map<u256, u64>,
        token_archived: Map<u256, bool>,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        collection_id: u256,
        registry: ContractAddress,
    ) {
        assert(name.len() > 0 && name.len() <= MAX_NAME_LEN, 'Invalid name length');
        assert(symbol.len() > 0 && symbol.len() <= MAX_SYMBOL_LEN, 'Invalid symbol length');
        assert(base_uri.len() <= MAX_BASE_URI_LEN, 'Base URI too long');
        assert(!registry.is_zero(), 'Registry is zero address');

        self.erc721.initializer(name, symbol, base_uri);
        self.erc721_enumerable.initializer();
        self.collection_id.write(collection_id);
        self.registry.write(registry);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let mut contract_state = self.get_contract_mut();
            assert(!contract_state.token_archived.read(token_id), 'Token is archived');
            contract_state.erc721_enumerable.before_update(to, token_id);
        }
    }

    #[abi(embed_v0)]
    impl ERC721Metadata of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            self.uris.read(token_id)
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnly of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            self.uris.read(tokenId)
        }
    }

    #[abi(embed_v0)]
    impl IPNftImpl of IIPNft<ContractState> {
        fn mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            token_uri: ByteArray,
            creator: ContractAddress,
        ) {
            assert(get_caller_address() == self.registry.read(), 'Only registry');
            assert(token_id != 0, 'Token ID cannot be zero');
            assert(!creator.is_zero(), 'Creator is zero address');
            assert(
                token_uri.len() > 0 && token_uri.len() <= MAX_TOKEN_URI_LEN, 'Invalid URI length',
            );

            self.erc721.mint(recipient, token_id);
            self.uris.write(token_id, token_uri);
            self.token_creators.write(token_id, creator);
            self.token_registered_at.write(token_id, get_block_timestamp());
        }

        fn archive(ref self: ContractState, token_id: u256) {
            assert(get_caller_address() == self.registry.read(), 'Only registry');
            self.erc721._require_owned(token_id);
            assert(!self.token_archived.read(token_id), 'Already archived');
            self.token_archived.write(token_id, true);
        }

        fn is_archived(self: @ContractState, token_id: u256) -> bool {
            self.token_archived.read(token_id)
        }

        fn get_collection_id(self: @ContractState) -> u256 {
            self.collection_id.read()
        }

        fn get_registry(self: @ContractState) -> ContractAddress {
            self.registry.read()
        }

        fn base_uri(self: @ContractState) -> ByteArray {
            self.erc721._base_uri()
        }

        fn all_tokens_of_owner(self: @ContractState, owner: ContractAddress) -> Span<u256> {
            self.erc721_enumerable.all_tokens_of_owner(owner)
        }

        fn token_exists(self: @ContractState, token_id: u256) -> bool {
            !self.erc721.ERC721_owners.read(token_id).is_zero()
        }

        fn get_full_token_data(
            self: @ContractState, token_id: u256,
        ) -> (ContractAddress, ByteArray, ContractAddress, u64) {
            self.erc721._require_owned(token_id);
            let owner = self.erc721.ERC721_owners.read(token_id);
            let metadata_uri = self.uris.read(token_id);
            let original_creator = self.token_creators.read(token_id);
            let registered_at = self.token_registered_at.read(token_id);
            (owner, metadata_uri, original_creator, registered_at)
        }

        fn get_token_creator(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._require_owned(token_id);
            self.token_creators.read(token_id)
        }

        fn get_token_registered_at(self: @ContractState, token_id: u256) -> u64 {
            self.erc721._require_owned(token_id);
            self.token_registered_at.read(token_id)
        }
    }
}
