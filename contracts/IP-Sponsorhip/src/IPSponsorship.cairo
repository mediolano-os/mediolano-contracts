// IP-Sponsorship — permissionless sponsorship on ERC-721 IP assets.
//
// Either side can initiate: an IP owner offers a time-bound sponsorship
// license on an asset they hold and sponsors bid on it, or a sponsor
// proposes terms directly and the owner accepts or rejects (any ERC-721 —
// the asset layer is the registry; this contract keeps none). Bids and
// proposals are allowance-based — no escrow, the contract never holds
// funds; on acceptance, payment settles sponsor → author directly and a
// license mints atomically, as a standard ERC-721 token of this same
// contract — one contract is both the registry and the license collection,
// so minting only ever happens from inside accept_bid/accept_proposal, with
// no cross-contract permission to hand out.
// Retracting a bid or withdrawing a proposal is advisory against an
// acceptance in flight in the same block; revoking the ERC-20 allowance is
// the guaranteed cancel, as acceptance settles against that allowance.
// An issued license cannot be revoked by anyone — it runs to its expiry.
// No contract owner, no admin, no fee.
#[starknet::contract]
pub mod IPSponsorship {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::interface::{
        IERC721Dispatcher, IERC721DispatcherTrait, IERC721Metadata, IERC721MetadataCamelOnly,
    };
    use openzeppelin_token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{IIPSponsorship, IIP_SPONSORSHIP_ID, ILICENSED_COLLECTION_ID};
    use crate::types::{LicenseRecord, SponsorshipOffer, SponsorshipProposal, bytearray_starts_with};

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
        last_offer_id: u256,
        offers: Map<u256, SponsorshipOffer>,
        // offer_id → sponsor → current bid amount (0 = no standing bid).
        // One standing bid per sponsor per offer; rebidding overwrites.
        // History lives in events; no enumerable bid lists on-chain.
        bids: Map<(u256, ContractAddress), u256>,
        last_proposal_id: u256,
        proposals: Map<u256, SponsorshipProposal>,
        last_license_id: u256,
        licenses: Map<u256, LicenseRecord>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        OfferCreated: OfferCreated,
        OfferStatusUpdated: OfferStatusUpdated,
        BidPlaced: BidPlaced,
        BidRetracted: BidRetracted,
        SponsorshipAccepted: SponsorshipAccepted,
        ProposalCreated: ProposalCreated,
        ProposalClosed: ProposalClosed,
        ProposalAccepted: ProposalAccepted,
        LicenseMinted: LicenseMinted,
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
        pub royalty_bps: u256,
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
    pub struct ProposalCreated {
        #[key]
        pub proposal_id: u256,
        #[key]
        pub proposer: ContractAddress,
        #[key]
        pub nft_contract: ContractAddress,
        pub token_id: u256,
        pub amount: u256,
        pub duration: u64,
        pub valid_until: u64,
        pub payment_token: ContractAddress,
        pub license_terms_uri: ByteArray,
        pub transferable: bool,
        pub royalty_bps: u256,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalClosed {
        #[key]
        pub proposal_id: u256,
        pub accepted: bool,
        pub closed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalAccepted {
        #[key]
        pub proposal_id: u256,
        #[key]
        pub license_id: u256,
        #[key]
        pub sponsor: ContractAddress,
        pub author: ContractAddress,
        pub amount: u256,
        pub expires_at: u64,
    }

    // The full declarative facts of an issued license, event-sourced rather
    // than kept in permanent storage — an indexer or integrator reconstructs
    // the deal from this log; only royalty_bps/license_terms_uri/author live
    // on in LicenseRecord for royalty_info()/token_uri() to read.
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
        self.src5.register_interface(IIP_SPONSORSHIP_ID);
        self.src5.register_interface(IERC2981_ID);
        self.src5.register_interface(ILICENSED_COLLECTION_ID);
    }

    // Each license has its own metadata URI (the offer/proposal's declared
    // license_terms_uri) — not a shared collection base_uri + token_id.
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
            self.licenses.entry(token_id).read().license_terms_uri
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.erc721._require_owned(tokenId);
            self.licenses.entry(tokenId).read().license_terms_uri
        }
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
            royalty_bps: u256,
            specific_sponsor: Option<ContractAddress>,
        ) -> u256 {
            let author = get_caller_address();
            assert(!author.is_zero(), 'Author is zero address');
            self
                .assert_valid_terms(
                    nft_contract, payment_token, duration, royalty_bps, @license_terms_uri,
                );

            if let Option::Some(sponsor) = specific_sponsor {
                assert(!sponsor.is_zero(), 'Sponsor is zero address');
            }

            self.assert_is_ip_owner(nft_contract, token_id, author);

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
                royalty_bps,
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
                        royalty_bps,
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

            // Effects before interactions: the offer closes and the accepted
            // bid is consumed before any external call.
            offer.open = false;
            self.offers.entry(offer_id).write(offer.clone());
            self.bids.entry((offer_id, sponsor)).write(0);

            let (license_id, expires_at) = self
                .settle_and_mint(
                    caller,
                    sponsor,
                    offer.nft_contract,
                    offer.token_id,
                    offer.payment_token,
                    amount,
                    offer.duration,
                    offer.transferable,
                    offer.royalty_bps,
                    offer.license_terms_uri.clone(),
                );

            self
                .emit(
                    SponsorshipAccepted {
                        offer_id, license_id, sponsor, author: caller, amount, expires_at,
                    },
                );

            license_id
        }

        fn propose_sponsorship(
            ref self: ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            amount: u256,
            duration: u64,
            valid_until: u64,
            payment_token: ContractAddress,
            license_terms_uri: ByteArray,
            transferable: bool,
            royalty_bps: u256,
        ) -> u256 {
            let proposer = get_caller_address();
            assert(!proposer.is_zero(), 'Proposer is zero address');
            assert(amount > 0, 'Amount cannot be zero');
            assert(valid_until == 0 || valid_until > get_block_timestamp(), 'Deadline in the past');
            self
                .assert_valid_terms(
                    nft_contract, payment_token, duration, royalty_bps, @license_terms_uri,
                );

            let proposal_id = self.last_proposal_id.read() + 1;
            self
                .proposals
                .entry(proposal_id)
                .write(
                    SponsorshipProposal {
                        proposer,
                        nft_contract,
                        token_id,
                        amount,
                        duration,
                        valid_until,
                        payment_token,
                        license_terms_uri: license_terms_uri.clone(),
                        transferable,
                        open: true,
                        royalty_bps,
                    },
                );
            self.last_proposal_id.write(proposal_id);

            self
                .emit(
                    ProposalCreated {
                        proposal_id,
                        proposer,
                        nft_contract,
                        token_id,
                        amount,
                        duration,
                        valid_until,
                        payment_token,
                        license_terms_uri,
                        transferable,
                        royalty_bps,
                        created_at: get_block_timestamp(),
                    },
                );
            proposal_id
        }

        fn withdraw_proposal(ref self: ContractState, proposal_id: u256) {
            let mut proposal = self.proposals.entry(proposal_id).read();
            assert(!proposal.proposer.is_zero(), 'Proposal does not exist');
            assert(proposal.proposer == get_caller_address(), 'Only proposer');
            assert(proposal.open, 'Proposal not open');

            proposal.open = false;
            self.proposals.entry(proposal_id).write(proposal);

            self
                .emit(
                    ProposalClosed {
                        proposal_id, accepted: false, closed_at: get_block_timestamp(),
                    },
                );
        }

        fn reject_proposal(ref self: ContractState, proposal_id: u256) {
            let mut proposal = self.proposals.entry(proposal_id).read();
            assert(!proposal.proposer.is_zero(), 'Proposal does not exist');
            assert(proposal.open, 'Proposal not open');

            // Effects before interactions: close before the external
            // ownership read; a failing assert reverts the write.
            proposal.open = false;
            self.proposals.entry(proposal_id).write(proposal.clone());

            self.assert_is_ip_owner(proposal.nft_contract, proposal.token_id, get_caller_address());

            self
                .emit(
                    ProposalClosed {
                        proposal_id, accepted: false, closed_at: get_block_timestamp(),
                    },
                );
        }

        fn accept_proposal(ref self: ContractState, proposal_id: u256) -> u256 {
            let caller = get_caller_address();
            let mut proposal = self.proposals.entry(proposal_id).read();
            assert(!proposal.proposer.is_zero(), 'Proposal does not exist');
            assert(proposal.open, 'Proposal not open');
            let now = get_block_timestamp();
            assert(proposal.valid_until == 0 || now <= proposal.valid_until, 'Proposal expired');

            proposal.open = false;
            self.proposals.entry(proposal_id).write(proposal.clone());

            let (license_id, expires_at) = self
                .settle_and_mint(
                    caller,
                    proposal.proposer,
                    proposal.nft_contract,
                    proposal.token_id,
                    proposal.payment_token,
                    proposal.amount,
                    proposal.duration,
                    proposal.transferable,
                    proposal.royalty_bps,
                    proposal.license_terms_uri.clone(),
                );

            self.emit(ProposalClosed { proposal_id, accepted: true, closed_at: now });
            self
                .emit(
                    ProposalAccepted {
                        proposal_id,
                        license_id,
                        sponsor: proposal.proposer,
                        author: caller,
                        amount: proposal.amount,
                        expires_at,
                    },
                );

            license_id
        }

        fn get_proposal(self: @ContractState, proposal_id: u256) -> SponsorshipProposal {
            let proposal = self.proposals.entry(proposal_id).read();
            assert(!proposal.proposer.is_zero(), 'Proposal does not exist');
            proposal
        }

        fn get_last_proposal_id(self: @ContractState) -> u256 {
            self.last_proposal_id.read()
        }

        fn get_offer(self: @ContractState, offer_id: u256) -> SponsorshipOffer {
            let offer = self.offers.entry(offer_id).read();
            assert(!offer.author.is_zero(), 'Offer does not exist');
            offer
        }

        fn get_bid(self: @ContractState, offer_id: u256, sponsor: ContractAddress) -> u256 {
            self.bids.entry((offer_id, sponsor)).read()
        }

        fn get_last_offer_id(self: @ContractState) -> u256 {
            self.last_offer_id.read()
        }

        fn get_last_license_id(self: @ContractState) -> u256 {
            self.last_license_id.read()
        }

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.erc721._require_owned(token_id);
            let record = self.licenses.entry(token_id).read();
            (record.author, (sale_price * record.royalty_bps) / 10000)
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

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Shared by create_offer and propose_sponsorship — both open a term
        // sheet on an asset and only differ in who initiates and what's
        // negotiable (a bid floor vs. a fixed take-it-or-leave-it amount).
        fn assert_valid_terms(
            self: @ContractState,
            nft_contract: ContractAddress,
            payment_token: ContractAddress,
            duration: u64,
            royalty_bps: u256,
            license_terms_uri: @ByteArray,
        ) {
            assert(duration > 0, 'Duration cannot be zero');
            assert(!payment_token.is_zero(), 'Payment token is zero');
            assert(!nft_contract.is_zero(), 'NFT contract is zero');
            assert(royalty_bps <= 10000, 'Royalty exceeds 10000');
            // License terms must be content-addressed so the agreement stays
            // verifiable independently of any gateway (Berne-aligned record).
            let valid_uri = bytearray_starts_with(license_terms_uri, @"ipfs://")
                || bytearray_starts_with(license_terms_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');
        }

        // The asset layer is the registry: `caller` must own the IP right
        // now, at offer/proposal creation, at acceptance, and at rejection.
        fn assert_is_ip_owner(
            self: @ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            caller: ContractAddress,
        ) {
            let nft = IERC721Dispatcher { contract_address: nft_contract };
            assert(nft.owner_of(token_id) == caller, 'Not IP owner');
        }

        // The author must still own the IP they are licensing (an offer or
        // proposal does not survive the sale of the underlying asset),
        // payment settles sponsor → author directly against the allowance
        // the sponsor holds open, and the license mints to the sponsor —
        // all atomically, so a failing transfer reverts the mint too. Minting
        // is only ever reachable from here — there is no external mint entry
        // point at all, so no cross-contract permission is needed to gate it.
        // Returns (license_id, expires_at).
        fn settle_and_mint(
            ref self: ContractState,
            author: ContractAddress,
            sponsor: ContractAddress,
            nft_contract: ContractAddress,
            token_id: u256,
            payment_token: ContractAddress,
            amount: u256,
            duration: u64,
            transferable: bool,
            royalty_bps: u256,
            license_terms_uri: ByteArray,
        ) -> (u256, u64) {
            self.assert_is_ip_owner(nft_contract, token_id, author);

            let expires_at = get_block_timestamp() + duration;
            let license_id = self.last_license_id.read() + 1;
            self.last_license_id.write(license_id);
            self
                .licenses
                .entry(license_id)
                .write(
                    LicenseRecord {
                        author, royalty_bps, license_terms_uri: license_terms_uri.clone(),
                    },
                );
            self.erc721.mint(sponsor, license_id);

            self
                .emit(
                    LicenseMinted {
                        token_id: license_id,
                        recipient: sponsor,
                        author,
                        asset_contract: nft_contract,
                        asset_token_id: token_id,
                        expires_at,
                        transferable,
                        royalty_bps,
                        license_terms_uri,
                        minted_at: get_block_timestamp(),
                    },
                );

            let token = IERC20Dispatcher { contract_address: payment_token };
            let result = token.transfer_from(sponsor, author, amount);
            assert(result, 'Token Transfer Failed');

            (license_id, expires_at)
        }
    }
}
