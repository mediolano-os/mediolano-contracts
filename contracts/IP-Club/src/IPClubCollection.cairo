#[starknet::contract]
pub mod IPClubCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc1155::interface::{IERC1155MetadataURI, IERC1155_METADATA_URI_ID};
    use openzeppelin_token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp};
    use crate::interface::{IIPClubCollection, IIP_CLUB_COLLECTION_ID};
    use crate::types::{Membership, bytearray_starts_with};

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
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        next_token_id: u256,
        memberships: Map<u256, Membership>,
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
        MembershipCreated: MembershipCreated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MembershipCreated {
        #[key]
        pub token_id: u256,
        pub max_supply: u256,
        pub start_time: Option<u64>,
        pub end_time: Option<u64>,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
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
        // uri() resolves per token_id from the memberships map; the ERC1155 base is unused.
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_CLUB_COLLECTION_ID);
        self.src5.register_interface(IERC2981_ID);
        self.src5.register_interface(IERC1155_METADATA_URI_ID);
        self.name.write(name);
        self.symbol.write(symbol);
        self.base_uri.write(base_uri);
        self.next_token_id.write(1);
    }

    /// True iff `now` is inside the membership's validity window. A tier with
    /// no window is always valid.
    fn in_window(m: @Membership, now: u64) -> bool {
        if let Option::Some(start) = *m.start_time {
            if now < start {
                return false;
            }
        }
        if let Option::Some(end) = *m.end_time {
            if now >= end {
                return false;
            }
        }
        true
    }

    /// Per-membership metadata URI instead of base+id concatenation.
    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, token_id: u256) -> ByteArray {
            let membership = self.memberships.read(token_id);
            assert(membership.max_supply > 0, 'Membership not found');
            membership.metadata_uri
        }
    }

    #[abi(embed_v0)]
    pub impl IPClubCollectionImpl of IIPClubCollection<ContractState> {
        fn create_membership(
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

            let membership = Membership {
                max_supply,
                minted: 0,
                start_time,
                end_time,
                royalty_bps,
                metadata_uri: metadata_uri.clone(),
            };
            self.memberships.write(token_id, membership);

            self
                .emit(
                    MembershipCreated {
                        token_id,
                        max_supply,
                        start_time,
                        end_time,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            token_id
        }

        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, amount: u256) {
            self.ownable.assert_only_owner();
            assert(!to.is_zero(), 'Recipient is zero');

            let mut membership = self.memberships.read(token_id);
            assert(membership.max_supply > 0, 'Membership not found');
            assert(membership.minted + amount <= membership.max_supply, 'Max supply reached');

            membership.minted += amount;
            self.memberships.write(token_id, membership);

            self.erc1155.mint_with_acceptance_check(to, token_id, amount, array![].span());
        }

        fn is_member(self: @ContractState, holder: ContractAddress) -> bool {
            let now = get_block_timestamp();
            let next = self.next_token_id.read();
            let mut token_id: u256 = 1;
            let mut member = false;
            while token_id < next {
                if self.erc1155.balance_of(holder, token_id) > 0 {
                    let membership = self.memberships.read(token_id);
                    if in_window(@membership, now) {
                        member = true;
                        break;
                    }
                }
                token_id += 1;
            }
            member
        }

        fn is_member_of(self: @ContractState, token_id: u256, holder: ContractAddress) -> bool {
            let membership = self.memberships.read(token_id);
            if membership.max_supply == 0 {
                return false;
            }
            if self.erc1155.balance_of(holder, token_id) == 0 {
                return false;
            }
            in_window(@membership, get_block_timestamp())
        }

        fn get_membership(self: @ContractState, token_id: u256) -> Membership {
            let membership = self.memberships.read(token_id);
            assert(membership.max_supply > 0, 'Membership not found');
            membership
        }

        fn name(self: @ContractState) -> ByteArray {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.symbol.read()
        }

        fn base_uri(self: @ContractState) -> ByteArray {
            self.base_uri.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let membership = self.memberships.read(token_id);
            assert(membership.max_supply > 0, 'Membership not found');
            let amount = (sale_price * membership.royalty_bps.into()) / 10000;
            (self.ownable.owner(), amount)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.royalty_info(token_id, sale_price)
        }

        fn version(self: @ContractState) -> ByteArray {
            "4.0.0"
        }
    }
}
