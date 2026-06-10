// DESIGN: IPCollection is permanently immutable — no UpgradeableComponent, no admin roles
// beyond the collection owner's mint rights. Each collection is a standalone ERC-1155
// contract deployed by IPCollectionFactory. The original creator address and registration
// timestamp are written once at the first mint of each token type and can never be changed.
// This constitutes the immutable IP provenance record under the Berne Convention standard.
//
// URI strategy:
//   - `base_uri` is the collection-level metadata URI set at deploy time (e.g. an IPFS
//     JSON containing the collection image, description, and external link).
//   - `uri(token_id)` returns the per-token URI if one has been minted, otherwise falls
//     back to `base_uri`. This mirrors the ERC-721 base_uri pattern while still supporting
//     content-addressed per-token URIs for IP provenance.
//
// ERC-2981 royalty support: the collection owner can set a default royalty (applies to all
// token types) and per-token overrides. Royalty starts at 0% and is fully owner-controlled.
// Fee denominator is 10,000 — so fee_numerator 500 = 5%, 1000 = 10%, etc.

#[starknet::contract]
pub mod IPCollection {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc1155::ERC1155Component;
    use openzeppelin::token::erc1155::ERC1155HooksEmptyImpl;
    use openzeppelin::token::erc1155::interface::IERC1155MetadataURI;
    use openzeppelin::token::common::erc2981::{ERC2981Component, DefaultConfig};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess,
        StorageMapWriteAccess,
    };
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interfaces::IIPCollection::IIPCollection;
    use crate::types::{TokenData, MAX_TOKEN_URI_LEN};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: ERC2981Component, storage: erc2981, event: ERC2981Event);

    // --- Exposed ABI implementations ---
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    // Embed ERC1155 transfers/approvals but NOT ERC1155MetadataURIImpl —
    // we provide our own uri() that returns per-token URIs with base_uri fallback.
    #[abi(embed_v0)]
    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155CamelImpl = ERC1155Component::ERC1155CamelImpl<ContractState>;
    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;

    // ERC-2981: royalty_info (read), default_royalty/token_royalty (info), admin (owner-gated)
    #[abi(embed_v0)]
    impl ERC2981Impl = ERC2981Component::ERC2981Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC2981InfoImpl = ERC2981Component::ERC2981InfoImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC2981AdminOwnableImpl = ERC2981Component::ERC2981AdminOwnableImpl<ContractState>;
    impl ERC2981InternalImpl = ERC2981Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        erc2981: ERC2981Component::Storage,
        /// Human-readable collection name (display only, not part of ERC-1155 standard).
        collection_name: ByteArray,
        /// Collection ticker symbol (display only).
        collection_symbol: ByteArray,
        /// Collection-level metadata URI. Points to a JSON with collection image, description,
        /// and external link. Also serves as fallback for uri(token_id) on unminted tokens.
        collection_base_uri: ByteArray,
        /// Address that originally deployed this collection via the factory.
        /// Immutable — does not change if ownership is transferred.
        collection_creator: ContractAddress,
        /// Per-token-type URI. Written once at first mint of each token_id, never modified.
        token_uris: Map<u256, ByteArray>,
        /// Original minter per token type — immutable Berne Convention authorship record.
        token_creators: Map<u256, ContractAddress>,
        /// Block timestamp at first mint — immutable proof of creation date.
        token_registered_at: Map<u256, u64>,
        /// Next edition id to assign. Initialized to 1 at deploy; incremented per mint_edition.
        next_token_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        #[flat]
        ERC2981Event: ERC2981Component::Event,
        IPMinted: IPMinted,
    }

    /// Emitted on every mint (mint_edition, batch_mint_edition, add_supply).
    /// `token_id` and `recipient` are indexed for efficient indexer filtering.
    #[derive(Drop, starknet::Event)]
    pub struct IPMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub recipient: ContractAddress,
        pub value: u256,
        pub uri: ByteArray,
        pub creator: ContractAddress,
        pub registered_at: u64,
    }

    /// Deploys a new standalone IPCollection.
    ///
    /// # Arguments
    /// * `name`     - Human-readable collection name (e.g. "My IP Collection")
    /// * `symbol`   - Collection ticker symbol (e.g. "MIP1155")
    /// * `base_uri` - Collection-level metadata URI (e.g. "ipfs://Qm…/collection.json").
    ///                May be empty. Used as fallback for uri(token_id) on unminted tokens.
    /// * `owner`    - Address that owns this collection and can mint into it
    ///
    /// Royalty starts at 0% pointing to `owner`. Call `set_default_royalty` to activate.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        owner: ContractAddress,
    ) {
        assert(!owner.is_zero(), 'Owner is zero address');
        // Initialize ERC1155 with empty base URI — we manage URIs ourselves.
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.collection_name.write(name);
        self.collection_symbol.write(symbol);
        self.collection_base_uri.write(base_uri);
        self.collection_creator.write(owner);
        // Initialize ERC-2981 with 0% royalty pointing to owner.
        // Owner can activate royalties post-deploy via set_default_royalty(receiver, fee_numerator).
        self.erc2981.initializer(owner, 0);
        // Editions are numbered from 1.
        self.next_token_id.write(1);
    }

    // --- ERC1155 URI override ---
    // Returns the per-token URI if one has been set, otherwise falls back to base_uri.
    // This satisfies the IERC1155MetadataURI interface while supporting both per-token
    // content-addressed URIs (for IP provenance) and collection-level base_uri fallback.

    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, token_id: u256) -> ByteArray {
            let token_uri = self.token_uris.read(token_id);
            if token_uri.len() > 0 {
                token_uri
            } else {
                self.collection_base_uri.read()
            }
        }
    }

    // --- IIPCollection implementation ---

    #[abi(embed_v0)]
    impl IPCollectionImpl of IIPCollection<ContractState> {
        // ── Collection metadata ────────────────────────────────────────────────

        fn name(self: @ContractState) -> ByteArray {
            self.collection_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.collection_symbol.read()
        }

        fn base_uri(self: @ContractState) -> ByteArray {
            self.collection_base_uri.read()
        }

        fn version(self: @ContractState) -> ByteArray {
            "0.2.0"
        }

        // ── Minting ────────────────────────────────────────────────────────────

        fn mint_edition(
            ref self: ContractState,
            to: ContractAddress,
            value: u256,
            token_uri: ByteArray,
        ) -> u256 {
            self.ownable.assert_only_owner();
            assert(!to.is_zero(), 'Recipient is zero address');
            let token_id = self.next_token_id.read();
            self._mint_new(get_caller_address(), to, token_id, value, token_uri);
            self.next_token_id.write(token_id + 1);
            token_id
        }

        fn add_supply(
            ref self: ContractState, to: ContractAddress, token_id: u256, value: u256,
        ) {
            self.ownable.assert_only_owner();
            assert(!to.is_zero(), 'Recipient is zero address');
            assert(value > 0, 'Value must be > 0');
            let creator = self.token_creators.read(token_id);
            assert(creator.is_non_zero(), 'Token does not exist');
            self.erc1155.mint_with_acceptance_check(to, token_id, value, array![].span());
            self
                .emit(
                    IPMinted {
                        token_id, recipient: to, value,
                        uri: self.token_uris.read(token_id),
                        creator,
                        registered_at: self.token_registered_at.read(token_id),
                    },
                );
        }

        // ── Provenance queries ─────────────────────────────────────────────────

        fn get_collection_creator(self: @ContractState) -> ContractAddress {
            self.collection_creator.read()
        }

        fn get_token_creator(self: @ContractState, token_id: u256) -> ContractAddress {
            let creator = self.token_creators.read(token_id);
            assert(creator.is_non_zero(), 'Token does not exist');
            creator
        }

        fn get_token_registered_at(self: @ContractState, token_id: u256) -> u64 {
            let creator = self.token_creators.read(token_id);
            assert(creator.is_non_zero(), 'Token does not exist');
            self.token_registered_at.read(token_id)
        }

        fn get_token_data(self: @ContractState, token_id: u256) -> TokenData {
            let creator = self.token_creators.read(token_id);
            assert(creator.is_non_zero(), 'Token does not exist');
            TokenData {
                token_id,
                metadata_uri: self.token_uris.read(token_id),
                original_creator: creator,
                registered_at: self.token_registered_at.read(token_id),
            }
        }
    }

    // --- Internal helpers ---

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Mints a brand-new edition: always records provenance (the id is guaranteed fresh
        /// by the counter). `value` must be > 0; `token_uri` length is validated.
        fn _mint_new(
            ref self: ContractState,
            creator: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            token_uri: ByteArray,
        ) {
            assert(value > 0, 'Value must be > 0');
            assert(
                token_uri.len() > 0 && token_uri.len() <= MAX_TOKEN_URI_LEN,
                'Invalid URI length',
            );
            let timestamp = get_block_timestamp();
            self.token_uris.write(token_id, token_uri.clone());
            self.token_creators.write(token_id, creator);
            self.token_registered_at.write(token_id, timestamp);
            self.erc1155.mint_with_acceptance_check(to, token_id, value, array![].span());
            self
                .emit(
                    IPMinted {
                        token_id, recipient: to, value, uri: token_uri,
                        creator, registered_at: timestamp,
                    },
                );
        }

    }
}
