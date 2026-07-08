// DESIGN: GenerativeArt is a permissionless-to-deploy, COLLECTOR-minted ERC-721
// for generative art. The generative script is anchored on-chain by its poseidon
// hash; each token's seed is derived deterministically at the collector's mint.
// Fully immutable: no owner, no upgrade, no pause, no setters. Zero-fee.

#[starknet::contract]
pub mod GenerativeArt {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::common::erc2981::{DefaultConfig, ERC2981Component};
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interfaces::IGenerativeArt::IGenerativeArt;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC2981Component, storage: erc2981, event: ERC2981Event);

    // ERC-721 + metadata (token_uri = base_uri + token_id, provided by OZ).
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    // ERC-2981 READ ONLY: royalty_info + info getters. NO admin impl => royalty frozen.
    #[abi(embed_v0)]
    impl ERC2981Impl = ERC2981Component::ERC2981Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC2981InfoImpl = ERC2981Component::ERC2981InfoImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl ERC2981InternalImpl = ERC2981Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc2981: ERC2981Component::Storage,
        /// Poseidon hash of the generative script — immutable tamper-proof anchor.
        script_hash: felt252,
        /// Permanent-storage pointer to the script source. Immutable.
        script_uri: ByteArray,
        /// Immutable hard cap.
        max_supply: u256,
        /// Sequential id counter; starts at 1.
        next_token_id: u256,
        /// Deterministic seed per token, written once at mint.
        token_seeds: Map<u256, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC2981Event: ERC2981Component::Event,
        Minted: Minted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Minted {
        #[key]
        pub token_id: u256,
        #[key]
        pub minter: ContractAddress,
        pub seed: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        script_hash: felt252,
        script_uri: ByteArray,
        max_supply: u256,
        royalty_receiver: ContractAddress,
        royalty_bps: u16,
    ) {
        assert(max_supply > 0, 'max_supply must be > 0');
        assert(script_hash != 0, 'script_hash must be set');
        self.erc721.initializer(name, symbol, base_uri);
        // DefaultConfig denominator is 10_000, so royalty_bps maps directly.
        self.erc2981.initializer(royalty_receiver, royalty_bps.into());
        self.script_hash.write(script_hash);
        self.script_uri.write(script_uri);
        self.max_supply.write(max_supply);
        self.next_token_id.write(1);
    }

    #[abi(embed_v0)]
    impl GenerativeArtImpl of IGenerativeArt<ContractState> {
        fn script_hash(self: @ContractState) -> felt252 {
            self.script_hash.read()
        }
        fn script_uri(self: @ContractState) -> ByteArray {
            self.script_uri.read()
        }
        fn max_supply(self: @ContractState) -> u256 {
            self.max_supply.read()
        }
        fn total_minted(self: @ContractState) -> u256 {
            self.next_token_id.read() - 1
        }
        fn token_seed(self: @ContractState, token_id: u256) -> felt252 {
            self.token_seeds.read(token_id)
        }
        fn mint(ref self: ContractState) -> u256 {
            let token_id = self.next_token_id.read();
            assert(token_id <= self.max_supply.read(), 'max supply reached');

            let minter = get_caller_address();
            let ts = get_block_timestamp();
            let seed = PoseidonTrait::new()
                .update_with(token_id)
                .update_with(minter)
                .update_with(ts)
                .finalize();

            self.token_seeds.write(token_id, seed);
            self.next_token_id.write(token_id + 1);
            self.erc721.mint(minter, token_id);

            self.emit(Minted { token_id, minter, seed });
            token_id
        }
    }
}
