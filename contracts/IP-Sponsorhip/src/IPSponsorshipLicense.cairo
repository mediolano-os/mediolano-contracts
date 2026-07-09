// The sponsorship license token: a standard ERC-721 whose holder is the
// current licensee. Minted only by the IPSponsorship registry when an offer
// is accepted. Transferability and expiry are properties of each license,
// enforced in the transfer hook; a transferable, unexpired license moves
// through ordinary transfer_from/safe_transfer_from and is therefore
// listable and holdable by any ERC-721-aware wallet, marketplace, or agent.
// EIP-2981 royalties on resale pay the IP author. Ownerless after the
// one-time minter bootstrap.
#[starknet::contract]
pub mod IPSponsorshipLicense {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{
        IIPSponsorshipLicense, IIP_SPONSORSHIP_LICENSE_ID, ILICENSED_COLLECTION_ID,
    };
    use crate::types::{LicenseData, bytearray_starts_with};

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
        /// The IPSponsorship registry. Zero until the one-time bootstrap;
        /// immutable afterwards.
        minter: ContractAddress,
        last_license_id: u256,
        licenses: Map<u256, LicenseData>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        LicenseMinted: LicenseMinted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LicenseMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub recipient: ContractAddress,
        #[key]
        pub author: ContractAddress,
        pub asset_contract: ContractAddress,
        pub asset_token_id: u256,
        pub expires_at: u64,
        pub transferable: bool,
        pub royalty_bps: u256,
        pub license_terms_uri: ByteArray,
        pub minted_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        assert(name.len() > 0, 'Name must not be empty');
        assert(symbol.len() > 0, 'Symbol must not be empty');
        // Token URI resolves per license from its own terms document.
        self.erc721.initializer(name, symbol, "");
        self.src5.register_interface(IIP_SPONSORSHIP_LICENSE_ID);
        self.src5.register_interface(IERC2981_ID);
        self.src5.register_interface(ILICENSED_COLLECTION_ID);
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
            // Mint and burn are always permitted; holder-to-holder movement
            // requires a transferable, unexpired license.
            if current_owner.is_zero() || to.is_zero() {
                return;
            }
            let data = contract_state.licenses.read(token_id);
            assert(data.transferable, 'License not transferable');
            assert(get_block_timestamp() < data.expires_at, 'License expired');
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
            self.licenses.read(token_id).license_terms_uri
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            self.licenses.read(tokenId).license_terms_uri
        }
    }

    #[abi(embed_v0)]
    impl IPSponsorshipLicenseImpl of IIPSponsorshipLicense<ContractState> {
        fn set_minter(ref self: ContractState, minter: ContractAddress) {
            assert(self.minter.read().is_zero(), 'Minter already set');
            assert(!minter.is_zero(), 'Minter is zero address');
            self.minter.write(minter);
        }

        fn get_minter(self: @ContractState) -> ContractAddress {
            self.minter.read()
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, data: LicenseData) -> u256 {
            let minter = self.minter.read();
            assert(!minter.is_zero(), 'Minter not set');
            assert(get_caller_address() == minter, 'Only minter');
            assert(!recipient.is_zero(), 'Recipient is zero address');
            assert(data.expires_at > get_block_timestamp(), 'Expiry must be future');
            assert(data.royalty_bps <= 10000, 'Royalty exceeds 10000');
            let valid_uri = bytearray_starts_with(@data.license_terms_uri, @"ipfs://")
                || bytearray_starts_with(@data.license_terms_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            let token_id = self.last_license_id.read() + 1;
            self.last_license_id.write(token_id);
            self.licenses.write(token_id, data.clone());

            self.erc721.mint(recipient, token_id);

            self
                .emit(
                    LicenseMinted {
                        token_id,
                        recipient,
                        author: data.author,
                        asset_contract: data.asset_contract,
                        asset_token_id: data.asset_token_id,
                        expires_at: data.expires_at,
                        transferable: data.transferable,
                        royalty_bps: data.royalty_bps,
                        license_terms_uri: data.license_terms_uri,
                        minted_at: get_block_timestamp(),
                    },
                );

            token_id
        }

        fn get_license_data(self: @ContractState, token_id: u256) -> LicenseData {
            self.erc721._require_owned(token_id);
            self.licenses.read(token_id)
        }

        fn is_license_valid(self: @ContractState, token_id: u256) -> bool {
            let owner = self.erc721.ERC721_owners.read(token_id);
            if owner.is_zero() {
                return false;
            }
            get_block_timestamp() < self.licenses.read(token_id).expires_at
        }

        fn last_license_id(self: @ContractState) -> u256 {
            self.last_license_id.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.erc721._require_owned(token_id);
            let data = self.licenses.read(token_id);
            ((data.author), (sale_price * data.royalty_bps) / 10000)
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
