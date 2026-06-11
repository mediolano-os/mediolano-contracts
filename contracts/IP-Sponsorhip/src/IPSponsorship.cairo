// IP-Sponsorship v2 — permissionless sponsorship offers on ERC-721 IP assets.
//
// An IP owner offers a time-bound sponsorship license on an asset they hold
// (any ERC-721 — the asset layer is the registry; this contract keeps none).
// Sponsors signal bids (allowance-based — no escrow, the contract never holds
// funds); the author accepts one, payment settles sponsor → author directly,
// and a license record is issued. An issued license cannot be revoked by
// anyone — it runs to its expiry. No contract owner, no admin, no fee.
#[starknet::contract]
pub mod IPSponsorship {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{IIPSponsorship, IIP_SPONSORSHIP_ID};
    use crate::types::{License, SponsorshipOffer, bytearray_starts_with};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        last_offer_id: u256,
        last_license_id: u256,
        offers: Map<u256, SponsorshipOffer>,
        // offer_id → sponsor → current bid amount (0 = no standing bid).
        // One standing bid per sponsor per offer; rebidding overwrites.
        // History lives in events; no enumerable bid lists on-chain.
        bids: Map<(u256, ContractAddress), u256>,
        licenses: Map<u256, License>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        OfferCreated: OfferCreated,
        OfferStatusUpdated: OfferStatusUpdated,
        BidPlaced: BidPlaced,
        BidRetracted: BidRetracted,
        SponsorshipAccepted: SponsorshipAccepted,
        LicenseTransferred: LicenseTransferred,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OfferCreated {
        #[key]
        pub offer_id: u256,
        #[key]
        pub author: ContractAddress,
        #[key]
        pub nft_contract: ContractAddress,
        pub token_id: u256,
        pub min_amount: u256,
        pub duration: u64,
        pub payment_token: ContractAddress,
        pub license_terms_uri: ByteArray,
        pub transferable: bool,
        pub specific_sponsor: Option<ContractAddress>,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OfferStatusUpdated {
        #[key]
        pub offer_id: u256,
        pub open: bool,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BidPlaced {
        #[key]
        pub offer_id: u256,
        #[key]
        pub sponsor: ContractAddress,
        pub amount: u256,
        pub bid_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BidRetracted {
        #[key]
        pub offer_id: u256,
        #[key]
        pub sponsor: ContractAddress,
        pub retracted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SponsorshipAccepted {
        #[key]
        pub offer_id: u256,
        #[key]
        pub license_id: u256,
        #[key]
        pub sponsor: ContractAddress,
        pub author: ContractAddress,
        pub amount: u256,
        pub expires_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LicenseTransferred {
        #[key]
        pub license_id: u256,
        #[key]
        pub from: ContractAddress,
        #[key]
        pub to: ContractAddress,
        pub transferred_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.src5.register_interface(IIP_SPONSORSHIP_ID);
    }

    #[abi(embed_v0)]
    impl IPSponsorshipImpl of IIPSponsorship<ContractState> {
        fn create_offer(
            ref self: ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            min_amount: u256,
            duration: u64,
            payment_token: ContractAddress,
            license_terms_uri: ByteArray,
            transferable: bool,
            specific_sponsor: Option<ContractAddress>,
        ) -> u256 {
            let author = get_caller_address();
            assert(!author.is_zero(), 'Author is zero address');
            assert(duration > 0, 'Duration cannot be zero');
            assert(!payment_token.is_zero(), 'Payment token is zero');
            assert(!nft_contract.is_zero(), 'NFT contract is zero');

            // License terms must be content-addressed so the agreement stays
            // verifiable independently of any gateway (Berne-aligned record).
            let valid_uri = bytearray_starts_with(@license_terms_uri, @"ipfs://")
                || bytearray_starts_with(@license_terms_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if let Option::Some(sponsor) = specific_sponsor {
                assert(!sponsor.is_zero(), 'Sponsor is zero address');
            }

            // The asset layer is the registry: the caller must own the IP
            // they are offering a license on, right now.
            let nft = IERC721Dispatcher { contract_address: nft_contract };
            assert(nft.owner_of(token_id) == author, 'Not IP owner');

            let offer_id = self.last_offer_id.read() + 1;
            let offer = SponsorshipOffer {
                author,
                nft_contract,
                token_id,
                min_amount,
                duration,
                payment_token,
                license_terms_uri: license_terms_uri.clone(),
                transferable,
                specific_sponsor,
                open: true,
            };

            self.offers.entry(offer_id).write(offer);
            self.last_offer_id.write(offer_id);

            self
                .emit(
                    OfferCreated {
                        offer_id,
                        author,
                        nft_contract,
                        token_id,
                        min_amount,
                        duration,
                        payment_token,
                        license_terms_uri,
                        transferable,
                        specific_sponsor,
                        created_at: get_block_timestamp(),
                    },
                );

            offer_id
        }

        fn set_offer_open(ref self: ContractState, offer_id: u256, open: bool) {
            let mut offer = self.offers.entry(offer_id).read();
            assert(!offer.author.is_zero(), 'Offer does not exist');
            assert(offer.author == get_caller_address(), 'Only offer author');

            offer.open = open;
            self.offers.entry(offer_id).write(offer);

            self.emit(OfferStatusUpdated { offer_id, open, updated_at: get_block_timestamp() });
        }

        fn place_bid(ref self: ContractState, offer_id: u256, amount: u256) {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Bidder is zero address');

            let offer = self.offers.entry(offer_id).read();
            assert(!offer.author.is_zero(), 'Offer does not exist');
            assert(offer.open, 'Offer not open');
            assert(amount > 0, 'Bid cannot be zero');
            assert(amount >= offer.min_amount, 'Bid below minimum');

            if let Option::Some(sponsor) = offer.specific_sponsor {
                assert(caller == sponsor, 'Not the invited sponsor');
            }

            // A bid is a signal plus an ERC-20 allowance the sponsor holds
            // open; no tokens move until the author accepts. Rebidding
            // overwrites the standing bid.
            self.bids.entry((offer_id, caller)).write(amount);

            self
                .emit(
                    BidPlaced { offer_id, sponsor: caller, amount, bid_at: get_block_timestamp() },
                );
        }

        fn retract_bid(ref self: ContractState, offer_id: u256) {
            let caller = get_caller_address();
            let standing = self.bids.entry((offer_id, caller)).read();
            assert(standing > 0, 'No standing bid');

            self.bids.entry((offer_id, caller)).write(0);

            self
                .emit(
                    BidRetracted { offer_id, sponsor: caller, retracted_at: get_block_timestamp() },
                );
        }

        fn accept_bid(ref self: ContractState, offer_id: u256, sponsor: ContractAddress) -> u256 {
            let caller = get_caller_address();
            let mut offer = self.offers.entry(offer_id).read();
            assert(!offer.author.is_zero(), 'Offer does not exist');
            assert(offer.author == caller, 'Only offer author');
            assert(offer.open, 'Offer not open');

            let amount = self.bids.entry((offer_id, sponsor)).read();
            assert(amount > 0, 'No standing bid');

            // The author must still own the IP they are licensing — an offer
            // does not survive the sale of the underlying asset.
            let nft = IERC721Dispatcher { contract_address: offer.nft_contract };
            assert(nft.owner_of(offer.token_id) == caller, 'Not IP owner');

            let now = get_block_timestamp();
            let expires_at = now + offer.duration;
            let license_id = self.last_license_id.read() + 1;

            let license = License {
                author: caller,
                sponsor,
                nft_contract: offer.nft_contract,
                token_id: offer.token_id,
                amount_paid: amount,
                expires_at,
                transferable: offer.transferable,
                license_terms_uri: offer.license_terms_uri.clone(),
            };

            // Effects before the payment interaction: offer closes, the
            // accepted bid is consumed, the license is recorded.
            offer.open = false;
            let payment_token = offer.payment_token;
            self.offers.entry(offer_id).write(offer);
            self.bids.entry((offer_id, sponsor)).write(0);
            self.licenses.entry(license_id).write(license);
            self.last_license_id.write(license_id);

            // Settlement: sponsor → author directly, against the allowance
            // the sponsor holds open. No escrow — a failing transfer reverts
            // the whole acceptance atomically.
            let token = IERC20Dispatcher { contract_address: payment_token };
            let result = token.transfer_from(sponsor, caller, amount);
            assert(result, 'Token Transfer Failed');

            self
                .emit(
                    SponsorshipAccepted {
                        offer_id, license_id, sponsor, author: caller, amount, expires_at,
                    },
                );

            license_id
        }

        fn transfer_license(ref self: ContractState, license_id: u256, to: ContractAddress) {
            let caller = get_caller_address();
            assert(!to.is_zero(), 'Recipient is zero address');

            let mut license = self.licenses.entry(license_id).read();
            assert(!license.author.is_zero(), 'License does not exist');
            assert(license.sponsor == caller, 'Only license holder');
            assert(license.transferable, 'License not transferable');
            assert(license.expires_at >= get_block_timestamp(), 'License expired');

            license.sponsor = to;
            self.licenses.entry(license_id).write(license);

            self
                .emit(
                    LicenseTransferred {
                        license_id, from: caller, to, transferred_at: get_block_timestamp(),
                    },
                );
        }

        fn get_offer(self: @ContractState, offer_id: u256) -> SponsorshipOffer {
            let offer = self.offers.entry(offer_id).read();
            assert(!offer.author.is_zero(), 'Offer does not exist');
            offer
        }

        fn get_bid(self: @ContractState, offer_id: u256, sponsor: ContractAddress) -> u256 {
            self.bids.entry((offer_id, sponsor)).read()
        }

        fn get_license(self: @ContractState, license_id: u256) -> License {
            let license = self.licenses.entry(license_id).read();
            assert(!license.author.is_zero(), 'License does not exist');
            license
        }

        fn is_license_valid(self: @ContractState, license_id: u256) -> bool {
            let license = self.licenses.entry(license_id).read();
            !license.author.is_zero() && license.expires_at >= get_block_timestamp()
        }

        fn get_last_offer_id(self: @ContractState) -> u256 {
            self.last_offer_id.read()
        }

        fn get_last_license_id(self: @ContractState) -> u256 {
            self.last_license_id.read()
        }
    }
}
