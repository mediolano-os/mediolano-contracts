// DESIGN: IPCollection is permanently immutable — no UpgradeableComponent, no admin roles.
// This contract is the standalone Mediolano IP provenance ERC-721 service used
// by genesis/shared mints. New collection protocols should use the MIP collection
// architecture or the collaborative collection contracts instead of copying this
// package as a factory template.
//
// Each deployment is a standalone ERC-721 NFT collection. The per-token URI,
// creator address, and registration timestamp constitute the legal IP provenance
// record under the Mediolano platform standard and the Berne Convention.
//
// DESIGN: Mint is permissionless — any caller can mint to any recipient.
// `collection_creator` is purely informational (who deployed this collection).
// No address holds any privileged power over this contract after deployment.
// The token ID counter (next_token_id) is internal and never exposed publicly.

#[starknet::contract]
pub mod IPCollection {
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
    use crate::interfaces::IIPCollection::{IIPCollection, IIP_COLLECTION_ID};
    use crate::types::{TokenData, bytearray_starts_with};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent,
    );

    // --- Exposed ABI implementations ---
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    // --- Internal implementations (not exposed) ---
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
        /// Address that deployed this collection. Informational only — holds no special power.
        collection_creator: ContractAddress,
        /// Internal token ID counter. Starts at 1; never exposed publicly.
        next_token_id: u256,
        /// Full content-addressed URI per token. Written once at mint, never modified.
        token_uris: Map<u256, ByteArray>,
        /// Original minter per token — immutable Berne Convention authorship record.
        token_creators: Map<u256, ContractAddress>,
        /// Block timestamp at mint — immutable proof of creation date.
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
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        IPMinted: IPMinted,
    }

    /// Emitted on every successful mint.
    /// `token_id` and `recipient` are indexed for efficient filtering by indexers.
    #[derive(Drop, starknet::Event)]
    pub struct IPMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub recipient: ContractAddress,
        pub uri: ByteArray,
        pub creator: ContractAddress,
        pub registered_at: u64,
    }

    /// Deploys a new standalone IPCollection.
    ///
    /// # Arguments
    /// * `name`   - Human-readable collection name (e.g. "My IP Collection")
    /// * `symbol` - Collection ticker symbol (e.g. "MIP")
    /// * `collection_creator` - Informational creator address (holds no admin power)
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        collection_creator: ContractAddress,
    ) {
        // base_uri is intentionally empty — every token stores its full ipfs:// or ar:// URI.
        self.erc721.initializer(name, symbol, "");
        self.erc721_enumerable.initializer();
        self.src5.register_interface(IIP_COLLECTION_ID);
        self.collection_creator.write(collection_creator);
        // Token IDs start at 1; zero is reserved as "non-existent"
        self.next_token_id.write(1);
    }

    /// ERC721 hooks — delegate enumerable bookkeeping to the OZ component.
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

    // --- IERC721Metadata override ---
    // Returns the full stored URI directly — no base_uri concatenation.

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

    // --- IIPCollection implementation ---

    #[abi(embed_v0)]
    impl IPCollectionImpl of IIPCollection<ContractState> {
        /// Mints a new token to `recipient`.
        ///
        /// Permissionless — callable by anyone.
        /// Validates:
        ///   - `recipient` is not the zero address
        ///   - `token_uri` starts with `ipfs://` or `ar://`
        ///
        /// Uses safe_mint to revert cleanly if `recipient` is a contract that does
        /// not implement IERC721Receiver, preventing permanent token lockup.
        fn mint_item(
            ref self: ContractState, recipient: ContractAddress, token_uri: ByteArray,
        ) -> u256 {
            assert(!recipient.is_zero(), 'Recipient is zero address');

            let valid_uri = bytearray_starts_with(@token_uri, @"ipfs://")
                || bytearray_starts_with(@token_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            let creator = get_caller_address();
            assert(!creator.is_zero(), 'Creator is zero address');

            self.erc721.safe_mint(recipient, token_id, array![].span());

            self.token_uris.write(token_id, token_uri.clone());
            self.token_creators.write(token_id, creator);

            let timestamp = get_block_timestamp();
            self.token_registered_at.write(token_id, timestamp);

            self
                .emit(
                    IPMinted {
                        token_id, recipient, uri: token_uri, creator, registered_at: timestamp,
                    },
                );

            token_id
        }

        /// Returns the address that deployed this collection.
        /// Informational only — this address holds no special power over the contract.
        fn get_collection_creator(self: @ContractState) -> ContractAddress {
            self.collection_creator.read()
        }

        /// Returns the original creator stored immutably at mint time.
        /// Reverts if the token does not exist.
        fn get_token_creator(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._require_owned(token_id);
            self.token_creators.read(token_id)
        }

        /// Returns the block timestamp stored immutably at mint time.
        /// Reverts if the token does not exist.
        fn get_token_registered_at(self: @ContractState, token_id: u256) -> u64 {
            self.erc721._require_owned(token_id);
            self.token_registered_at.read(token_id)
        }

        /// Returns all provenance fields for a token in a single call.
        /// Reverts if the token does not exist.
        fn get_token_data(self: @ContractState, token_id: u256) -> TokenData {
            self.erc721._require_owned(token_id);
            TokenData {
                token_id,
                owner: self.erc721.ERC721_owners.read(token_id),
                metadata_uri: self.token_uris.read(token_id),
                original_creator: self.token_creators.read(token_id),
                registered_at: self.token_registered_at.read(token_id),
            }
        }
    }
}
