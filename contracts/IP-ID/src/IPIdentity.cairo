use starknet::ContractAddress;

pub const RELATION_VERSION: felt252 = 'VERSION';
pub const RELATION_DERIVATIVE: felt252 = 'DERIVATIVE';
pub const ATTESTATION_PROVENANCE: felt252 = 'PROVENANCE';
pub const ATTESTATION_CREATOR_SIGNATURE: felt252 = 'CREATOR_SIGNATURE';
pub const ATTESTATION_EXTERNAL_REGISTRY: felt252 = 'EXTERNAL_REGISTRY';
pub const ATTESTATION_LEGAL_PROOF: felt252 = 'LEGAL_PROOF';
pub const ATTESTATION_VERIFICATION: felt252 = 'VERIFICATION';
pub const ATTESTATION_CONFIRM: felt252 = 'CONFIRM';
pub const ATTESTATION_DISPUTE: felt252 = 'DISPUTE';
// Reserved seam: "this state/work was anchored on chain X at height N"
// (Bitcoin proof-of-existence, roadmap Horizon). No contract logic reads it.
pub const ATTESTATION_ANCHOR: felt252 = 'ANCHOR';

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Work {
    pub controller: ContractAddress,
    pub creator: ContractAddress,
    pub metadata_uri: ByteArray,
    pub metadata_hash: felt252,
    pub created_at: u64,
    pub representation_count: u256,
    pub relation_count: u256,
    pub attestation_count: u256,
    pub exists: bool,
}

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Representation {
    pub ip_id: felt252,
    pub chain_id: felt252,
    pub representation_key: felt252,
    pub asset_locator: felt252,
    pub token_id: u256,
    pub content_id: felt252,
    pub metadata_uri: ByteArray,
    pub metadata_hash: felt252,
    pub standard: felt252,
    pub linked_at: u64,
    pub linked_by: ContractAddress,
}

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Relation {
    pub ip_id: felt252,
    pub relation_key: felt252,
    pub related_ip_id: felt252,
    pub relation_type: felt252,
    pub asserted_at: u64,
    pub asserted_by: ContractAddress,
}

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Attestation {
    pub ip_id: felt252,
    pub attestation_id: u256,
    pub subject_key: felt252,
    pub attester: ContractAddress,
    pub attestation_type: felt252,
    pub data_hash: felt252,
    pub uri: ByteArray,
    pub created_at: u64,
}

#[starknet::interface]
pub trait IIPIdentity<TContractState> {
    fn register_work(
        ref self: TContractState, metadata_uri: ByteArray, metadata_hash: felt252, salt: felt252,
    ) -> felt252;

    fn reveal(ref self: TContractState, ip_id: felt252, metadata_uri: ByteArray);

    fn link_representation(
        ref self: TContractState,
        ip_id: felt252,
        chain_id: felt252,
        asset_locator: felt252,
        token_id: u256,
        content_id: felt252,
        metadata_uri: ByteArray,
        metadata_hash: felt252,
        standard: felt252,
    );

    fn transfer_controller(
        ref self: TContractState, ip_id: felt252, new_controller: ContractAddress,
    );

    fn attest(
        ref self: TContractState,
        ip_id: felt252,
        subject_key: felt252,
        attestation_type: felt252,
        data_hash: felt252,
        uri: ByteArray,
    ) -> u256;

    fn relate(
        ref self: TContractState, ip_id: felt252, related_ip_id: felt252, relation_type: felt252,
    ) -> felt252;

    fn get_work(self: @TContractState, ip_id: felt252) -> Work;
    fn get_relation(self: @TContractState, relation_key: felt252) -> Relation;
    fn get_relation_ip_id(self: @TContractState, relation_key: felt252) -> felt252;
    fn get_work_relation_key(self: @TContractState, ip_id: felt252, index: u256) -> felt252;
    fn is_relation_asserted(self: @TContractState, relation_key: felt252) -> bool;
    fn derive_relation_key(
        self: @TContractState, ip_id: felt252, related_ip_id: felt252, relation_type: felt252,
    ) -> felt252;
    fn get_representation(self: @TContractState, representation_key: felt252) -> Representation;
    fn get_attestation(self: @TContractState, ip_id: felt252, attestation_id: u256) -> Attestation;
    fn get_representation_ip_id(self: @TContractState, representation_key: felt252) -> felt252;
    fn get_work_representation_key(self: @TContractState, ip_id: felt252, index: u256) -> felt252;
    fn is_work_registered(self: @TContractState, ip_id: felt252) -> bool;
    fn is_representation_linked(self: @TContractState, representation_key: felt252) -> bool;
    fn registered_count(self: @TContractState) -> u256;
    fn derive_ip_id(
        self: @TContractState, creator: ContractAddress, metadata_hash: felt252, salt: felt252,
    ) -> felt252;
    fn derive_representation_key(
        self: @TContractState,
        chain_id: felt252,
        asset_locator: felt252,
        token_id: u256,
        content_id: felt252,
        standard: felt252,
    ) -> felt252;
}

#[starknet::contract]
pub mod IPIdentity {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::{Attestation, IIPIdentity, Relation, Representation, Work};

    const ERROR_INVALID_WORK: felt252 = 'IPID: invalid work';
    const ERROR_NOT_CONTROLLER: felt252 = 'IPID: not controller';
    const ERROR_ALREADY_REGISTERED: felt252 = 'IPID: already registered';
    const ERROR_REPRESENTATION_LINKED: felt252 = 'IPID: representation linked';
    const ERROR_INVALID_REPRESENTATION: felt252 = 'IPID: invalid representation';
    const ERROR_INVALID_CONTROLLER: felt252 = 'IPID: invalid controller';
    const ERROR_INVALID_ATTESTATION: felt252 = 'IPID: invalid attestation';
    const ERROR_INVALID_METADATA: felt252 = 'IPID: invalid metadata';
    const ERROR_INVALID_RELATION: felt252 = 'IPID: invalid relation';
    const ERROR_RELATION_ASSERTED: felt252 = 'IPID: relation asserted';
    const ERROR_SELF_RELATION: felt252 = 'IPID: self relation';
    const ERROR_INVALID_SUBJECT: felt252 = 'IPID: invalid subject';
    const ERROR_ALREADY_REVEALED: felt252 = 'IPID: already revealed';

    #[storage]
    struct Storage {
        registered_count: u256,
        works: Map<felt252, Work>,
        representation_to_ip_id: Map<felt252, felt252>,
        representations: Map<felt252, Representation>,
        work_representations: Map<(felt252, u256), felt252>,
        relation_to_ip_id: Map<felt252, felt252>,
        relations: Map<felt252, Relation>,
        work_relations: Map<(felt252, u256), felt252>,
        attestations: Map<(felt252, u256), Attestation>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        WorkRegistered: WorkRegistered,
        WorkRevealed: WorkRevealed,
        RepresentationLinked: RepresentationLinked,
        RelationAsserted: RelationAsserted,
        ControllerTransferred: ControllerTransferred,
        WorkAttested: WorkAttested,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WorkRegistered {
        #[key]
        pub ip_id: felt252,
        #[key]
        pub creator: ContractAddress,
        pub controller: ContractAddress,
        pub metadata_hash: felt252,
        pub salt: felt252,
        pub metadata_uri: ByteArray,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WorkRevealed {
        #[key]
        pub ip_id: felt252,
        pub metadata_uri: ByteArray,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RepresentationLinked {
        #[key]
        pub ip_id: felt252,
        #[key]
        pub representation_key: felt252,
        pub chain_id: felt252,
        pub asset_locator: felt252,
        pub token_id: u256,
        pub content_id: felt252,
        pub metadata_hash: felt252,
        pub standard: felt252,
        pub linked_by: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RelationAsserted {
        #[key]
        pub ip_id: felt252,
        #[key]
        pub relation_key: felt252,
        pub related_ip_id: felt252,
        pub relation_type: felt252,
        pub asserted_by: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ControllerTransferred {
        #[key]
        pub ip_id: felt252,
        pub previous_controller: ContractAddress,
        pub new_controller: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WorkAttested {
        #[key]
        pub ip_id: felt252,
        pub attestation_id: u256,
        pub subject_key: felt252,
        pub attester: ContractAddress,
        pub attestation_type: felt252,
        pub data_hash: felt252,
        pub uri: ByteArray,
        pub timestamp: u64,
    }

    #[abi(embed_v0)]
    impl IPIdentityImpl of IIPIdentity<ContractState> {
        fn register_work(
            ref self: ContractState, metadata_uri: ByteArray, metadata_hash: felt252, salt: felt252,
        ) -> felt252 {
            assert(metadata_hash != 0, ERROR_INVALID_METADATA);

            let creator = get_caller_address();
            let ip_id = self.derive_ip_id(creator, metadata_hash, salt);
            assert(!self.works.read(ip_id).exists, ERROR_ALREADY_REGISTERED);

            let timestamp = get_block_timestamp();
            let work = Work {
                controller: creator,
                creator,
                metadata_uri: metadata_uri.clone(),
                metadata_hash,
                created_at: timestamp,
                representation_count: 0,
                relation_count: 0,
                attestation_count: 0,
                exists: true,
            };

            self.works.write(ip_id, work);
            self.registered_count.write(self.registered_count.read() + 1);

            self
                .emit(
                    WorkRegistered {
                        ip_id,
                        creator,
                        controller: creator,
                        metadata_hash,
                        salt,
                        metadata_uri,
                        timestamp,
                    },
                );

            ip_id
        }

        fn reveal(ref self: ContractState, ip_id: felt252, metadata_uri: ByteArray) {
            let mut work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);

            let caller = get_caller_address();
            assert(caller == work.controller, ERROR_NOT_CONTROLLER);
            assert(work.metadata_uri.len() == 0, ERROR_ALREADY_REVEALED);
            assert(metadata_uri.len() != 0, ERROR_INVALID_METADATA);

            work.metadata_uri = metadata_uri.clone();
            self.works.write(ip_id, work);

            self.emit(WorkRevealed { ip_id, metadata_uri, timestamp: get_block_timestamp() });
        }

        fn link_representation(
            ref self: ContractState,
            ip_id: felt252,
            chain_id: felt252,
            asset_locator: felt252,
            token_id: u256,
            content_id: felt252,
            metadata_uri: ByteArray,
            metadata_hash: felt252,
            standard: felt252,
        ) {
            let mut work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);

            let caller = get_caller_address();
            assert(caller == work.controller, ERROR_NOT_CONTROLLER);
            assert(chain_id != 0, ERROR_INVALID_REPRESENTATION);
            assert(asset_locator != 0 || content_id != 0, ERROR_INVALID_REPRESENTATION);
            assert(metadata_hash != 0, ERROR_INVALID_METADATA);
            assert(standard != 0, ERROR_INVALID_REPRESENTATION);
            let representation_key = self
                .derive_representation_key(chain_id, asset_locator, token_id, content_id, standard);
            assert(representation_key != 0, ERROR_INVALID_REPRESENTATION);
            assert(
                self.representation_to_ip_id.read(representation_key).is_zero(),
                ERROR_REPRESENTATION_LINKED,
            );

            let timestamp = get_block_timestamp();
            let representation = Representation {
                ip_id,
                chain_id,
                representation_key,
                asset_locator,
                token_id,
                content_id,
                metadata_uri,
                metadata_hash,
                standard,
                linked_at: timestamp,
                linked_by: caller,
            };

            self.representation_to_ip_id.write(representation_key, ip_id);
            self.representations.write(representation_key, representation);
            self.work_representations.write((ip_id, work.representation_count), representation_key);
            work.representation_count += 1;
            self.works.write(ip_id, work);

            self
                .emit(
                    RepresentationLinked {
                        ip_id,
                        representation_key,
                        chain_id,
                        asset_locator,
                        token_id,
                        content_id,
                        metadata_hash,
                        standard,
                        linked_by: caller,
                        timestamp,
                    },
                );
        }

        fn relate(
            ref self: ContractState, ip_id: felt252, related_ip_id: felt252, relation_type: felt252,
        ) -> felt252 {
            let mut work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);

            let caller = get_caller_address();
            assert(caller == work.controller, ERROR_NOT_CONTROLLER);
            assert(relation_type != 0, ERROR_INVALID_RELATION);
            assert(ip_id != related_ip_id, ERROR_SELF_RELATION);
            assert(self.works.read(related_ip_id).exists, ERROR_INVALID_WORK);

            let relation_key = self.derive_relation_key(ip_id, related_ip_id, relation_type);
            assert(self.relation_to_ip_id.read(relation_key).is_zero(), ERROR_RELATION_ASSERTED);

            let timestamp = get_block_timestamp();
            let relation = Relation {
                ip_id,
                relation_key,
                related_ip_id,
                relation_type,
                asserted_at: timestamp,
                asserted_by: caller,
            };

            self.relation_to_ip_id.write(relation_key, ip_id);
            self.relations.write(relation_key, relation);
            self.work_relations.write((ip_id, work.relation_count), relation_key);
            work.relation_count += 1;
            self.works.write(ip_id, work);

            self
                .emit(
                    RelationAsserted {
                        ip_id,
                        relation_key,
                        related_ip_id,
                        relation_type,
                        asserted_by: caller,
                        timestamp,
                    },
                );

            relation_key
        }

        fn transfer_controller(
            ref self: ContractState, ip_id: felt252, new_controller: ContractAddress,
        ) {
            let mut work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);

            let caller = get_caller_address();
            assert(caller == work.controller, ERROR_NOT_CONTROLLER);
            assert(new_controller != Zero::zero(), ERROR_INVALID_CONTROLLER);

            let previous_controller = work.controller;
            work.controller = new_controller;
            self.works.write(ip_id, work);

            self
                .emit(
                    ControllerTransferred {
                        ip_id,
                        previous_controller,
                        new_controller,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        fn attest(
            ref self: ContractState,
            ip_id: felt252,
            subject_key: felt252,
            attestation_type: felt252,
            data_hash: felt252,
            uri: ByteArray,
        ) -> u256 {
            let mut work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);
            assert(attestation_type != 0, ERROR_INVALID_ATTESTATION);
            assert(data_hash != 0, ERROR_INVALID_ATTESTATION);

            if subject_key != 0 {
                let subject_owner = if self
                    .representation_to_ip_id
                    .read(subject_key)
                    .is_non_zero() {
                    self.representation_to_ip_id.read(subject_key)
                } else {
                    self.relation_to_ip_id.read(subject_key)
                };
                assert(subject_owner == ip_id, ERROR_INVALID_SUBJECT);
            }

            let attester = get_caller_address();
            let attestation_id = work.attestation_count + 1;
            let timestamp = get_block_timestamp();
            let attestation = Attestation {
                ip_id,
                attestation_id,
                subject_key,
                attester,
                attestation_type,
                data_hash,
                uri: uri.clone(),
                created_at: timestamp,
            };

            // Attestations are stored and addressed by their 1-based id, so the id
            // returned by `attest` can be passed straight back into `get_attestation`.
            self.attestations.write((ip_id, attestation_id), attestation);
            work.attestation_count = attestation_id;
            self.works.write(ip_id, work);

            self
                .emit(
                    WorkAttested {
                        ip_id,
                        attestation_id,
                        subject_key,
                        attester,
                        attestation_type,
                        data_hash,
                        uri,
                        timestamp,
                    },
                );

            attestation_id
        }

        fn get_work(self: @ContractState, ip_id: felt252) -> Work {
            let work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);
            work
        }

        fn get_representation(self: @ContractState, representation_key: felt252) -> Representation {
            assert(
                self.representation_to_ip_id.read(representation_key).is_non_zero(),
                ERROR_INVALID_REPRESENTATION,
            );
            self.representations.read(representation_key)
        }

        fn get_attestation(
            self: @ContractState, ip_id: felt252, attestation_id: u256,
        ) -> Attestation {
            let work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);
            assert(
                attestation_id != 0 && attestation_id <= work.attestation_count,
                ERROR_INVALID_ATTESTATION,
            );
            self.attestations.read((ip_id, attestation_id))
        }

        fn get_relation(self: @ContractState, relation_key: felt252) -> Relation {
            assert(self.relation_to_ip_id.read(relation_key).is_non_zero(), ERROR_INVALID_RELATION);
            self.relations.read(relation_key)
        }

        fn get_relation_ip_id(self: @ContractState, relation_key: felt252) -> felt252 {
            self.relation_to_ip_id.read(relation_key)
        }

        fn get_work_relation_key(self: @ContractState, ip_id: felt252, index: u256) -> felt252 {
            let work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);
            assert(index < work.relation_count, ERROR_INVALID_RELATION);
            self.work_relations.read((ip_id, index))
        }

        fn is_relation_asserted(self: @ContractState, relation_key: felt252) -> bool {
            self.relation_to_ip_id.read(relation_key).is_non_zero()
        }

        fn derive_relation_key(
            self: @ContractState, ip_id: felt252, related_ip_id: felt252, relation_type: felt252,
        ) -> felt252 {
            PoseidonTrait::new()
                .update_with('IPID_RELATION_V1')
                .update_with(ip_id)
                .update_with(related_ip_id)
                .update_with(relation_type)
                .finalize()
        }

        fn get_representation_ip_id(self: @ContractState, representation_key: felt252) -> felt252 {
            self.representation_to_ip_id.read(representation_key)
        }

        fn get_work_representation_key(
            self: @ContractState, ip_id: felt252, index: u256,
        ) -> felt252 {
            let work = self.works.read(ip_id);
            assert(work.exists, ERROR_INVALID_WORK);
            assert(index < work.representation_count, ERROR_INVALID_REPRESENTATION);
            self.work_representations.read((ip_id, index))
        }

        fn is_work_registered(self: @ContractState, ip_id: felt252) -> bool {
            self.works.read(ip_id).exists
        }

        fn is_representation_linked(self: @ContractState, representation_key: felt252) -> bool {
            self.representation_to_ip_id.read(representation_key).is_non_zero()
        }

        fn registered_count(self: @ContractState) -> u256 {
            self.registered_count.read()
        }

        fn derive_ip_id(
            self: @ContractState, creator: ContractAddress, metadata_hash: felt252, salt: felt252,
        ) -> felt252 {
            PoseidonTrait::new()
                .update_with('IPID_WORK_V1')
                .update_with(creator)
                .update_with(metadata_hash)
                .update_with(salt)
                .finalize()
        }

        fn derive_representation_key(
            self: @ContractState,
            chain_id: felt252,
            asset_locator: felt252,
            token_id: u256,
            content_id: felt252,
            standard: felt252,
        ) -> felt252 {
            PoseidonTrait::new()
                .update_with('IPID_REPRESENTATION_V1')
                .update_with(chain_id)
                .update_with(asset_locator)
                .update_with(token_id)
                .update_with(content_id)
                .update_with(standard)
                .finalize()
        }
    }
}
