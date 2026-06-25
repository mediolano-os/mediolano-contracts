#[starknet::contract]
pub mod IPCollection {
    use core::dict::Felt252Dict;
    use core::num::traits::Zero;
    use openzeppelin::token::erc721::extensions::erc721_enumerable::interface::{
        ERC721EnumerableABIDispatcher as IERC721EnumerableDispatcher,
        ERC721EnumerableABIDispatcherTrait,
    };
    use openzeppelin::token::erc721::{
        ERC721ABIDispatcher as IERC721Dispatcher, ERC721ABIDispatcherTrait,
    };
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::interfaces::IIPCollection::IIPCollection;
    use crate::interfaces::IIPNFT::{IIPNftDispatcher, IIPNftDispatcherTrait};
    use crate::types::{
        Collection, CollectionStats, MAX_BASE_URI_LEN, MAX_NAME_LEN, MAX_SYMBOL_LEN, TokenData,
    };

    // IPCollection is intentionally immutable. It deploys immutable IPNft
    // contracts and provides a permanent registry view over their records.

    #[storage]
    struct Storage {
        collections: Map<u256, Collection>,
        collection_count: u256,
        collection_stats: Map<u256, CollectionStats>,
        ip_nft_class_hash: ClassHash,
        user_collections: Map<(ContractAddress, u256), u256>,
        user_collection_index: Map<ContractAddress, u256>,
        collection_owner_index: Map<u256, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CollectionCreated: CollectionCreated,
        CollectionOwnershipTransferred: CollectionOwnershipTransferred,
        TokenMinted: TokenMinted,
        TokenMintedBatch: TokenMintedBatch,
        TokenArchived: TokenArchived,
        TokenArchivedBatch: TokenArchivedBatch,
        TokenTransferred: TokenTransferred,
        TokenTransferredBatch: TokenTransferredBatch,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollectionCreated {
        #[key]
        pub collection_id: u256,
        pub owner: ContractAddress,
        pub name: ByteArray,
        pub symbol: ByteArray,
        pub base_uri: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollectionOwnershipTransferred {
        #[key]
        pub collection_id: u256,
        pub previous_owner: ContractAddress,
        pub new_owner: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenMinted {
        #[key]
        pub collection_id: u256,
        #[key]
        pub token_id: u256,
        pub owner: ContractAddress,
        pub metadata_uri: ByteArray,
        pub royalty_bps: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenMintedBatch {
        #[key]
        pub collection_id: u256,
        pub token_ids: Span<u256>,
        pub owners: Array<ContractAddress>,
        // per-token URIs included so event-only/indexer-independent readers can
        // reconstruct batch-minted metadata without per-token `token_uri` reads.
        pub metadata_uris: Array<ByteArray>,
        pub operator: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenArchived {
        #[key]
        pub collection_id: u256,
        #[key]
        pub token_id: u256,
        pub operator: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenArchivedBatch {
        pub collection_ids: Span<u256>,
        pub token_ids: Span<u256>,
        pub operator: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenTransferred {
        #[key]
        pub collection_id: u256,
        #[key]
        pub token_id: u256,
        pub from: ContractAddress,
        pub to: ContractAddress,
        pub operator: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenTransferredBatch {
        pub from: ContractAddress,
        pub to: ContractAddress,
        pub collection_ids: Span<u256>,
        pub token_ids: Span<u256>,
        pub operator: ContractAddress,
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, ip_nft_class_hash: ClassHash) {
        assert(ip_nft_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.ip_nft_class_hash.write(ip_nft_class_hash);
    }

    #[abi(embed_v0)]
    impl IPCollectionImpl of IIPCollection<ContractState> {
        /// Creates a new NFT collection and deploys a dedicated IPNft contract for it.
        /// The caller becomes the collection owner.
        fn create_collection(
            ref self: ContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
        ) -> u256 {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Caller is zero address');

            // validate non-empty name and symbol
            assert(name.len() > 0 && name.len() <= MAX_NAME_LEN, 'Invalid name length');
            assert(symbol.len() > 0 && symbol.len() <= MAX_SYMBOL_LEN, 'Invalid symbol length');
            assert(base_uri.len() <= MAX_BASE_URI_LEN, 'Base URI too long');

            let collection_id = self.collection_count.read() + 1;
            let registry = get_contract_address();

            // 4-M CRITICAL: calldata must match IPNft constructor exactly.
            // IPNft constructor: (name, symbol, base_uri, collection_id, registry)
            let mut constructor_calldata: Array<felt252> = array![];
            (name.clone(), symbol.clone(), base_uri.clone(), collection_id, registry)
                .serialize(ref constructor_calldata);

            let (ip_nft_address, _) = deploy_syscall(
                self.ip_nft_class_hash.read(), 0, constructor_calldata.span(), false,
            )
                .unwrap();

            let collection = Collection {
                name: name.clone(),
                symbol: symbol.clone(),
                base_uri: base_uri.clone(),
                owner: caller,
                ip_nft: ip_nft_address,
            };

            self.collections.entry(collection_id).write(collection);
            self.collection_count.write(collection_id);

            let user_collection_index = self.user_collection_index.read(caller);
            self.user_collections.entry((caller, user_collection_index)).write(collection_id);
            self.user_collection_index.entry(caller).write(user_collection_index + 1);
            self.collection_owner_index.entry(collection_id).write(user_collection_index);

            self.emit(CollectionCreated { collection_id, owner: caller, name, symbol, base_uri });

            collection_id
        }

        /// Mints a new token in the specified collection to the recipient address.
        /// Only the collection owner can mint. Token IDs start at 1.
        /// `royalty_bps` sets the token's immutable EIP-2981 secondary-sale royalty
        /// (receiver = the minting collection owner, recorded as the token creator).
        fn mint(
            ref self: ContractState,
            collection_id: u256,
            recipient: ContractAddress,
            token_uri: ByteArray,
            royalty_bps: u128,
        ) -> u256 {
            assert(!recipient.is_zero(), 'Recipient is zero address');

            let collection = self.collections.read(collection_id);
            assert(!collection.ip_nft.is_zero(), 'Invalid collection');
            let operator = get_caller_address();
            assert(operator == collection.owner, 'Only collection owner can mint');

            let mut collection_stats = self.collection_stats.read(collection_id);

            // token IDs start at 1 — total_minted + 1 gives the next ID
            let next_token_id = collection_stats.total_minted + 1;

            // CEI: advance + persist stats BEFORE the external mint call. A revert in
            // ip_nft.mint rolls this back; doing it first removes any reentrancy ID-collision
            // surface regardless of future mint internals.
            collection_stats.total_minted = next_token_id;
            collection_stats.last_mint_time = get_block_timestamp();
            self.collection_stats.entry(collection_id).write(collection_stats);

            let ip_nft = IIPNftDispatcher { contract_address: collection.ip_nft };
            ip_nft.mint(recipient, next_token_id, token_uri.clone(), operator, royalty_bps);

            self
                .emit(
                    TokenMinted {
                        collection_id,
                        token_id: next_token_id,
                        owner: recipient,
                        metadata_uri: token_uri,
                        royalty_bps,
                    },
                );

            next_token_id
        }

        /// Batch mints tokens in the specified collection to multiple recipients.
        /// Only the collection owner can batch mint. `recipients`, `token_uris`, and
        /// `royalty_bps` must all be the same length (per-token royalty).
        fn batch_mint(
            ref self: ContractState,
            collection_id: u256,
            recipients: Array<ContractAddress>,
            token_uris: Array<ByteArray>,
            royalty_bps: Array<u128>,
        ) -> Span<u256> {
            let n = recipients.len();
            assert(n > 0, 'Recipients array is empty');

            // all input arrays must be the same length
            assert(token_uris.len() == n, 'Array lengths mismatch');
            assert(royalty_bps.len() == n, 'Array lengths mismatch');

            let collection = self.collections.read(collection_id);
            assert(!collection.ip_nft.is_zero(), 'Invalid collection');

            let operator = get_caller_address();
            assert(operator == collection.owner, 'Only collection owner can mint');

            let mut collection_stats = self.collection_stats.read(collection_id);
            let base = collection_stats.total_minted;
            let timestamp = get_block_timestamp();

            // CEI: advance + persist stats BEFORE any external mint call.
            collection_stats.total_minted = base + n.into();
            collection_stats.last_mint_time = timestamp;
            self.collection_stats.entry(collection_id).write(collection_stats);

            let ip_nft = IIPNftDispatcher { contract_address: collection.ip_nft };

            let mut i: u32 = 0;
            let mut token_ids: Array<u256> = array![];

            while i < n {
                let recipient: ContractAddress = *recipients.at(i);
                let token_uri: ByteArray = token_uris.at(i).clone();
                assert(!recipient.is_zero(), 'Recipient is zero address');

                // token IDs start at 1
                let next_token_id = base + i.into() + 1;
                ip_nft.mint(recipient, next_token_id, token_uri, operator, *royalty_bps.at(i));
                token_ids.append(next_token_id);
                i += 1;
            }

            self
                .emit(
                    TokenMintedBatch {
                        collection_id,
                        token_ids: token_ids.span(),
                        owners: recipients,
                        metadata_uris: token_uris,
                        operator,
                        timestamp,
                    },
                );

            token_ids.span()
        }

        /// Transfers collection ownership atomically.
        /// This changes only future collection stewardship and mint authority.
        /// Existing token URI, creator, timestamp, and ownership records are untouched.
        fn transfer_collection_ownership(
            ref self: ContractState, collection_id: u256, new_owner: ContractAddress,
        ) {
            assert(!new_owner.is_zero(), 'New owner is zero address');

            let caller = get_caller_address();
            let mut collection = self.collections.read(collection_id);
            assert(!collection.ip_nft.is_zero(), 'Invalid collection');
            assert(collection.owner == caller, 'Not collection owner');
            assert(new_owner != caller, 'New owner is current owner');

            let old_owner = collection.owner;
            let old_index = self.collection_owner_index.read(collection_id);
            let old_count = self.user_collection_index.read(old_owner);
            let last_index = old_count - 1;

            if old_index != last_index {
                let moved_collection_id = self
                    .user_collections
                    .entry((old_owner, last_index))
                    .read();
                self.user_collections.entry((old_owner, old_index)).write(moved_collection_id);
                self.collection_owner_index.entry(moved_collection_id).write(old_index);
            }
            // Collection IDs start at 1, so zero is an unambiguous cleared slot marker.
            self.user_collections.entry((old_owner, last_index)).write(0);
            self.user_collection_index.entry(old_owner).write(last_index);

            let new_index = self.user_collection_index.read(new_owner);
            self.user_collections.entry((new_owner, new_index)).write(collection_id);
            self.user_collection_index.entry(new_owner).write(new_index + 1);
            self.collection_owner_index.entry(collection_id).write(new_index);

            collection.owner = new_owner;
            self.collections.entry(collection_id).write(collection);

            self
                .emit(
                    CollectionOwnershipTransferred {
                        collection_id,
                        previous_owner: old_owner,
                        new_owner,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        /// Archives a token, permanently preserving the on-chain provenance record.
        /// Only the token owner can archive their token.
        /// Replaces destructive burn — the IP registration record is never destroyed.
        fn archive(ref self: ContractState, collection_id: u256, token_id: u256) {
            let collection = self.collections.read(collection_id);
            assert(!collection.ip_nft.is_zero(), 'Invalid collection');

            let caller = get_caller_address();
            let token_owner = IERC721Dispatcher { contract_address: collection.ip_nft }
                .owner_of(token_id);
            assert(token_owner == caller, 'Caller not token owner');

            IIPNftDispatcher { contract_address: collection.ip_nft }.archive(token_id);

            let timestamp = get_block_timestamp();
            let mut collection_stats = self.collection_stats.read(collection_id);
            collection_stats.total_archived += 1;
            collection_stats.last_archive_time = timestamp;
            self.collection_stats.entry(collection_id).write(collection_stats);

            self.emit(TokenArchived { collection_id, token_id, operator: caller, timestamp });
        }

        /// Batch archives multiple tokens (parallel `collection_ids` / `token_ids`).
        /// Ownership verified for every token inside the loop.
        /// Stats are written once per unique collection, not once per token.
        fn batch_archive(
            ref self: ContractState, collection_ids: Array<u256>, token_ids: Array<u256>,
        ) {
            let n = collection_ids.len();
            assert(n > 0, 'Tokens array is empty');
            assert(token_ids.len() == n, 'Array lengths mismatch');

            let caller = get_caller_address();
            let timestamp = get_block_timestamp();

            // Accumulate archive counts per collection_id to minimise storage writes.
            // Key: collection_id.low (felt252); collection_ids are sequential u256 with high=0.
            let mut unique_cols: Array<u256> = array![];
            let mut col_counts: Felt252Dict<u128> = Default::default();

            let mut i: u32 = 0;
            while i < n {
                let collection_id = *collection_ids.at(i);
                let token_id = *token_ids.at(i);
                assert(collection_id.high == 0, 'Collection ID too large');
                let collection = self.collections.read(collection_id);
                assert(!collection.ip_nft.is_zero(), 'Invalid collection');

                // verify ownership for every token
                let token_owner = IERC721Dispatcher { contract_address: collection.ip_nft }
                    .owner_of(token_id);
                assert(token_owner == caller, 'Caller not token owner');

                IIPNftDispatcher { contract_address: collection.ip_nft }.archive(token_id);

                let key: felt252 = collection_id.low.into();
                let prev = col_counts.get(key);
                if prev == 0 {
                    unique_cols.append(collection_id);
                }
                col_counts.insert(key, prev + 1);

                i += 1;
            }

            // One storage read+write per unique collection rather than per token
            let mut j: u32 = 0;
            while j < unique_cols.len() {
                let col_id = *unique_cols.at(j);
                let count: u256 = col_counts.get(col_id.low.into()).into();
                let mut stats = self.collection_stats.read(col_id);
                stats.total_archived += count;
                stats.last_archive_time = timestamp;
                self.collection_stats.entry(col_id).write(stats);
                j += 1;
            }

            self
                .emit(
                    TokenArchivedBatch {
                        collection_ids: collection_ids.span(),
                        token_ids: token_ids.span(),
                        operator: caller,
                        timestamp,
                    },
                );
        }

        /// Transfers a token from its current owner to `to`.
        /// The IPCollection contract must be approved for the token.
        /// `from` is derived from on-chain ownership (was a redundant argument).
        /// caller must be the token owner or an approved operator.
        fn transfer_token(
            ref self: ContractState, to: ContractAddress, collection_id: u256, token_id: u256,
        ) {
            let collection = self.collections.read(collection_id);
            assert(!collection.ip_nft.is_zero(), 'Invalid collection');

            let caller = get_caller_address();
            let ip_nft = IERC721Dispatcher { contract_address: collection.ip_nft };

            let registry = get_contract_address();
            // registry must be approved, and caller must be owner or approved operator.
            let token_owner = assert_token_transfer_authorized(ip_nft, token_id, caller, registry);

            ip_nft.transfer_from(token_owner, to, token_id);

            // update protocol-routed transfer stats
            let timestamp = get_block_timestamp();
            let mut collection_stats = self.collection_stats.read(collection_id);
            collection_stats.protocol_routed_transfers += 1;
            collection_stats.last_transfer_time = timestamp;
            self.collection_stats.entry(collection_id).write(collection_stats);

            self
                .emit(
                    TokenTransferred {
                        collection_id, token_id, from: token_owner, to, operator: caller, timestamp,
                    },
                );
        }

        /// Batch transfers multiple tokens (parallel `collection_ids` / `token_ids`) from `from`.
        /// approval check and caller authorization enforced for every token.
        /// Stats are written once per unique collection, not once per token.
        fn batch_transfer(
            ref self: ContractState,
            to: ContractAddress,
            collection_ids: Array<u256>,
            token_ids: Array<u256>,
        ) {
            let n = collection_ids.len();
            assert(n > 0, 'Tokens array is empty');
            assert(token_ids.len() == n, 'Array lengths mismatch');

            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            // registry is invariant — read once, not per iteration.
            let registry = get_contract_address();

            // Derive the sender from on-chain ownership of the first token (rather than
            // trusting a caller argument). The per-token transfer_from below carries OZ's
            // `previous_owner == from` assert, so a batch spanning two owners reverts —
            // preserving the single-owner-batch invariant.
            let first_collection = self.collections.read(*collection_ids.at(0));
            assert(!first_collection.ip_nft.is_zero(), 'Invalid collection');
            let from = IERC721Dispatcher { contract_address: first_collection.ip_nft }
                .owner_of(*token_ids.at(0));

            // Accumulate transfer counts per collection_id to minimise storage writes
            let mut unique_cols: Array<u256> = array![];
            let mut col_counts: Felt252Dict<u128> = Default::default();

            let mut i: u32 = 0;
            while i < n {
                let collection_id = *collection_ids.at(i);
                let token_id = *token_ids.at(i);
                assert(collection_id.high == 0, 'Collection ID too large');
                let collection = self.collections.read(collection_id);
                assert(!collection.ip_nft.is_zero(), 'Invalid collection');

                let ip_nft = IERC721Dispatcher { contract_address: collection.ip_nft };

                // registry approved + caller authorized for this token. The sender is
                // the batch-derived `from`; transfer_from asserts each token shares that owner.
                let _ = assert_token_transfer_authorized(ip_nft, token_id, caller, registry);

                ip_nft.transfer_from(from, to, token_id);

                let key: felt252 = collection_id.low.into();
                let prev = col_counts.get(key);
                if prev == 0 {
                    unique_cols.append(collection_id);
                }
                col_counts.insert(key, prev + 1);

                i += 1;
            }

            // One storage read+write per unique collection rather than per token
            let mut j: u32 = 0;
            while j < unique_cols.len() {
                let col_id = *unique_cols.at(j);
                let count: u256 = col_counts.get(col_id.low.into()).into();
                let mut stats = self.collection_stats.read(col_id);
                stats.protocol_routed_transfers += count;
                stats.last_transfer_time = timestamp;
                self.collection_stats.entry(col_id).write(stats);
                j += 1;
            }

            self
                .emit(
                    TokenTransferredBatch {
                        from,
                        to,
                        collection_ids: collection_ids.span(),
                        token_ids: token_ids.span(),
                        operator: caller,
                        timestamp,
                    },
                );
        }

        /// Lists all token IDs owned by a user in a specific collection.
        fn list_user_tokens_per_collection(
            self: @ContractState, collection_id: u256, user: ContractAddress,
        ) -> Span<u256> {
            let collection = self.collections.read(collection_id);
            if collection.ip_nft.is_zero() {
                return array![].span();
            }
            let ip_nft = IERC721EnumerableDispatcher { contract_address: collection.ip_nft };
            ip_nft.all_tokens_of_owner(user)
        }

        /// Returns all collection IDs owned by the specified user.
        fn list_user_collections(self: @ContractState, user: ContractAddress) -> Span<u256> {
            let user_collection_index = self.user_collection_index.read(user);
            let mut collections = array![];
            let mut i: u256 = 0;
            while i < user_collection_index {
                let collection_id = self.user_collections.entry((user, i)).read();
                collections.append(collection_id);
                i += 1;
            }
            collections.span()
        }

        /// Retrieves the metadata and configuration of a specific collection.
        fn get_collection(self: @ContractState, collection_id: u256) -> Collection {
            self.collections.read(collection_id)
        }

        /// Returns the total number of collections ever created.
        fn get_collection_count(self: @ContractState) -> u256 {
            self.collection_count.read()
        }

        /// Returns the immutable implementation version for this deployed registry class.
        fn version(self: @ContractState) -> ByteArray {
            "0.5.0"
        }

        /// Retrieves statistics for a specific collection.
        fn get_collection_stats(self: @ContractState, collection_id: u256) -> CollectionStats {
            self.collection_stats.read(collection_id)
        }

        /// Checks if a collection exists.
        fn is_valid_collection(self: @ContractState, collection_id: u256) -> bool {
            let collection = self.collections.read(collection_id);
            !collection.ip_nft.is_zero()
        }

        /// Retrieves full token data including the immutable legal record fields.
        /// Reverts if the collection is invalid or the token does not exist.
        fn get_token(self: @ContractState, collection_id: u256, token_id: u256) -> TokenData {
            let collection = self.collections.read(collection_id);
            assert(!collection.ip_nft.is_zero(), 'Invalid collection');

            let nft = IIPNftDispatcher { contract_address: collection.ip_nft };
            let (owner, metadata_uri, original_creator, registered_at) = nft
                .get_full_token_data(token_id);

            TokenData {
                collection_id, token_id, owner, metadata_uri, original_creator, registered_at,
            }
        }

        /// Checks if a token is valid (exists in a valid collection).
        /// Safe: uses token_exists which never panics, unlike owner_of.
        fn is_valid_token(self: @ContractState, collection_id: u256, token_id: u256) -> bool {
            let collection = self.collections.read(collection_id);
            if collection.ip_nft.is_zero() {
                return false;
            }
            IIPNftDispatcher { contract_address: collection.ip_nft }.token_exists(token_id)
        }

        /// Checks if a token exists and has not been archived.
        fn is_transferable_token(
            self: @ContractState, collection_id: u256, token_id: u256,
        ) -> bool {
            let collection = self.collections.read(collection_id);
            if collection.ip_nft.is_zero() {
                return false;
            }
            let nft = IIPNftDispatcher { contract_address: collection.ip_nft };
            nft.token_exists(token_id) && !nft.is_archived(token_id)
        }

        /// Checks if a given address is the owner of a specific collection.
        fn is_collection_owner(
            self: @ContractState, collection_id: u256, owner: ContractAddress,
        ) -> bool {
            let collection = self.collections.read(collection_id);
            !collection.ip_nft.is_zero() && collection.owner == owner
        }
    }

    /// Asserts the registry is approved for `token_id` and `caller` is authorized to move it
    /// (token owner or an approved operator); returns the on-chain token owner. Shared by
    /// `transfer_token` and `batch_transfer` (was a duplicated approval/auth block).
    fn assert_token_transfer_authorized(
        ip_nft: IERC721Dispatcher,
        token_id: u256,
        caller: ContractAddress,
        registry: ContractAddress,
    ) -> ContractAddress {
        let token_owner = ip_nft.owner_of(token_id);
        let approved = ip_nft.get_approved(token_id);
        assert(
            approved == registry || ip_nft.is_approved_for_all(token_owner, registry),
            'Contract not approved',
        );
        assert(
            caller == token_owner
                || approved == caller
                || ip_nft.is_approved_for_all(token_owner, caller),
            'Not authorized',
        );
        token_owner
    }
}
