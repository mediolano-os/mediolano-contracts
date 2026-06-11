#[starknet::contract]
pub mod IPTicketService {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{IIPTicketService, IIP_TICKET_SERVICE_ID};
    use crate::types::{TicketData, TicketSeries, bytearray_starts_with};

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
        last_series_id: u256,
        next_token_id: u256,
        total_supply: u256,
        ticket_series: Map<u256, TicketSeries>,
        token_to_series: Map<u256, u256>,
        active_ticket_balance: Map<(ContractAddress, u256), u256>,
        redeemed_tickets: Map<u256, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        TicketSeriesCreated: TicketSeriesCreated,
        SeriesStatusUpdated: SeriesStatusUpdated,
        TicketMinted: TicketMinted,
        TicketRedeemed: TicketRedeemed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SeriesStatusUpdated {
        #[key]
        pub series_id: u256,
        pub active: bool,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TicketSeriesCreated {
        #[key]
        pub series_id: u256,
        #[key]
        pub creator: ContractAddress,
        pub price: u256,
        pub max_supply: u256,
        pub expiration: u64,
        pub royalty_bps: u256,
        pub payment_token: Option<ContractAddress>,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TicketMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub series_id: u256,
        #[key]
        pub owner: ContractAddress,
        pub minted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TicketRedeemed {
        #[key]
        pub token_id: u256,
        #[key]
        pub series_id: u256,
        #[key]
        pub owner: ContractAddress,
        pub redeemed_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        assert(name.len() > 0, 'Name must not be empty');
        assert(symbol.len() > 0, 'Symbol must not be empty');

        // Token URI is resolved per ticket from its ticket series.
        self.erc721.initializer(name, symbol, "");
        self.src5.register_interface(IIP_TICKET_SERVICE_ID);
        self.src5.register_interface(IERC2981_ID);
        self.next_token_id.write(1);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let mut contract_state = self.get_contract_mut();
            if contract_state.redeemed_tickets.read(token_id) {
                return;
            }

            let series_id = contract_state.token_to_series.read(token_id);
            if series_id == 0 {
                return;
            }

            let from = contract_state.erc721.ERC721_owners.read(token_id);
            if !from.is_zero() {
                let from_key = (from, series_id);
                let from_balance = contract_state.active_ticket_balance.read(from_key);
                assert(from_balance > 0, 'Ticket balance underflow');
                contract_state.active_ticket_balance.write(from_key, from_balance - 1);
            }

            if !to.is_zero() {
                let to_key = (to, series_id);
                let to_balance = contract_state.active_ticket_balance.read(to_key);
                contract_state.active_ticket_balance.write(to_key, to_balance + 1);
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
            let series_id = self.token_to_series.read(token_id);
            self.ticket_series.read(series_id).metadata_uri
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            let series_id = self.token_to_series.read(tokenId);
            self.ticket_series.read(series_id).metadata_uri
        }
    }

    #[abi(embed_v0)]
    pub impl IPTicketImpl of IIPTicketService<ContractState> {
        fn create_ticket_series(
            ref self: ContractState,
            price: u256,
            max_supply: u256,
            expiration: u64,
            royalty_bps: u256,
            payment_token: Option<ContractAddress>,
            metadata_uri: ByteArray,
        ) -> u256 {
            let creator = get_caller_address();
            assert(!creator.is_zero(), 'Creator is zero address');
            assert(max_supply > 0, 'Max supply is zero');
            assert(expiration > get_block_timestamp(), 'Expiration must be future');
            assert(royalty_bps <= 10000, 'Royalty exceeds 10000');

            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if price == 0 {
                assert(payment_token.is_none(), 'Free ticket cannot use token');
            } else {
                assert(payment_token.is_some(), 'Paid ticket requires token');
                assert(!payment_token.unwrap().is_zero(), 'Payment token is zero');
            }

            let series_id = self.last_series_id.read() + 1;
            let series = TicketSeries {
                creator,
                price,
                max_supply,
                minted: 0,
                expiration,
                royalty_bps,
                payment_token,
                metadata_uri: metadata_uri.clone(),
                active: true,
            };

            self.ticket_series.write(series_id, series);
            self.last_series_id.write(series_id);

            self
                .emit(
                    TicketSeriesCreated {
                        series_id,
                        creator,
                        price,
                        max_supply,
                        expiration,
                        royalty_bps,
                        payment_token,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            series_id
        }

        fn set_series_active(ref self: ContractState, series_id: u256, active: bool) {
            let mut series = self.ticket_series.read(series_id);
            assert(!series.creator.is_zero(), 'Ticket series does not exist');
            assert(get_caller_address() == series.creator, 'Only series creator');

            series.active = active;
            self.ticket_series.write(series_id, series);

            self.emit(SeriesStatusUpdated { series_id, active, updated_at: get_block_timestamp() });
        }

        fn mint_ticket(ref self: ContractState, series_id: u256) -> u256 {
            let mut series = self.ticket_series.read(series_id);
            assert(!series.creator.is_zero(), 'Ticket series does not exist');
            assert(series.active, 'Series is inactive');
            assert(get_block_timestamp() < series.expiration, 'Ticket series expired');
            assert(series.minted < series.max_supply, 'Max supply reached');

            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Recipient is zero address');

            series.minted += 1;
            self.ticket_series.write(series_id, series.clone());

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);
            self.token_to_series.write(token_id, series_id);
            self.total_supply.write(self.total_supply.read() + 1);

            // State is final before the external calls (checks-effects-
            // interactions); a reentrant call from the payment token or the
            // receiver callback runs under its own caller context against
            // consistent storage.
            collect_payment(caller, @series);

            self.erc721.safe_mint(caller, token_id, array![].span());

            self
                .emit(
                    TicketMinted {
                        token_id, series_id, owner: caller, minted_at: get_block_timestamp(),
                    },
                );

            token_id
        }

        fn redeem_ticket(ref self: ContractState, token_id: u256) {
            let owner = self.erc721.owner_of(token_id);
            let caller = get_caller_address();
            assert(caller == owner, 'Only owner can redeem');
            assert(!self.redeemed_tickets.read(token_id), 'Ticket already redeemed');

            let series_id = self.token_to_series.read(token_id);
            let series = self.ticket_series.read(series_id);
            assert(get_block_timestamp() < series.expiration, 'Ticket expired');

            self.redeemed_tickets.write(token_id, true);

            let key = (owner, series_id);
            let balance = self.active_ticket_balance.read(key);
            assert(balance > 0, 'Ticket balance underflow');
            self.active_ticket_balance.write(key, balance - 1);

            self
                .emit(
                    TicketRedeemed {
                        token_id, series_id, owner, redeemed_at: get_block_timestamp(),
                    },
                );
        }

        fn has_valid_ticket(self: @ContractState, user: ContractAddress, series_id: u256) -> bool {
            let series = self.ticket_series.read(series_id);
            if series.creator.is_zero() {
                return false;
            }
            if get_block_timestamp() >= series.expiration {
                return false;
            }
            self.active_ticket_balance.read((user, series_id)) > 0
        }

        fn get_ticket_series(self: @ContractState, series_id: u256) -> TicketSeries {
            let series = self.ticket_series.read(series_id);
            assert(!series.creator.is_zero(), 'Ticket series does not exist');
            series
        }

        fn get_ticket_data(self: @ContractState, token_id: u256) -> TicketData {
            let owner = self.erc721.owner_of(token_id);
            let series_id = self.token_to_series.read(token_id);
            let series = self.ticket_series.read(series_id);
            let redeemed = self.redeemed_tickets.read(token_id);
            let valid = !series.creator.is_zero()
                && !redeemed
                && get_block_timestamp() < series.expiration;

            TicketData {
                token_id,
                owner,
                series_id,
                creator: series.creator,
                metadata_uri: series.metadata_uri,
                expiration: series.expiration,
                redeemed,
                valid,
            }
        }

        fn get_ticket_series_id(self: @ContractState, token_id: u256) -> u256 {
            self.erc721._require_owned(token_id);
            self.token_to_series.read(token_id)
        }

        fn get_active_ticket_balance(
            self: @ContractState, user: ContractAddress, series_id: u256,
        ) -> u256 {
            self.active_ticket_balance.read((user, series_id))
        }

        fn get_last_series_id(self: @ContractState) -> u256 {
            self.last_series_id.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            compute_royalty(self, token_id, sale_price)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            compute_royalty(self, token_id, sale_price)
        }
    }

    fn compute_royalty(
        self: @ContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256) {
        self.erc721._require_owned(token_id);
        let series_id = self.token_to_series.read(token_id);
        let series = self.ticket_series.read(series_id);
        let royalty_amount = (sale_price * series.royalty_bps) / 10000;
        (series.creator, royalty_amount)
    }

    fn collect_payment(payer: ContractAddress, series: @TicketSeries) {
        if *series.price > 0 {
            // create_ticket_series guarantees a paid series carries a
            // non-zero payment token, and series terms are immutable.
            let token = IERC20Dispatcher { contract_address: (*series.payment_token).unwrap() };
            let result = token.transfer_from(payer, *series.creator, *series.price);
            assert(result, 'Token Transfer Failed');
        }
    }
}
