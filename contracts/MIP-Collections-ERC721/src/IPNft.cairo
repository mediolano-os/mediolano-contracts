#[starknet::contract]
pub mod IPNft {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc721::extensions::ERC721EnumerableComponent;
    use openzeppelin::token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interfaces::IIPNFT::IIPNft;
    use crate::types::{MAX_BASE_URI_LEN, MAX_NAME_LEN, MAX_SYMBOL_LEN, MAX_TOKEN_URI_LEN};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent,
    );

    // COMP-01: UpgradeableComponent intentionally removed.
    // IPNft contracts are permanently immutable by design — the per-token URI, creator,
    // and timestamp constitute the legal IP registration record under the Berne Convention.
    // Upgradeability of this contract would allow altering that record, which is prohibited.

    // No owner or role admin exists. Mint/archive authority is the immutable
    // registry address written once in the constructor.

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
        /// Per-token metadata URIs — written once at mint, never updated (immutable).
        uris: Map<u256, ByteArray>,
        /// COMP-02: Original creator per token — immutable Berne Convention authorship record.
        token_creators: Map<u256, ContractAddress>,
        /// COMP-03: Registration timestamp per token — immutable proof of creation date.
        token_registered_at: Map<u256, u64>,
        /// COMP-05: Archived state per token — preserves the record while marking as inactive.
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

    /// Constructor.
    /// R-04: `owner` parameter removed — OwnableComponent is gone.
    /// The `registry` (IPCollection factory address) is immutable and is the only
    /// address allowed to mint or archive.
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
            // COMP-05: Block any transfer of an archived token.
            // Archived tokens are permanently immobile — their record is preserved as-is.
            // This fires on both mint and transfer; Map defaults to false so mints pass cleanly.
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
            // Return the immutable per-token URI directly. Collection base_uri is
            // informational and is not concatenated with token IDs.
            self.uris.read(token_id)
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnly of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            // Return the immutable per-token URI directly. Collection base_uri is
            // informational and is not concatenated with token IDs.
            self.uris.read(tokenId)
        }
    }

    #[abi(embed_v0)]
    impl IPNftImpl of IIPNft<ContractState> {
        /// Mints a new ERC-721 token to the specified recipient.
        /// Only callable by the immutable IPCollection factory.
        ///
        /// token_uri is stored permanently and must not be empty.
        /// COMP-02: creator is stored as the immutable original_creator.
        /// COMP-03: block timestamp is stored as the immutable registered_at.
        fn mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            token_uri: ByteArray,
            creator: ContractAddress,
        ) {
            assert(get_caller_address() == self.registry.read(), 'Only registry');

            // R-05: token IDs must be > 0 (IPCollection assigns IDs starting at 1)
            assert(token_id != 0, 'Token ID cannot be zero');
            assert(!creator.is_zero(), 'Creator is zero address');
            assert(token_uri.len() > 0 && token_uri.len() <= MAX_TOKEN_URI_LEN, 'Invalid URI length');

            // mint intentionally does not call safe_mint; IP records can be minted to any
            // account/contract without requiring an ERC721 receiver callback.
            self.erc721.mint(recipient, token_id);
            self.uris.write(token_id, token_uri);

            // COMP-02: store original creator — permanent, never overwritten
            self.token_creators.write(token_id, creator);

            // COMP-03: store registration timestamp — permanent, never overwritten
            self.token_registered_at.write(token_id, get_block_timestamp());
        }

        /// Archives a token permanently.
        /// The on-chain record (URI, creator, timestamp, ownership) is preserved forever.
        /// Archived tokens cannot be transferred or re-archived.
        /// Only callable by the immutable IPCollection factory.
        fn archive(ref self: ContractState, token_id: u256) {
            assert(get_caller_address() == self.registry.read(), 'Only registry');
            self.erc721._require_owned(token_id);
            assert(!self.token_archived.read(token_id), 'Already archived');
            // Write the archived flag — the ERC721 state is intentionally preserved
            self.token_archived.write(token_id, true);
        }

        /// Returns true if the token has been archived.
        fn is_archived(self: @ContractState, token_id: u256) -> bool {
            self.token_archived.read(token_id)
        }

        /// Returns the collection ID associated with this contract.
        fn get_collection_id(self: @ContractState) -> u256 {
            self.collection_id.read()
        }

        /// Returns the address of the immutable registry (IPCollection factory).
        fn get_registry(self: @ContractState) -> ContractAddress {
            self.registry.read()
        }

        /// Returns the informational base URI of the collection.
        fn base_uri(self: @ContractState) -> ByteArray {
            self.erc721._base_uri()
        }

        /// Returns all token IDs owned by a specific address.
        fn all_tokens_of_owner(self: @ContractState, owner: ContractAddress) -> Span<u256> {
            self.erc721_enumerable.all_tokens_of_owner(owner)
        }

        /// Returns true if the token exists without panicking.
        /// Reads the ERC721 owner slot directly — zero means the token doesn't exist.
        fn token_exists(self: @ContractState, token_id: u256) -> bool {
            !self.erc721.ERC721_owners.read(token_id).is_zero()
        }

        /// Returns all legal record fields for a token in a single call.
        /// Reverts if the token does not exist.
        /// Replaces four separate cross-contract calls from IPCollection.get_token.
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

        /// Returns the original creator address stored immutably at mint time.
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
    }
}
