#[starknet::contract]
pub mod IPClubNFT {
    use ERC721Component::InternalTrait;
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::get_block_timestamp;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    use crate::interfaces::IIPClubNFT::{IIPClubNFT, IIP_CLUB_NFT_ID, ILICENSED_COLLECTION_ID};
    use crate::types::bytearray_starts_with;

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
        creator: ContractAddress, // Address of the NFT creator
        club_id: u256, // Club identifier
        ip_club_manager: ContractAddress, // Address of the IP club manager
        last_token_id: u256, // Last minted token ID
        metadata_uri: ByteArray, // The club's shared document (every card looks the same)
        transfer_lock: Option<u64>, // None = permanently non-transferable
        royalty_bps: u256,
        minted_at: Map<u256, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        club_id: u256,
        creator: ContractAddress,
        ip_club_manager: ContractAddress,
        metadata_uri: ByteArray,
        transfer_lock: Option<u64>,
        royalty_bps: u256,
    ) {
        assert(name.len() > 0, 'Name must not be empty');
        assert(symbol.len() > 0, 'Symbol must not be empty');
        assert(club_id > 0, 'Club id is zero');
        assert(!creator.is_zero(), 'Creator is zero address');
        assert(!ip_club_manager.is_zero(), 'Manager is zero address');
        assert(royalty_bps <= 10000, 'Royalty exceeds 10000');
        let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
            || bytearray_starts_with(@metadata_uri, @"ar://");
        assert(valid_uri, 'URI must be ipfs:// or ar://');

        // Token URI is resolved from the club's own document, not OZ's
        // base-URI concatenation (which would dangle a token id onto it).
        self.erc721.initializer(name, symbol, "");
        self.src5.register_interface(IIP_CLUB_NFT_ID);
        self.src5.register_interface(IERC2981_ID);
        self.src5.register_interface(ILICENSED_COLLECTION_ID);

        // Store creator, manager, club ID, and reset last token ID
        self.creator.write(creator);
        self.ip_club_manager.write(ip_club_manager);
        self.last_token_id.write(0);
        self.club_id.write(club_id);
        self.metadata_uri.write(metadata_uri);
        self.transfer_lock.write(transfer_lock);
        self.royalty_bps.write(royalty_bps);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let contract_state = self.get_contract();
            let current_owner = contract_state.erc721.ERC721_owners.read(token_id);
            // Mints (owner not yet set) and burns (leave path) are always
            // permitted; only member-to-member movement is vesting-gated.
            if current_owner.is_zero() || to.is_zero() {
                return;
            }
            match contract_state.transfer_lock.read() {
                Option::None => { assert(false, 'Membership is non-transferable'); },
                Option::Some(lock) => {
                    let unlocks_at = contract_state.minted_at.read(token_id) + lock;
                    assert(get_block_timestamp() >= unlocks_at, 'Membership still vesting');
                },
            }
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
            self.metadata_uri.read()
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            self.metadata_uri.read()
        }
    }

    // Implementation of the IIPClubNFT interface
    #[abi(embed_v0)]
    impl IIPClubNFTImpl of IIPClubNFT<ContractState> {
        /// Mints a new NFT and assigns it to the specified recipient address.
        /// # Arguments
        /// * `recipient` - The address that will receive the newly minted NFT.
        /// # Access Control
        /// Only authorized club nft manager can call this function.
        // Mint a new NFT to the recipient address
        fn mint(ref self: ContractState, recipient: ContractAddress) {
            assert(get_caller_address() == self.ip_club_manager.read(), 'Not club manager');
            assert(!recipient.is_zero(), 'Recipient is zero address');

            // Ensure recipient does not already own an NFT
            let has_nft = self.has_nft(recipient);
            assert(!has_nft, 'Already has nft');

            // Increment token ID and mint NFT
            let next_token_id = self.last_token_id.read() + 1;
            self.minted_at.write(next_token_id, get_block_timestamp());
            self.erc721.safe_mint(recipient, next_token_id, array![].span());
            self.last_token_id.write(next_token_id);
        }

        /// Burns a member's NFT — the leave path. Only the IPClub registry
        /// may call this, and only for a token the member actually owns.
        /// The transfer hook permits burns (`to == 0`), so non-transferable
        /// membership remains enforced for every other movement.
        fn burn(ref self: ContractState, member: ContractAddress, token_id: u256) {
            assert(get_caller_address() == self.ip_club_manager.read(), 'Not club manager');
            let owner = self.erc721.ERC721_owners.read(token_id);
            assert(owner == member, 'Not token owner');

            self.erc721.burn(token_id);
        }

        // Check if a user already owns an NFT
        fn has_nft(self: @ContractState, user: ContractAddress) -> bool {
            let balance = self.erc721.balance_of(user);
            balance > 0
        }

        // Get the creator address
        fn get_nft_creator(self: @ContractState) -> ContractAddress {
            self.creator.read()
        }

        // Get the IP club manager address
        fn get_ip_club_manager(self: @ContractState) -> ContractAddress {
            self.ip_club_manager.read()
        }

        // Get the Club ID
        fn get_associated_club_id(self: @ContractState) -> u256 {
            self.club_id.read()
        }

        // Get last minted ID
        fn get_last_minted_id(self: @ContractState) -> u256 {
            self.last_token_id.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.erc721._require_owned(token_id);
            let amount = (sale_price * self.royalty_bps.read()) / 10000;
            (self.creator.read(), amount)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.royalty_info(token_id, sale_price)
        }

        fn version(self: @ContractState) -> ByteArray {
            "2.0.0"
        }
    }
}
