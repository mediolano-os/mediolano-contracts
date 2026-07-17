#[starknet::contract]
pub mod IPCollabCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{IIPCollabCollection, IIP_COLAB_COLLECTION_ID};
    use crate::types::{Contribution, ContributionStatus, ContributionType, bytearray_starts_with};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        base_uri: ByteArray,
        next_type_id: u256,
        next_contribution_id: u256,
        next_token_id: u256,
        types: Map<u256, ContributionType>,
        contributions: Map<u256, Contribution>,
        token_contributions: Map<u256, u256>,
        registered_at: Map<u256, u64>,
        archived: Map<u256, bool>,
        verifiers: Map<ContractAddress, bool>,
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
        ContributionTypeCreated: ContributionTypeCreated,
        ContributionSubmitted: ContributionSubmitted,
        ContributionApproved: ContributionApproved,
        ContributionRejected: ContributionRejected,
        ContributionMinted: ContributionMinted,
        TokenArchived: TokenArchived,
        VerifierAdded: VerifierAdded,
        VerifierRemoved: VerifierRemoved,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionTypeCreated {
        #[key]
        pub type_id: u256,
        pub max_supply: u256,
        pub submission_deadline: Option<u64>,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionSubmitted {
        #[key]
        pub contribution_id: u256,
        #[key]
        pub contributor: ContractAddress,
        pub type_id: u256,
        pub token_uri: ByteArray,
        pub royalty_bps: u16,
        pub submitted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionApproved {
        #[key]
        pub contribution_id: u256,
        pub verifier: ContractAddress,
        pub reviewed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionRejected {
        #[key]
        pub contribution_id: u256,
        pub verifier: ContractAddress,
        pub reviewed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionMinted {
        #[key]
        pub contribution_id: u256,
        #[key]
        pub token_id: u256,
        pub contributor: ContractAddress,
        pub minted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenArchived {
        #[key]
        pub token_id: u256,
        pub owner: ContractAddress,
        pub archived_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct VerifierAdded {
        #[key]
        pub verifier: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct VerifierRemoved {
        #[key]
        pub verifier: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        owner: ContractAddress,
    ) {
        assert(name.len() > 0, 'Name must not be empty');
        assert(symbol.len() > 0, 'Symbol must not be empty');
        assert(!owner.is_zero(), 'Owner is zero address');
        // token_uri resolves per token from the contribution record; the
        // ERC721 base is unused.
        self.erc721.initializer(name, symbol, "");
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_COLAB_COLLECTION_ID);
        self.src5.register_interface(IERC2981_ID);
        self.base_uri.write(base_uri);
        self.next_type_id.write(1);
        self.next_contribution_id.write(1);
        self.next_token_id.write(1);
    }

    /// Transfers of archived tokens are blocked; minting (from == 0) is the
    /// only update an archived token id can never see anyway.
    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let contract_state = self.get_contract();
            assert(!contract_state.archived.read(token_id), 'Token is archived');
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
    }

    /// Per-token metadata URI from the contribution record instead of
    /// base+id concatenation.
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
            let contribution = self.contributions.read(self.token_contributions.read(token_id));
            contribution.token_uri
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.token_uri(tokenId)
        }
    }

    #[abi(embed_v0)]
    pub impl IPCollabCollectionImpl of IIPCollabCollection<ContractState> {
        fn create_contribution_type(
            ref self: ContractState,
            max_supply: u256,
            submission_deadline: Option<u64>,
            metadata_uri: ByteArray,
        ) -> u256 {
            self.ownable.assert_only_owner();
            assert(max_supply > 0, 'Max supply is zero');
            assert_content_addressed(@metadata_uri);

            let type_id = self.next_type_id.read();
            self.next_type_id.write(type_id + 1);

            let contribution_type = ContributionType {
                max_supply,
                approved_count: 0,
                minted_count: 0,
                submission_deadline,
                metadata_uri: metadata_uri.clone(),
            };
            self.types.write(type_id, contribution_type);

            self
                .emit(
                    ContributionTypeCreated {
                        type_id,
                        max_supply,
                        submission_deadline,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            type_id
        }

        fn submit_contribution(
            ref self: ContractState, type_id: u256, token_uri: ByteArray, royalty_bps: u16,
        ) -> u256 {
            let contribution_type = self.get_existing_type(type_id);
            if let Option::Some(deadline) = contribution_type.submission_deadline {
                assert(get_block_timestamp() < deadline, 'Submissions closed');
            }
            assert_content_addressed(@token_uri);
            assert(royalty_bps <= 10000, 'Royalty exceeds 10000');

            let contributor = get_caller_address();
            let contribution_id = self.next_contribution_id.read();
            self.next_contribution_id.write(contribution_id + 1);

            let contribution = Contribution {
                contributor,
                type_id,
                token_uri: token_uri.clone(),
                royalty_bps,
                status: ContributionStatus::Pending,
                token_id: 0,
            };
            self.contributions.write(contribution_id, contribution);

            self
                .emit(
                    ContributionSubmitted {
                        contribution_id,
                        contributor,
                        type_id,
                        token_uri,
                        royalty_bps,
                        submitted_at: get_block_timestamp(),
                    },
                );

            contribution_id
        }

        fn approve_contribution(ref self: ContractState, contribution_id: u256) {
            let verifier = get_caller_address();
            self.assert_verifier(verifier);

            let mut contribution = self.get_existing_contribution(contribution_id);
            assert(contribution.status == ContributionStatus::Pending, 'Not pending');

            let mut contribution_type = self.get_existing_type(contribution.type_id);
            assert(
                contribution_type.approved_count < contribution_type.max_supply,
                'Max supply reached',
            );

            contribution_type.approved_count += 1;
            contribution.status = ContributionStatus::Approved;
            self.types.write(contribution.type_id, contribution_type);
            self.contributions.write(contribution_id, contribution);

            self
                .emit(
                    ContributionApproved {
                        contribution_id, verifier, reviewed_at: get_block_timestamp(),
                    },
                );
        }

        fn reject_contribution(ref self: ContractState, contribution_id: u256) {
            let verifier = get_caller_address();
            self.assert_verifier(verifier);

            let mut contribution = self.get_existing_contribution(contribution_id);
            assert(contribution.status == ContributionStatus::Pending, 'Not pending');

            contribution.status = ContributionStatus::Rejected;
            self.contributions.write(contribution_id, contribution);

            self
                .emit(
                    ContributionRejected {
                        contribution_id, verifier, reviewed_at: get_block_timestamp(),
                    },
                );
        }

        fn mint_contribution(ref self: ContractState, contribution_id: u256) -> u256 {
            let contributor = get_caller_address();

            let mut contribution = self.get_existing_contribution(contribution_id);
            assert(contribution.contributor == contributor, 'Only contributor');
            assert(contribution.status == ContributionStatus::Approved, 'Not approved');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            let mut contribution_type = self.get_existing_type(contribution.type_id);
            contribution_type.minted_count += 1;
            self.types.write(contribution.type_id, contribution_type);

            contribution.status = ContributionStatus::Minted;
            contribution.token_id = token_id;
            self.contributions.write(contribution_id, contribution);

            self.token_contributions.write(token_id, contribution_id);
            let minted_at = get_block_timestamp();
            self.registered_at.write(token_id, minted_at);

            self.erc721.safe_mint(contributor, token_id, array![].span());

            self.emit(ContributionMinted { contribution_id, token_id, contributor, minted_at });

            token_id
        }

        fn archive(ref self: ContractState, token_id: u256) {
            self.erc721._require_owned(token_id);
            let owner = self.erc721.ERC721_owners.read(token_id);
            assert(get_caller_address() == owner, 'Only token owner');
            assert(!self.archived.read(token_id), 'Already archived');

            self.archived.write(token_id, true);

            self.emit(TokenArchived { token_id, owner, archived_at: get_block_timestamp() });
        }

        fn add_verifier(ref self: ContractState, verifier: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!verifier.is_zero(), 'Verifier is zero');
            self.verifiers.write(verifier, true);
            self.emit(VerifierAdded { verifier });
        }

        fn remove_verifier(ref self: ContractState, verifier: ContractAddress) {
            self.ownable.assert_only_owner();
            self.verifiers.write(verifier, false);
            self.emit(VerifierRemoved { verifier });
        }

        fn is_verifier(self: @ContractState, verifier: ContractAddress) -> bool {
            self.verifiers.read(verifier) || verifier == self.ownable.owner()
        }

        fn is_archived(self: @ContractState, token_id: u256) -> bool {
            self.archived.read(token_id)
        }

        fn get_contribution(self: @ContractState, contribution_id: u256) -> Contribution {
            self.get_existing_contribution(contribution_id)
        }

        fn get_contribution_type(self: @ContractState, type_id: u256) -> ContributionType {
            self.get_existing_type(type_id)
        }

        fn contribution_count(self: @ContractState) -> u256 {
            self.next_contribution_id.read() - 1
        }

        fn type_count(self: @ContractState) -> u256 {
            self.next_type_id.read() - 1
        }

        fn get_token_contribution(self: @ContractState, token_id: u256) -> u256 {
            self.erc721._require_owned(token_id);
            self.token_contributions.read(token_id)
        }

        fn token_registered_at(self: @ContractState, token_id: u256) -> u64 {
            self.erc721._require_owned(token_id);
            self.registered_at.read(token_id)
        }

        fn base_uri(self: @ContractState) -> ByteArray {
            self.base_uri.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.erc721._require_owned(token_id);
            let contribution = self.contributions.read(self.token_contributions.read(token_id));
            let amount = (sale_price * contribution.royalty_bps.into()) / 10000;
            (contribution.contributor, amount)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.royalty_info(token_id, sale_price)
        }

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing_type(self: @ContractState, type_id: u256) -> ContributionType {
            let contribution_type = self.types.read(type_id);
            assert(contribution_type.max_supply > 0, 'Type not found');
            contribution_type
        }

        fn get_existing_contribution(self: @ContractState, contribution_id: u256) -> Contribution {
            let contribution = self.contributions.read(contribution_id);
            assert(!contribution.contributor.is_zero(), 'Contribution not found');
            contribution
        }

        fn assert_verifier(self: @ContractState, caller: ContractAddress) {
            assert(caller == self.ownable.owner() || self.verifiers.read(caller), 'Not a verifier');
        }
    }

    fn assert_content_addressed(uri: @ByteArray) {
        let valid_uri = bytearray_starts_with(uri, @"ipfs://")
            || bytearray_starts_with(uri, @"ar://");
        assert(valid_uri, 'URI must be ipfs:// or ar://');
    }
}
