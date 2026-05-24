#[starknet::contract]
pub mod IPNegotiationEscrow {
    use core::num::traits::Zero;
    use ip_negotiation_escrow::errors::Errors;
    use ip_negotiation_escrow::interface::{IIPNegotiationEscrow, IIP_NEGOTIATION_ESCROW_ID};
    use ip_negotiation_escrow::types::{Negotiation, NegotiationStatus, bytearray_starts_with};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::ERC721Component::InternalTrait as ERC721InternalTrait;
    use openzeppelin_token::erc721::interface::IERC721Metadata;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        last_negotiation_id: u256,
        negotiations: Map<u256, Negotiation>,
        asset_to_negotiation: Map<(ContractAddress, u256), u256>,
        token_uris: Map<u256, ByteArray>,
        fulfillment_uris: Map<u256, ByteArray>,
        seller_claims: Map<(u256, ContractAddress), u256>,
        buyer_refunds: Map<(u256, ContractAddress), u256>,
        reentrancy_locked: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        ListingCreated: ListingCreated,
        ListingFunded: ListingFunded,
        FulfillmentSubmitted: FulfillmentSubmitted,
        FulfillmentApproved: FulfillmentApproved,
        ListingCancelled: ListingCancelled,
        SellerFundsClaimed: SellerFundsClaimed,
        BuyerRefundClaimed: BuyerRefundClaimed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ListingCreated {
        #[key]
        pub negotiation_id: u256,
        #[key]
        pub seller: ContractAddress,
        #[key]
        pub ip_asset_contract: ContractAddress,
        pub ip_token_id: u256,
        pub payment_token: ContractAddress,
        pub price: u256,
        pub deadline: u64,
        pub listing_uri: ByteArray,
        pub terms_uri: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ListingFunded {
        #[key]
        pub negotiation_id: u256,
        #[key]
        pub buyer: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FulfillmentSubmitted {
        #[key]
        pub negotiation_id: u256,
        #[key]
        pub seller: ContractAddress,
        pub fulfillment_uri: ByteArray,
        pub fulfillment_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FulfillmentApproved {
        #[key]
        pub negotiation_id: u256,
        #[key]
        pub buyer: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ListingCancelled {
        #[key]
        pub negotiation_id: u256,
        pub refund_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SellerFundsClaimed {
        #[key]
        pub negotiation_id: u256,
        #[key]
        pub seller: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BuyerRefundClaimed {
        #[key]
        pub negotiation_id: u256,
        #[key]
        pub buyer: ContractAddress,
        pub amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc721.initializer("Mediolano Negotiation Listing", "MNEG", "");
        self.src5.register_interface(IIP_NEGOTIATION_ESCROW_ID);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let from = self._owner_of(token_id);
            if !from.is_zero() && !to.is_zero() {
                assert(false, Errors::NON_TRANSFERABLE);
            }
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            "Mediolano Negotiation Listing"
        }

        fn symbol(self: @ContractState) -> ByteArray {
            "MNEG"
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.token_uris.entry(token_id).read()
        }
    }

    #[abi(embed_v0)]
    pub impl NegotiationEscrowImpl of IIPNegotiationEscrow<ContractState> {
        fn create_listing(
            ref self: ContractState,
            ip_asset_contract: ContractAddress,
            ip_token_id: u256,
            payment_token: ContractAddress,
            price: u256,
            listing_uri: ByteArray,
            listing_hash: felt252,
            terms_uri: ByteArray,
            terms_hash: felt252,
            deadline: u64,
        ) -> u256 {
            let seller = get_caller_address();
            assert(!seller.is_zero(), Errors::NOT_SELLER);
            assert(!ip_asset_contract.is_zero(), Errors::INVALID_ASSET);
            assert(!payment_token.is_zero(), Errors::INVALID_PAYMENT_TOKEN);
            assert(price > 0, Errors::PRICE_IS_ZERO);
            assert(listing_hash != 0, Errors::INVALID_HASH);
            assert(terms_hash != 0, Errors::INVALID_HASH);
            assert_content_addressed(@listing_uri);
            assert_content_addressed(@terms_uri);
            assert(deadline > get_block_timestamp(), Errors::DEADLINE_EXPIRED);

            let asset_key = (ip_asset_contract, ip_token_id);
            let existing_id = self.asset_to_negotiation.entry(asset_key).read();
            if existing_id != 0 {
                let existing = self.negotiations.entry(existing_id).read();
                let active = existing.status == NegotiationStatus::Open
                    || existing.status == NegotiationStatus::Funded
                    || existing.status == NegotiationStatus::FulfillmentSubmitted;
                assert(!existing.exists || !active, Errors::ACTIVE_LISTING_EXISTS);
            }

            let negotiation_id = self.last_negotiation_id.read() + 1;
            let negotiation = Negotiation {
                negotiation_id,
                seller,
                buyer: Zero::zero(),
                ip_asset_contract,
                ip_token_id,
                payment_token,
                price,
                escrowed_amount: 0,
                released_amount: 0,
                refunded_amount: 0,
                deadline,
                status: NegotiationStatus::Open,
                listing_uri: listing_uri.clone(),
                listing_hash,
                terms_uri: terms_uri.clone(),
                terms_hash,
                fulfillment_hash: 0,
                exists: true,
            };

            self.negotiations.entry(negotiation_id).write(negotiation);
            self.asset_to_negotiation.entry(asset_key).write(negotiation_id);
            self.token_uris.entry(negotiation_id).write(listing_uri.clone());
            self.last_negotiation_id.write(negotiation_id);
            self.erc721.mint(seller, negotiation_id);

            self
                .emit(
                    ListingCreated {
                        negotiation_id,
                        seller,
                        ip_asset_contract,
                        ip_token_id,
                        payment_token,
                        price,
                        deadline,
                        listing_uri,
                        terms_uri,
                    },
                );

            negotiation_id
        }

        fn fund_listing(ref self: ContractState, negotiation_id: u256) -> u256 {
            self.enter_non_reentrant();
            let buyer = get_caller_address();
            let mut negotiation = self.get_existing_negotiation(negotiation_id);
            assert(negotiation.status == NegotiationStatus::Open, Errors::INVALID_STATUS);
            self.assert_before_deadline(negotiation.deadline);
            assert(buyer != negotiation.seller, Errors::INVALID_BUYER);

            let token = IERC20Dispatcher { contract_address: negotiation.payment_token };
            let contract_address = get_contract_address();
            let balance_before = token.balance_of(contract_address);
            let success = token.transfer_from(buyer, contract_address, negotiation.price);
            assert(success, Errors::PAYMENT_FAILED);
            let balance_after = token.balance_of(contract_address);
            assert(balance_after - balance_before == negotiation.price, Errors::PAYMENT_FAILED);

            negotiation.buyer = buyer;
            negotiation.escrowed_amount = negotiation.price;
            negotiation.status = NegotiationStatus::Funded;
            let funded_amount = negotiation.price;
            self.negotiations.entry(negotiation_id).write(negotiation);
            self.exit_non_reentrant();

            self.emit(ListingFunded { negotiation_id, buyer, amount: funded_amount });
            funded_amount
        }

        fn submit_fulfillment(
            ref self: ContractState,
            negotiation_id: u256,
            fulfillment_uri: ByteArray,
            fulfillment_hash: felt252,
        ) {
            let caller = get_caller_address();
            let mut negotiation = self.get_existing_negotiation(negotiation_id);
            assert(caller == negotiation.seller, Errors::NOT_SELLER);
            assert(negotiation.status == NegotiationStatus::Funded, Errors::INVALID_STATUS);
            self.assert_before_deadline(negotiation.deadline);
            assert(fulfillment_hash != 0, Errors::INVALID_HASH);
            assert_content_addressed(@fulfillment_uri);

            negotiation.status = NegotiationStatus::FulfillmentSubmitted;
            negotiation.fulfillment_hash = fulfillment_hash;
            self.negotiations.entry(negotiation_id).write(negotiation);
            self.fulfillment_uris.entry(negotiation_id).write(fulfillment_uri.clone());

            self
                .emit(
                    FulfillmentSubmitted {
                        negotiation_id, seller: caller, fulfillment_uri, fulfillment_hash,
                    },
                );
        }

        fn approve_fulfillment(ref self: ContractState, negotiation_id: u256) {
            let caller = get_caller_address();
            let mut negotiation = self.get_existing_negotiation(negotiation_id);
            assert(caller == negotiation.buyer, Errors::NOT_BUYER);
            assert(
                negotiation.status == NegotiationStatus::FulfillmentSubmitted,
                Errors::INVALID_STATUS,
            );

            negotiation.status = NegotiationStatus::Completed;
            negotiation.released_amount = negotiation.price;
            let key = (negotiation_id, negotiation.seller);
            let claim = self.seller_claims.entry(key).read() + negotiation.price;
            self.seller_claims.entry(key).write(claim);
            let approved_amount = negotiation.price;
            self.negotiations.entry(negotiation_id).write(negotiation);

            self
                .emit(
                    FulfillmentApproved { negotiation_id, buyer: caller, amount: approved_amount },
                );
        }

        fn cancel_listing(ref self: ContractState, negotiation_id: u256) {
            let caller = get_caller_address();
            let mut negotiation = self.get_existing_negotiation(negotiation_id);
            let seller_can_cancel_open = caller == negotiation.seller
                && negotiation.status == NegotiationStatus::Open;
            let buyer_can_cancel_expired = caller == negotiation.buyer
                && negotiation.status == NegotiationStatus::Funded
                && get_block_timestamp() > negotiation.deadline;
            assert(seller_can_cancel_open || buyer_can_cancel_expired, Errors::INVALID_STATUS);

            let refund_amount = if buyer_can_cancel_expired {
                negotiation.escrowed_amount - negotiation.refunded_amount
            } else {
                0
            };
            negotiation.status = NegotiationStatus::Cancelled;
            negotiation.refunded_amount += refund_amount;
            let buyer = negotiation.buyer;
            self.negotiations.entry(negotiation_id).write(negotiation);
            if refund_amount > 0 {
                let key = (negotiation_id, buyer);
                let refund = self.buyer_refunds.entry(key).read() + refund_amount;
                self.buyer_refunds.entry(key).write(refund);
            }

            self.emit(ListingCancelled { negotiation_id, refund_amount });
        }

        fn claim_seller_funds(ref self: ContractState, negotiation_id: u256) -> u256 {
            self.enter_non_reentrant();
            let caller = get_caller_address();
            let negotiation = self.get_existing_negotiation(negotiation_id);
            assert(caller == negotiation.seller, Errors::NOT_SELLER);
            let key = (negotiation_id, caller);
            let amount = self.seller_claims.entry(key).read();
            assert(amount > 0, Errors::NOTHING_TO_CLAIM);
            self.seller_claims.entry(key).write(0);

            let token = IERC20Dispatcher { contract_address: negotiation.payment_token };
            let success = token.transfer(caller, amount);
            assert(success, Errors::PAYMENT_FAILED);
            self.exit_non_reentrant();

            self.emit(SellerFundsClaimed { negotiation_id, seller: caller, amount });
            amount
        }

        fn claim_buyer_refund(ref self: ContractState, negotiation_id: u256) -> u256 {
            self.enter_non_reentrant();
            let caller = get_caller_address();
            let negotiation = self.get_existing_negotiation(negotiation_id);
            assert(caller == negotiation.buyer, Errors::NOT_BUYER);
            let key = (negotiation_id, caller);
            let amount = self.buyer_refunds.entry(key).read();
            assert(amount > 0, Errors::NOTHING_TO_CLAIM);
            self.buyer_refunds.entry(key).write(0);

            let token = IERC20Dispatcher { contract_address: negotiation.payment_token };
            let success = token.transfer(caller, amount);
            assert(success, Errors::PAYMENT_FAILED);
            self.exit_non_reentrant();

            self.emit(BuyerRefundClaimed { negotiation_id, buyer: caller, amount });
            amount
        }

        fn get_negotiation(self: @ContractState, negotiation_id: u256) -> Negotiation {
            self.get_existing_negotiation(negotiation_id)
        }

        fn get_negotiation_by_asset(
            self: @ContractState, ip_asset_contract: ContractAddress, ip_token_id: u256,
        ) -> Negotiation {
            let negotiation_id = self
                .asset_to_negotiation
                .entry((ip_asset_contract, ip_token_id))
                .read();
            self.get_existing_negotiation(negotiation_id)
        }

        fn get_fulfillment_uri(self: @ContractState, negotiation_id: u256) -> ByteArray {
            self.get_existing_negotiation(negotiation_id);
            self.fulfillment_uris.entry(negotiation_id).read()
        }

        fn get_claimable_seller_funds(
            self: @ContractState, negotiation_id: u256, seller: ContractAddress,
        ) -> u256 {
            self.seller_claims.entry((negotiation_id, seller)).read()
        }

        fn get_claimable_buyer_refund(
            self: @ContractState, negotiation_id: u256, buyer: ContractAddress,
        ) -> u256 {
            self.buyer_refunds.entry((negotiation_id, buyer)).read()
        }

        fn get_last_negotiation_id(self: @ContractState) -> u256 {
            self.last_negotiation_id.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing_negotiation(self: @ContractState, negotiation_id: u256) -> Negotiation {
            let negotiation = self.negotiations.entry(negotiation_id).read();
            assert(negotiation.exists, Errors::NEGOTIATION_NOT_FOUND);
            negotiation
        }

        fn enter_non_reentrant(ref self: ContractState) {
            assert(!self.reentrancy_locked.read(), Errors::REENTRANT_CALL);
            self.reentrancy_locked.write(true);
        }

        fn exit_non_reentrant(ref self: ContractState) {
            self.reentrancy_locked.write(false);
        }

        fn assert_before_deadline(self: @ContractState, deadline: u64) {
            assert(get_block_timestamp() <= deadline, Errors::DEADLINE_EXPIRED);
        }
    }

    fn assert_content_addressed(uri: @ByteArray) {
        let valid_uri = bytearray_starts_with(uri, @"ipfs://")
            || bytearray_starts_with(uri, @"ar://");
        assert(valid_uri, Errors::INVALID_URI);
    }
}
