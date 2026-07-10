#[starknet::contract]
pub mod IPTicketCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc1155::ERC1155Component;
    use openzeppelin_token::erc1155::ERC1155HooksEmptyImpl;
    use openzeppelin_token::erc1155::interface::{IERC1155MetadataURI, IERC1155_METADATA_URI_ID};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{IIPTicketCollection, IIP_TICKET_COLLECTION_ID};
    use crate::types::{EventRecord, bytearray_starts_with};

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155CamelImpl = ERC1155Component::ERC1155CamelImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        next_token_id: u256,
        events: Map<u256, EventRecord>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        EventCreated: EventCreated,
        EventPaused: EventPaused,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EventCreated {
        #[key]
        pub token_id: u256,
        pub max_supply: u256,
        pub start_time: Option<u64>,
        pub end_time: Option<u64>,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EventPaused {
        #[key]
        pub token_id: u256,
        pub active: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        owner: ContractAddress,
    ) {
        assert(name.len() > 0, 'Name must not be empty');
        assert(symbol.len() > 0, 'Symbol must not be empty');
        assert(!owner.is_zero(), 'Owner is zero address');
        // Empty base URI — uri() resolves per token_id from the events map.
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_TICKET_COLLECTION_ID);
        self.src5.register_interface(IERC2981_ID);
        self.src5.register_interface(IERC1155_METADATA_URI_ID);
        self.next_token_id.write(1);
    }

    /// Override uri() to return per-event metadata URI instead of base+id concatenation.
    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, token_id: u256) -> ByteArray {
            let ev = self.events.read(token_id);
            assert(!ev.creator.is_zero(), 'Event not found');
            ev.metadata_uri
        }
    }

    #[abi(embed_v0)]
    pub impl IPTicketCollectionImpl of IIPTicketCollection<ContractState> {
        fn create_event(
            ref self: ContractState,
            max_supply: u256,
            start_time: Option<u64>,
            end_time: Option<u64>,
            royalty_bps: u16,
            metadata_uri: ByteArray,
        ) -> u256 {
            self.ownable.assert_only_owner();
            assert(max_supply > 0, 'Max supply is zero');
            assert(royalty_bps <= 10000, 'Royalty exceeds 10000');

            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if let Option::Some(end) = end_time {
                if let Option::Some(start) = start_time {
                    assert(end > start, 'end_time before start_time');
                }
            }

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            let creator = get_caller_address();
            let record = EventRecord {
                creator,
                max_supply,
                minted: 0,
                start_time,
                end_time,
                royalty_bps,
                metadata_uri: metadata_uri.clone(),
                active: true,
            };
            self.events.write(token_id, record);

            self.emit(EventCreated {
                token_id,
                max_supply,
                start_time,
                end_time,
                metadata_uri,
                created_at: get_block_timestamp(),
            });

            token_id
        }

        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, amount: u256) {
            self.ownable.assert_only_owner();
            assert(!to.is_zero(), 'Recipient is zero');

            let mut ev = self.events.read(token_id);
            assert(!ev.creator.is_zero(), 'Event not found');
            assert(ev.active, 'Event is paused');

            let now = get_block_timestamp();
            if let Option::Some(start) = ev.start_time {
                assert(now >= start, 'Minting not yet open');
            }
            if let Option::Some(end) = ev.end_time {
                assert(now < end, 'Minting window closed');
            }
            assert(ev.minted + amount <= ev.max_supply, 'Max supply reached');

            ev.minted += amount;
            self.events.write(token_id, ev);

            self.erc1155.mint_with_acceptance_check(to, token_id, amount, array![].span());
        }

        fn pause_event(ref self: ContractState, token_id: u256, active: bool) {
            self.ownable.assert_only_owner();
            let mut ev = self.events.read(token_id);
            assert(!ev.creator.is_zero(), 'Event not found');
            ev.active = active;
            self.events.write(token_id, ev);
            self.emit(EventPaused { token_id, active });
        }

        fn is_valid(self: @ContractState, token_id: u256, holder: ContractAddress) -> bool {
            let ev = self.events.read(token_id);
            if ev.creator.is_zero() {
                return false;
            }
            if self.erc1155.balance_of(holder, token_id) == 0 {
                return false;
            }
            let now = get_block_timestamp();
            if let Option::Some(start) = ev.start_time {
                if now < start {
                    return false;
                }
            }
            if let Option::Some(end) = ev.end_time {
                if now >= end {
                    return false;
                }
            }
            true
        }

        fn get_event(self: @ContractState, token_id: u256) -> EventRecord {
            let ev = self.events.read(token_id);
            assert(!ev.creator.is_zero(), 'Event not found');
            ev
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let ev = self.events.read(token_id);
            assert(!ev.creator.is_zero(), 'Event not found');
            let amount = (sale_price * ev.royalty_bps.into()) / 10000;
            (ev.creator, amount)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.royalty_info(token_id, sale_price)
        }

        fn version(self: @ContractState) -> ByteArray {
            "3.0.0"
        }
    }
}
