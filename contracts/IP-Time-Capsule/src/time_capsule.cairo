// DESIGN: IPTimeCapsule is a permissionless, immutable ERC-721 service for
// delayed disclosure. The contract never stores plaintext reveal metadata before
// unlock; it stores a content-addressed encrypted pointer plus a commitment, then
// allows the creator or current owner to publish the revealed URI after reveal_at.
// The commitment scheme is Poseidon(content_hash, content_salt).
//
// Cairo contracts cannot provide secrecy for values written to chain storage.
// Privacy comes from keeping plaintext off-chain until reveal and using the
// on-chain commitment as the permanent audit trail.

#[starknet::contract]
pub mod IPTimeCapsule {
    use core::num::traits::Zero;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interfaces::{IIP_TIME_CAPSULE_ID, ITimeCapsule};
    use crate::types::{
        COMMITMENT_SCHEME_POSEIDON_HASH_SALT, MAX_NAME_LEN, MAX_SYMBOL_LEN, MAX_URI_LEN,
        TimeCapsule, TimeCapsuleData, compute_content_commitment, is_supported_uri,
    };

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        next_token_id: u256,
        hidden_uri: ByteArray,
        max_lock_duration: u64,
        capsules: Map<u256, TimeCapsule>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        TimeCapsuleMinted: TimeCapsuleMinted,
        TimeCapsuleRevealed: TimeCapsuleRevealed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TimeCapsuleMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub recipient: ContractAddress,
        #[key]
        pub creator: ContractAddress,
        pub encrypted_uri: ByteArray,
        pub content_commitment: felt252,
        pub reveal_at: u64,
        pub minted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TimeCapsuleRevealed {
        #[key]
        pub token_id: u256,
        #[key]
        pub revealer: ContractAddress,
        pub revealed_uri: ByteArray,
        pub content_hash: felt252,
        pub content_salt: felt252,
        pub revealed_at: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        hidden_uri: ByteArray,
        max_lock_duration: u64,
    ) {
        assert(name.len() > 0 && name.len() <= MAX_NAME_LEN, 'Invalid name');
        assert(symbol.len() > 0 && symbol.len() <= MAX_SYMBOL_LEN, 'Invalid symbol');
        assert(
            hidden_uri.len() <= MAX_URI_LEN && is_supported_uri(@hidden_uri), 'Invalid hidden URI',
        );
        assert(max_lock_duration > 0, 'Invalid max lock');

        self.erc721.initializer(name, symbol, "");
        self.src5.register_interface(IIP_TIME_CAPSULE_ID);
        self.hidden_uri.write(hidden_uri);
        self.max_lock_duration.write(max_lock_duration);
        self.next_token_id.write(1);
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
            let capsule = self.capsules.read(token_id);
            if capsule.revealed_at != 0 {
                capsule.revealed_uri
            } else {
                self.hidden_uri.read()
            }
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            let capsule = self.capsules.read(tokenId);
            if capsule.revealed_at != 0 {
                capsule.revealed_uri
            } else {
                self.hidden_uri.read()
            }
        }
    }

    #[abi(embed_v0)]
    impl IPTimeCapsuleImpl of ITimeCapsule<ContractState> {
        fn mint_capsule(
            ref self: ContractState,
            recipient: ContractAddress,
            encrypted_uri: ByteArray,
            content_commitment: felt252,
            reveal_at: u64,
        ) -> u256 {
            let creator = get_caller_address();
            assert(!creator.is_zero(), 'Creator is zero address');
            assert(!recipient.is_zero(), 'Recipient is zero address');
            assert(
                encrypted_uri.len() <= MAX_URI_LEN && is_supported_uri(@encrypted_uri),
                'Invalid encrypted URI',
            );
            assert(content_commitment != 0, 'Empty commitment');

            let now = get_block_timestamp();
            assert(reveal_at > now, 'Reveal must be future');
            assert(reveal_at <= now + self.max_lock_duration.read(), 'Reveal exceeds max lock');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            // Capsule state must be final before safe_mint: the receiver
            // callback is an external call, and a reentrant observer must
            // never see a minted token with an empty capsule record.
            self
                .capsules
                .write(
                    token_id,
                    TimeCapsule {
                        creator,
                        encrypted_uri: encrypted_uri.clone(),
                        content_commitment,
                        reveal_at,
                        revealed_uri: "",
                        revealed_at: 0,
                        content_hash: 0,
                    },
                );

            self.erc721.safe_mint(recipient, token_id, array![].span());

            self
                .emit(
                    TimeCapsuleMinted {
                        token_id,
                        recipient,
                        creator,
                        encrypted_uri,
                        content_commitment,
                        reveal_at,
                        minted_at: now,
                    },
                );

            token_id
        }

        fn reveal_capsule(
            ref self: ContractState,
            token_id: u256,
            revealed_uri: ByteArray,
            content_hash: felt252,
            content_salt: felt252,
        ) {
            self.erc721._require_owned(token_id);
            let capsule = self.capsules.read(token_id);
            assert(capsule.revealed_at == 0, 'Already revealed');

            let now = get_block_timestamp();
            assert(now >= capsule.reveal_at, 'Not unlocked');

            let caller = get_caller_address();
            let owner = self.erc721.ERC721_owners.read(token_id);
            assert(caller == capsule.creator || caller == owner, 'Not authorized');

            assert(
                revealed_uri.len() <= MAX_URI_LEN && is_supported_uri(@revealed_uri),
                'Invalid revealed URI',
            );
            assert(content_hash != 0, 'Empty content hash');
            assert(content_salt != 0, 'Empty content salt');
            assert(
                compute_content_commitment(content_hash, content_salt) == capsule
                    .content_commitment,
                'Commitment mismatch',
            );

            self
                .capsules
                .write(
                    token_id,
                    TimeCapsule {
                        creator: capsule.creator,
                        encrypted_uri: capsule.encrypted_uri,
                        content_commitment: capsule.content_commitment,
                        reveal_at: capsule.reveal_at,
                        revealed_uri: revealed_uri.clone(),
                        revealed_at: now,
                        content_hash,
                    },
                );

            self
                .emit(
                    TimeCapsuleRevealed {
                        token_id,
                        revealer: caller,
                        revealed_uri,
                        content_hash,
                        content_salt,
                        revealed_at: now,
                    },
                );
        }

        fn get_capsule_data(self: @ContractState, token_id: u256) -> TimeCapsuleData {
            self.erc721._require_owned(token_id);
            let capsule = self.capsules.read(token_id);
            TimeCapsuleData {
                token_id,
                owner: self.erc721.ERC721_owners.read(token_id),
                creator: capsule.creator,
                encrypted_uri: capsule.encrypted_uri,
                content_commitment: capsule.content_commitment,
                reveal_at: capsule.reveal_at,
                revealed_uri: capsule.revealed_uri,
                revealed_at: capsule.revealed_at,
                content_hash: capsule.content_hash,
                revealed: capsule.revealed_at != 0,
            }
        }

        fn get_encrypted_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            self.capsules.read(token_id).encrypted_uri
        }

        fn get_revealed_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            let capsule = self.capsules.read(token_id);
            assert(capsule.revealed_at != 0, 'Not revealed');
            capsule.revealed_uri
        }

        fn get_token_creator(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._require_owned(token_id);
            self.capsules.read(token_id).creator
        }

        fn get_token_reveal_at(self: @ContractState, token_id: u256) -> u64 {
            self.erc721._require_owned(token_id);
            self.capsules.read(token_id).reveal_at
        }

        fn is_unlocked(self: @ContractState, token_id: u256) -> bool {
            self.erc721._require_owned(token_id);
            get_block_timestamp() >= self.capsules.read(token_id).reveal_at
        }

        fn is_revealed(self: @ContractState, token_id: u256) -> bool {
            self.erc721._require_owned(token_id);
            self.capsules.read(token_id).revealed_at != 0
        }

        fn get_hidden_uri(self: @ContractState) -> ByteArray {
            self.hidden_uri.read()
        }

        fn get_max_lock_duration(self: @ContractState) -> u64 {
            self.max_lock_duration.read()
        }

        fn compute_content_commitment(
            self: @ContractState, content_hash: felt252, content_salt: felt252,
        ) -> felt252 {
            compute_content_commitment(content_hash, content_salt)
        }

        fn get_commitment_scheme(self: @ContractState) -> felt252 {
            COMMITMENT_SCHEME_POSEIDON_HASH_SALT
        }
    }
}
