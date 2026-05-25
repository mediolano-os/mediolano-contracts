// DESIGN: IPCollabCollection is a collaborative review registry that deploys a
// MIP-style IPNft ERC-721 contract and mints approved contributions through it.
// This keeps Medialane's production NFT shape: a registry-like contract controls
// minting, while the standalone IPNft contract holds ERC-721 ownership and
// immutable creator/timestamp provenance.

#[starknet::contract]
pub mod IPCollabCollection {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::interfaces::IIPCollaborativeCollection::{
        IIPCollaborativeCollection, IIP_COLLABORATIVE_COLLECTION_ID,
    };
    use crate::interfaces::IIPNft::{IIPNftDispatcher, IIPNftDispatcherTrait};
    use crate::types::{
        CollectionConfig, Contribution, ContributionType, STATUS_APPROVED, STATUS_ARCHIVED,
        STATUS_MINTED, STATUS_PENDING, STATUS_REJECTED, TokenData, URI_POLICY_CONTENT_ADDRESSED,
        bytearray_starts_with,
    };

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        collection_issuer: ContractAddress,
        ip_nft_class_hash: ClassHash,
        ip_nft: ContractAddress,
        next_token_id: u256,
        next_contribution_id: u256,
        token_contributions: Map<u256, u256>,
        contributions: Map<u256, Contribution>,
        contribution_types: Map<felt252, ContributionType>,
        type_registered: Map<felt252, bool>,
        type_approved_count: Map<felt252, u256>,
        type_minted_count: Map<felt252, u256>,
        contributor_to_contribution_count: Map<ContractAddress, u256>,
        contributor_contributions: Map<(ContractAddress, u256), u256>,
        verifiers: Map<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        BackingCollectionDeployed: BackingCollectionDeployed,
        ContributionTypeRegistered: ContributionTypeRegistered,
        ContributionSubmitted: ContributionSubmitted,
        ContributionApproved: ContributionApproved,
        ContributionRejected: ContributionRejected,
        ContributionMinted: ContributionMinted,
        ContributionTokenArchived: ContributionTokenArchived,
        VerifierAdded: VerifierAdded,
        VerifierRemoved: VerifierRemoved,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BackingCollectionDeployed {
        #[key]
        pub ip_nft: ContractAddress,
        pub name: ByteArray,
        pub symbol: ByteArray,
        pub base_uri: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionTypeRegistered {
        #[key]
        pub type_id: felt252,
        pub min_quality_score: u8,
        pub submission_deadline: u64,
        pub max_supply: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionSubmitted {
        #[key]
        pub contribution_id: u256,
        #[key]
        pub contributor: ContractAddress,
        pub token_uri: ByteArray,
        pub contribution_type: felt252,
        pub submitted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionApproved {
        #[key]
        pub contribution_id: u256,
        pub verifier: ContractAddress,
        pub quality_score: u8,
        pub reviewed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionRejected {
        #[key]
        pub contribution_id: u256,
        pub verifier: ContractAddress,
        pub quality_score: u8,
        pub reviewed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionMinted {
        #[key]
        pub contribution_id: u256,
        #[key]
        pub token_id: u256,
        pub ip_nft: ContractAddress,
        pub contributor: ContractAddress,
        pub token_uri: ByteArray,
        pub minted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionTokenArchived {
        #[key]
        pub contribution_id: u256,
        #[key]
        pub token_id: u256,
        pub ip_nft: ContractAddress,
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
        ip_nft_class_hash: ClassHash,
    ) {
        assert(!owner.is_zero(), 'Owner is zero address');
        assert(ip_nft_class_hash.into() != 0_felt252, 'Class hash is zero');

        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_COLLABORATIVE_COLLECTION_ID);
        self.collection_issuer.write(owner);
        self.ip_nft_class_hash.write(ip_nft_class_hash);
        self.next_token_id.write(1);
        self.next_contribution_id.write(1);
        self.verifiers.write(owner, true);

        let registry = get_contract_address();
        let collection_id: u256 = 1;
        let mut constructor_calldata: Array<felt252> = array![];
        (name.clone(), symbol.clone(), base_uri.clone(), collection_id, registry)
            .serialize(ref constructor_calldata);

        let (ip_nft, _) = deploy_syscall(ip_nft_class_hash, 0, constructor_calldata.span(), false)
            .unwrap();

        self.ip_nft.write(ip_nft);
        self.emit(BackingCollectionDeployed { ip_nft, name, symbol, base_uri });
    }

    #[abi(embed_v0)]
    impl IPCollaborativeCollectionImpl of IIPCollaborativeCollection<ContractState> {
        fn register_contribution_type(
            ref self: ContractState,
            type_id: felt252,
            min_quality_score: u8,
            submission_deadline: u64,
            max_supply: u256,
        ) {
            self.ownable.assert_only_owner();
            assert(type_id != 0, 'Type id is zero');
            assert(!self.type_registered.read(type_id), 'Type exists');
            assert(max_supply > 0, 'Max supply is zero');

            let type_info = ContributionType {
                type_id,
                min_quality_score,
                submission_deadline,
                max_supply,
                approved_count: 0,
                minted_count: 0,
                exists: true,
            };
            self.contribution_types.write(type_id, type_info);
            self.type_registered.write(type_id, true);

            self
                .emit(
                    ContributionTypeRegistered {
                        type_id, min_quality_score, submission_deadline, max_supply,
                    },
                );
        }

        fn submit_contribution(
            ref self: ContractState, token_uri: ByteArray, contribution_type: felt252,
        ) -> u256 {
            assert(self.type_registered.read(contribution_type), 'Type missing');

            let type_info = self.contribution_types.read(contribution_type);
            let current_time = get_block_timestamp();
            assert(current_time <= type_info.submission_deadline, 'Deadline passed');
            self.assert_valid_uri(@token_uri);

            let contributor = get_caller_address();
            assert(!contributor.is_zero(), 'Contributor is zero');

            let contribution_id = self.next_contribution_id.read();
            self.next_contribution_id.write(contribution_id + 1);

            let contribution = Contribution {
                contribution_id,
                contributor,
                token_uri: token_uri.clone(),
                contribution_type,
                quality_score: 0,
                submitted_at: current_time,
                reviewed_at: 0,
                minted_at: 0,
                status: STATUS_PENDING,
                token_id: 0,
            };

            self.contributions.write(contribution_id, contribution);

            let current_count = self.contributor_to_contribution_count.read(contributor);
            let new_count = current_count + 1;
            self.contributor_contributions.write((contributor, new_count), contribution_id);
            self.contributor_to_contribution_count.write(contributor, new_count);

            self
                .emit(
                    ContributionSubmitted {
                        contribution_id,
                        contributor,
                        token_uri,
                        contribution_type,
                        submitted_at: current_time,
                    },
                );

            contribution_id
        }

        fn approve_contribution(ref self: ContractState, contribution_id: u256, quality_score: u8) {
            let verifier = get_caller_address();
            self.assert_verifier_or_owner(verifier);
            self.assert_contribution_exists(contribution_id);

            let contribution = self.contributions.read(contribution_id);
            assert(contribution.status == STATUS_PENDING, 'Not pending');

            let type_info = self.contribution_types.read(contribution.contribution_type);
            assert(quality_score >= type_info.min_quality_score, 'Quality too low');

            let current_approved = self.type_approved_count.read(contribution.contribution_type);
            assert(current_approved < type_info.max_supply, 'Max supply reached');

            let reviewed_at = get_block_timestamp();
            let updated = Contribution {
                quality_score, reviewed_at, status: STATUS_APPROVED, ..contribution,
            };
            self.contributions.write(contribution_id, updated);
            self.type_approved_count.write(contribution.contribution_type, current_approved + 1);

            let minted_count = self.type_minted_count.read(contribution.contribution_type);
            let updated_type = ContributionType {
                approved_count: current_approved + 1, minted_count, ..type_info,
            };
            self.contribution_types.write(contribution.contribution_type, updated_type);

            self
                .emit(
                    ContributionApproved { contribution_id, verifier, quality_score, reviewed_at },
                );
        }

        fn reject_contribution(ref self: ContractState, contribution_id: u256, quality_score: u8) {
            let verifier = get_caller_address();
            self.assert_verifier_or_owner(verifier);
            self.assert_contribution_exists(contribution_id);

            let contribution = self.contributions.read(contribution_id);
            assert(contribution.status == STATUS_PENDING, 'Not pending');

            let reviewed_at = get_block_timestamp();
            let updated = Contribution {
                quality_score, reviewed_at, status: STATUS_REJECTED, ..contribution,
            };
            self.contributions.write(contribution_id, updated);

            self
                .emit(
                    ContributionRejected { contribution_id, verifier, quality_score, reviewed_at },
                );
        }

        fn mint_contribution(ref self: ContractState, contribution_id: u256) -> u256 {
            self.assert_contribution_exists(contribution_id);

            let contribution = self.contributions.read(contribution_id);
            let caller = get_caller_address();
            assert(caller == contribution.contributor, 'Only contributor');
            assert(contribution.status == STATUS_APPROVED, 'Not approved');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            let ip_nft_address = self.ip_nft.read();
            let ip_nft = IIPNftDispatcher { contract_address: ip_nft_address };
            ip_nft
                .mint(
                    contribution.contributor,
                    token_id,
                    contribution.token_uri.clone(),
                    contribution.contributor,
                );
            self.token_contributions.write(token_id, contribution_id);

            let minted_at = get_block_timestamp();
            let contribution_type = contribution.contribution_type;
            let contributor = contribution.contributor;
            let event_uri = contribution.token_uri.clone();
            let updated = Contribution {
                status: STATUS_MINTED, token_id, minted_at, ..contribution,
            };
            self.contributions.write(contribution_id, updated);

            let minted_count = self.type_minted_count.read(contribution_type) + 1;
            self.type_minted_count.write(contribution_type, minted_count);

            let type_info = self.contribution_types.read(contribution_type);
            let updated_type = ContributionType { minted_count, ..type_info };
            self.contribution_types.write(contribution_type, updated_type);

            self
                .emit(
                    ContributionMinted {
                        contribution_id,
                        token_id,
                        ip_nft: ip_nft_address,
                        contributor,
                        token_uri: event_uri,
                        minted_at,
                    },
                );

            token_id
        }

        fn archive_contribution_token(ref self: ContractState, token_id: u256) {
            let ip_nft_address = self.ip_nft.read();
            let ip_nft = IIPNftDispatcher { contract_address: ip_nft_address };
            let (owner, _, _, _) = ip_nft.get_full_token_data(token_id);
            assert(get_caller_address() == owner, 'Only token owner');

            let contribution_id = self.token_contributions.read(token_id);
            assert(contribution_id > 0, 'Contribution missing');

            let contribution = self.contributions.read(contribution_id);
            assert(contribution.status == STATUS_MINTED, 'Not minted');

            ip_nft.archive(token_id);

            let archived_at = get_block_timestamp();
            let updated = Contribution { status: STATUS_ARCHIVED, ..contribution };
            self.contributions.write(contribution_id, updated);

            self
                .emit(
                    ContributionTokenArchived {
                        contribution_id, token_id, ip_nft: ip_nft_address, owner, archived_at,
                    },
                );
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

        fn get_collection_issuer(self: @ContractState) -> ContractAddress {
            self.collection_issuer.read()
        }

        fn get_ip_nft(self: @ContractState) -> ContractAddress {
            self.ip_nft.read()
        }

        fn get_uri_policy(self: @ContractState) -> felt252 {
            URI_POLICY_CONTENT_ADDRESSED
        }

        fn get_collection_config(self: @ContractState) -> CollectionConfig {
            CollectionConfig {
                owner: self.ownable.owner(),
                collection_issuer: self.collection_issuer.read(),
                ip_nft: self.ip_nft.read(),
                ip_nft_class_hash: self.ip_nft_class_hash.read(),
                total_contributions: self.next_contribution_id.read() - 1,
                total_minted: self.next_token_id.read() - 1,
                uri_policy: URI_POLICY_CONTENT_ADDRESSED,
            }
        }

        fn get_contribution(self: @ContractState, contribution_id: u256) -> Contribution {
            self.assert_contribution_exists(contribution_id);
            self.contributions.read(contribution_id)
        }

        fn get_contribution_type(self: @ContractState, type_id: felt252) -> ContributionType {
            assert(self.type_registered.read(type_id), 'Type missing');
            self.contribution_types.read(type_id)
        }

        fn get_contributions_count(self: @ContractState) -> u256 {
            self.next_contribution_id.read() - 1
        }

        fn get_contributor_contributions(
            self: @ContractState, contributor: ContractAddress,
        ) -> Array<u256> {
            let count = self.contributor_to_contribution_count.read(contributor);
            let mut contributions = array![];

            let mut i: u256 = 1;
            loop {
                if i > count {
                    break;
                }
                contributions.append(self.contributor_contributions.read((contributor, i)));
                i += 1;
            }

            contributions
        }

        fn get_token_contribution(self: @ContractState, token_id: u256) -> u256 {
            let exists = IIPNftDispatcher { contract_address: self.ip_nft.read() }
                .token_exists(token_id);
            assert(exists, 'Token missing');
            self.token_contributions.read(token_id)
        }

        fn get_token_contributor(self: @ContractState, token_id: u256) -> ContractAddress {
            let ip_nft = IIPNftDispatcher { contract_address: self.ip_nft.read() };
            ip_nft.get_token_creator(token_id)
        }

        fn get_token_registered_at(self: @ContractState, token_id: u256) -> u64 {
            let ip_nft = IIPNftDispatcher { contract_address: self.ip_nft.read() };
            ip_nft.get_token_registered_at(token_id)
        }

        fn get_token_data(self: @ContractState, token_id: u256) -> TokenData {
            let ip_nft_address = self.ip_nft.read();
            let ip_nft = IIPNftDispatcher { contract_address: ip_nft_address };
            let (owner, metadata_uri, contributor, registered_at) = ip_nft
                .get_full_token_data(token_id);
            TokenData {
                ip_nft: ip_nft_address,
                token_id,
                contribution_id: self.get_token_contribution(token_id),
                owner,
                metadata_uri,
                contributor,
                registered_at,
            }
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn assert_valid_uri(self: @ContractState, token_uri: @ByteArray) {
            let valid_uri = bytearray_starts_with(token_uri, @"ipfs://")
                || bytearray_starts_with(token_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');
        }

        fn assert_contribution_exists(self: @ContractState, contribution_id: u256) {
            assert(contribution_id > 0, 'Contribution missing');
            assert(contribution_id < self.next_contribution_id.read(), 'Contribution missing');
        }

        fn assert_verifier_or_owner(self: @ContractState, caller: ContractAddress) {
            let owner = self.ownable.owner();
            assert(caller == owner || self.verifiers.read(caller), 'Not verifier');
        }
    }
}
