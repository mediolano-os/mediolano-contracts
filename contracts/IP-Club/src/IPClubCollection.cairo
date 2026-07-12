// IPClubCollection — per-creator ERC-721 membership contract deployed by
// IPClubFactory. Public mint; fee flows directly creator → buyer in the call.
// Fully immutable: no metadata update, no supply change, no admin backdoors.
// Ownable only for set_open (creator-managed pause on new memberships).

#[starknet::contract]
pub mod IPClubCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use crate::interface::{IIPClubCollection, IIP_CLUB_COLLECTION_ID};
    use crate::types::bytearray_starts_with;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
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
        /// Immutable collection metadata URI (ipfs:// or ar://).
        club_base_uri: ByteArray,
        /// Hard cap on membership supply. Immutable.
        club_max_supply: u256,
        /// Entry fee per membership in payment_token base units. Immutable.
        club_entry_fee: u256,
        /// ERC-20 accepted for entry fees. None means free. Immutable.
        club_payment_token: Option<ContractAddress>,
        /// EIP-2981 royalty in basis points (0..=10000). Immutable.
        club_royalty_bps: u256,
        /// Creator-controlled gate on new mints. Does not affect existing members.
        club_is_open: bool,
        next_token_id: u256,
        club_total_minted: u256,
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
        MemberMinted: MemberMinted,
        OpenStatusChanged: OpenStatusChanged,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MemberMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub to: ContractAddress,
        pub payer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OpenStatusChanged {
        pub open: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        max_supply: u256,
        entry_fee: u256,
        payment_token: Option<ContractAddress>,
        royalty_bps: u256,
        owner: ContractAddress,
    ) {
        assert(name.len() > 0, 'Name must not be empty');
        assert(symbol.len() > 0, 'Symbol must not be empty');
        let valid_uri = bytearray_starts_with(@base_uri, @"ipfs://")
            || bytearray_starts_with(@base_uri, @"ar://");
        assert(valid_uri, 'URI must be ipfs:// or ar://');
        assert(max_supply > 0, 'Max supply must be > 0');
        assert(royalty_bps <= 10000, 'Royalty exceeds 10000');
        assert(!owner.is_zero(), 'Owner is zero address');
        if entry_fee == 0 {
            assert(payment_token.is_none(), 'Free club cannot use token');
        } else {
            assert(payment_token.is_some(), 'Paid club requires token');
            assert(!payment_token.unwrap().is_zero(), 'Payment token is zero');
        }

        self.erc721.initializer(name, symbol, "");
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_CLUB_COLLECTION_ID);
        self.src5.register_interface(IERC2981_ID);

        self.club_base_uri.write(base_uri);
        self.club_max_supply.write(max_supply);
        self.club_entry_fee.write(entry_fee);
        self.club_payment_token.write(payment_token);
        self.club_royalty_bps.write(royalty_bps);
        self.club_is_open.write(true);
        self.next_token_id.write(1);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}

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
            self.club_base_uri.read()
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            self.club_base_uri.read()
        }
    }

    #[abi(embed_v0)]
    pub impl IPClubCollectionImpl of IIPClubCollection<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress) -> u256 {
            assert(self.club_is_open.read(), 'Club is closed');
            assert(self.club_total_minted.read() < self.club_max_supply.read(), 'Max supply reached');
            assert(!to.is_zero(), 'Recipient is zero address');

            let payer = get_caller_address();

            // Effects before external calls (checks-effects-interactions).
            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);
            self.club_total_minted.write(self.club_total_minted.read() + 1);

            let fee = self.club_entry_fee.read();
            if fee > 0 {
                let owner = self.ownable.owner();
                let token = IERC20Dispatcher {
                    contract_address: self.club_payment_token.read().unwrap(),
                };
                let result = token.transfer_from(payer, owner, fee);
                assert(result, 'Token transfer failed');
            }

            self.erc721.safe_mint(to, token_id, array![].span());
            self.emit(MemberMinted { token_id, to, payer });

            token_id
        }

        fn set_open(ref self: ContractState, open: bool) {
            self.ownable.assert_only_owner();
            self.club_is_open.write(open);
            self.emit(OpenStatusChanged { open });
        }

        fn base_uri(self: @ContractState) -> ByteArray {
            self.club_base_uri.read()
        }

        fn entry_fee(self: @ContractState) -> u256 {
            self.club_entry_fee.read()
        }

        fn payment_token(self: @ContractState) -> Option<ContractAddress> {
            self.club_payment_token.read()
        }

        fn max_supply(self: @ContractState) -> u256 {
            self.club_max_supply.read()
        }

        fn total_minted(self: @ContractState) -> u256 {
            self.club_total_minted.read()
        }

        fn is_open(self: @ContractState) -> bool {
            self.club_is_open.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.erc721._require_owned(token_id);
            let owner = self.ownable.owner();
            let amount = (sale_price * self.club_royalty_bps.read()) / 10000;
            (owner, amount)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.erc721._require_owned(token_id);
            let owner = self.ownable.owner();
            let amount = (sale_price * self.club_royalty_bps.read()) / 10000;
            (owner, amount)
        }

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }
    }
}
