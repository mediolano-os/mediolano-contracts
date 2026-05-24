// DESIGN: IPCollection is a permissionless-to-deploy, owner-minted ERC-721
// collection for canonical IP issuance. The owner is the collection authority
// and sole minter; there is no upgrade path and no platform fee logic.
//
// Each token stores a full content-addressed URI plus immutable provenance
// fields at mint time. Transfers use the standard ERC-721 ABI.

#[starknet::contract]
pub mod IPCollection {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc721::extensions::ERC721EnumerableComponent;
    use openzeppelin::token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interfaces::IIPCollection::{IIPCollection, IIP_COLLECTION_ID};
    use crate::types::{TokenData, bytearray_starts_with};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
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
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
        /// Address recorded as the initial collection issuer and mint authority.
        collection_issuer: ContractAddress,
        /// Internal token ID counter. Starts at 1; zero is reserved as non-existent.
        next_token_id: u256,
        /// Full content-addressed URI per token. Written once at mint, never modified.
        token_uris: Map<u256, ByteArray>,
        /// Collection authority that minted the token.
        token_issuers: Map<u256, ContractAddress>,
        /// Block timestamp at mint.
        token_registered_at: Map<u256, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        IPMinted: IPMinted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct IPMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub recipient: ContractAddress,
        pub uri: ByteArray,
        pub issuer: ContractAddress,
        pub registered_at: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, name: ByteArray, symbol: ByteArray, owner: ContractAddress,
    ) {
        assert(!owner.is_zero(), 'Owner is zero address');

        // base_uri is intentionally empty; every token stores its full URI.
        self.erc721.initializer(name, symbol, "");
        self.erc721_enumerable.initializer();
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_COLLECTION_ID);
        self.collection_issuer.write(owner);
        self.next_token_id.write(1);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.erc721_enumerable.before_update(to, token_id);
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
    }

    #[abi(embed_v0)]
    impl ERC721MetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            self.token_uris.read(token_id)
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            self.token_uris.read(tokenId)
        }
    }

    #[abi(embed_v0)]
    impl IPCollectionImpl of IIPCollection<ContractState> {
        fn mint_item(
            ref self: ContractState, recipient: ContractAddress, token_uri: ByteArray,
        ) -> u256 {
            self.ownable.assert_only_owner();
            assert(!recipient.is_zero(), 'Recipient is zero address');

            let valid_uri = bytearray_starts_with(@token_uri, @"ipfs://")
                || bytearray_starts_with(@token_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            self.erc721.safe_mint(recipient, token_id, array![].span());

            let issuer = get_caller_address();
            self.token_uris.write(token_id, token_uri.clone());
            self.token_issuers.write(token_id, issuer);

            let timestamp = get_block_timestamp();
            self.token_registered_at.write(token_id, timestamp);

            self
                .emit(
                    IPMinted {
                        token_id, recipient, uri: token_uri, issuer, registered_at: timestamp,
                    },
                );

            token_id
        }

        fn get_collection_issuer(self: @ContractState) -> ContractAddress {
            self.collection_issuer.read()
        }

        fn get_token_issuer(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._require_owned(token_id);
            self.token_issuers.read(token_id)
        }

        fn get_token_registered_at(self: @ContractState, token_id: u256) -> u64 {
            self.erc721._require_owned(token_id);
            self.token_registered_at.read(token_id)
        }

        fn get_token_data(self: @ContractState, token_id: u256) -> TokenData {
            self.erc721._require_owned(token_id);
            TokenData {
                token_id,
                owner: self.erc721.ERC721_owners.read(token_id),
                metadata_uri: self.token_uris.read(token_id),
                issuer: self.token_issuers.read(token_id),
                registered_at: self.token_registered_at.read(token_id),
            }
        }
    }
}
