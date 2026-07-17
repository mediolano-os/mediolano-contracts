#[starknet::contract]
pub mod IPCommissionEscrow {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{IERC721Metadata, IERC721MetadataCamelOnly};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::interface::{IIPCommissionEscrow, IIP_COMMISSION_ESCROW_ID};
    use crate::types::{
        Commission, CommissionStatus, Milestone, MilestoneStatus, bytearray_starts_with,
    };

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
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
        next_commission_id: u256,
        commissions: Map<u256, Commission>,
        milestones: Map<(u256, u32), Milestone>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        CommissionCreated: CommissionCreated,
        CommissionAccepted: CommissionAccepted,
        MilestoneSubmitted: MilestoneSubmitted,
        MilestoneRevisionRequested: MilestoneRevisionRequested,
        MilestoneApproved: MilestoneApproved,
        CommissionCompleted: CommissionCompleted,
        CommissionCancelled: CommissionCancelled,
        CreatorFundsClaimed: CreatorFundsClaimed,
        CommissionerRefundClaimed: CommissionerRefundClaimed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionCreated {
        #[key]
        pub commission_id: u256,
        #[key]
        pub commissioner: ContractAddress,
        #[key]
        pub invited_creator: ContractAddress,
        pub payment_token: ContractAddress,
        pub total_amount: u256,
        pub milestone_count: u32,
        pub deadline: u64,
        pub review_period: u64,
        pub brief_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionAccepted {
        #[key]
        pub commission_id: u256,
        #[key]
        pub creator: ContractAddress,
        pub accepted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneSubmitted {
        #[key]
        pub commission_id: u256,
        #[key]
        pub milestone_index: u32,
        pub deliverable_uri: ByteArray,
        pub submitted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneRevisionRequested {
        #[key]
        pub commission_id: u256,
        #[key]
        pub milestone_index: u32,
        pub revision_count: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneApproved {
        #[key]
        pub commission_id: u256,
        #[key]
        pub milestone_index: u32,
        pub amount: u256,
        /// The commissioner, or the creator when approval came from the
        /// review-window timeout.
        pub approver: ContractAddress,
        pub approved_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionCompleted {
        #[key]
        pub commission_id: u256,
        pub released_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionCancelled {
        #[key]
        pub commission_id: u256,
        /// The commissioner (cancel) or the creator (abandon).
        #[key]
        pub ended_by: ContractAddress,
        pub refund_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CreatorFundsClaimed {
        #[key]
        pub commission_id: u256,
        #[key]
        pub creator: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionerRefundClaimed {
        #[key]
        pub commission_id: u256,
        #[key]
        pub commissioner: ContractAddress,
        pub amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc721.initializer("Mediolano Commission Offer", "MCOM", "");
        self.src5.register_interface(IIP_COMMISSION_ESCROW_ID);
        self.next_commission_id.write(1);
    }

    /// Offer records are non-transferable: only minting (from == 0) passes.
    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let from = self._owner_of(token_id);
            assert(from.is_zero(), 'Offer is non-transferable');
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
    }

    /// token_uri resolves to the commission's brief.
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
            self.commissions.read(token_id).brief_uri
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnlyImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.token_uri(tokenId)
        }
    }

    #[abi(embed_v0)]
    pub impl IPCommissionEscrowImpl of IIPCommissionEscrow<ContractState> {
        fn create_commission(
            ref self: ContractState,
            invited_creator: ContractAddress,
            payment_token: ContractAddress,
            brief_uri: ByteArray,
            revisions_allowed: u32,
            deadline: u64,
            review_period: u64,
            milestone_amounts: Array<u256>,
        ) -> u256 {
            let commissioner = get_caller_address();
            assert(!payment_token.is_zero(), 'Payment token is zero');
            assert(deadline > get_block_timestamp(), 'Deadline in the past');
            assert(review_period > 0, 'Review period is zero');
            if !invited_creator.is_zero() {
                assert(invited_creator != commissioner, 'Invited is commissioner');
            }
            assert_content_addressed(@brief_uri);

            let milestone_count = milestone_amounts.len();
            assert(milestone_count > 0, 'No milestones');

            let commission_id = self.next_commission_id.read();
            self.next_commission_id.write(commission_id + 1);

            let mut total_amount: u256 = 0;
            let mut index: u32 = 0;
            while index < milestone_count {
                let amount = *milestone_amounts.at(index);
                assert(amount > 0, 'Milestone amount is zero');
                total_amount += amount;
                self
                    .milestones
                    .write(
                        (commission_id, index),
                        Milestone {
                            amount,
                            status: MilestoneStatus::Pending,
                            revision_count: 0,
                            submitted_at: 0,
                            deliverable_uri: "",
                        },
                    );
                index += 1;
            }

            let commission = Commission {
                commissioner,
                invited_creator,
                creator: Zero::zero(),
                payment_token,
                total_amount,
                released_amount: 0,
                milestone_count,
                approved_milestone_count: 0,
                revisions_allowed,
                deadline,
                review_period,
                status: CommissionStatus::Open,
                brief_uri: brief_uri.clone(),
                creator_claim: 0,
                commissioner_refund: 0,
            };
            self.commissions.write(commission_id, commission);

            // The offer record; mint has no receiver callback.
            self.erc721.mint(commissioner, commission_id);

            // Escrow the full budget — external call after state is final.
            let token = IERC20Dispatcher { contract_address: payment_token };
            let this = get_contract_address();
            let balance_before = token.balance_of(this);
            let success = token.transfer_from(commissioner, this, total_amount);
            assert(success, 'Payment failed');
            assert(token.balance_of(this) - balance_before >= total_amount, 'Payment failed');

            self
                .emit(
                    CommissionCreated {
                        commission_id,
                        commissioner,
                        invited_creator,
                        payment_token,
                        total_amount,
                        milestone_count,
                        deadline,
                        review_period,
                        brief_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            commission_id
        }

        fn accept_commission(ref self: ContractState, commission_id: u256) {
            let caller = get_caller_address();
            let mut commission = self.get_existing(commission_id);
            assert(commission.status == CommissionStatus::Open, 'Commission not open');
            assert(get_block_timestamp() <= commission.deadline, 'Deadline passed');
            assert(caller != commission.commissioner, 'Commissioner cannot accept');
            if !commission.invited_creator.is_zero() {
                assert(caller == commission.invited_creator, 'Not the invited creator');
            }

            commission.creator = caller;
            commission.status = CommissionStatus::InProgress;
            self.commissions.write(commission_id, commission);

            self
                .emit(
                    CommissionAccepted {
                        commission_id, creator: caller, accepted_at: get_block_timestamp(),
                    },
                );
        }

        fn submit_milestone(
            ref self: ContractState,
            commission_id: u256,
            milestone_index: u32,
            deliverable_uri: ByteArray,
        ) {
            let caller = get_caller_address();
            let commission = self.get_existing(commission_id);
            assert(commission.status == CommissionStatus::InProgress, 'Commission not in progress');
            assert(caller == commission.creator, 'Not the creator');
            assert(get_block_timestamp() <= commission.deadline, 'Deadline passed');
            assert_content_addressed(@deliverable_uri);

            if milestone_index > 0 {
                let previous = self.get_existing_milestone(commission_id, milestone_index - 1);
                assert(previous.status == MilestoneStatus::Approved, 'Previous milestone open');
            }

            let mut milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(
                milestone.status == MilestoneStatus::Pending
                    || milestone.status == MilestoneStatus::RevisionRequested,
                'Milestone not submittable',
            );

            let submitted_at = get_block_timestamp();
            milestone.status = MilestoneStatus::Submitted;
            milestone.submitted_at = submitted_at;
            milestone.deliverable_uri = deliverable_uri.clone();
            self.milestones.write((commission_id, milestone_index), milestone);

            self
                .emit(
                    MilestoneSubmitted {
                        commission_id, milestone_index, deliverable_uri, submitted_at,
                    },
                );
        }

        fn approve_milestone(ref self: ContractState, commission_id: u256, milestone_index: u32) {
            let caller = get_caller_address();
            let commission = self.get_existing(commission_id);
            assert(caller == commission.commissioner, 'Not the commissioner');
            self.approve_submitted(commission_id, milestone_index, caller);
        }

        fn request_revision(ref self: ContractState, commission_id: u256, milestone_index: u32) {
            let caller = get_caller_address();
            let commission = self.get_existing(commission_id);
            assert(caller == commission.commissioner, 'Not the commissioner');
            assert(commission.status == CommissionStatus::InProgress, 'Commission not in progress');

            let mut milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(milestone.status == MilestoneStatus::Submitted, 'Milestone not under review');
            assert(
                milestone.revision_count < commission.revisions_allowed, 'Revision limit reached',
            );

            milestone.revision_count += 1;
            milestone.status = MilestoneStatus::RevisionRequested;
            let revision_count = milestone.revision_count;
            self.milestones.write((commission_id, milestone_index), milestone);

            self
                .emit(
                    MilestoneRevisionRequested { commission_id, milestone_index, revision_count },
                );
        }

        fn claim_overdue_milestone(
            ref self: ContractState, commission_id: u256, milestone_index: u32,
        ) {
            let caller = get_caller_address();
            let commission = self.get_existing(commission_id);
            assert(caller == commission.creator, 'Not the creator');

            let milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(milestone.status == MilestoneStatus::Submitted, 'Milestone not under review');
            assert(
                get_block_timestamp() > milestone.submitted_at + commission.review_period,
                'Review window still open',
            );

            self.approve_submitted(commission_id, milestone_index, caller);
        }

        fn cancel_commission(ref self: ContractState, commission_id: u256) {
            let caller = get_caller_address();
            let mut commission = self.get_existing(commission_id);
            assert(caller == commission.commissioner, 'Not the commissioner');

            if commission.status == CommissionStatus::InProgress {
                assert(get_block_timestamp() > commission.deadline, 'Deadline not passed');
                // Sequencing allows at most one milestone under review: the
                // first unapproved one. A submission must be resolved —
                // approved, revised, or timed out — before cancel can pass it.
                if commission.approved_milestone_count < commission.milestone_count {
                    let current = self
                        .get_existing_milestone(commission_id, commission.approved_milestone_count);
                    assert(current.status != MilestoneStatus::Submitted, 'Milestone under review');
                }
            } else {
                assert(commission.status == CommissionStatus::Open, 'Commission not cancellable');
            }

            self.settle_cancellation(commission_id, ref commission, caller);
        }

        fn abandon_commission(ref self: ContractState, commission_id: u256) {
            let caller = get_caller_address();
            let mut commission = self.get_existing(commission_id);
            assert(caller == commission.creator, 'Not the creator');
            assert(commission.status == CommissionStatus::InProgress, 'Commission not in progress');

            self.settle_cancellation(commission_id, ref commission, caller);
        }

        fn claim_creator_funds(ref self: ContractState, commission_id: u256) -> u256 {
            let caller = get_caller_address();
            let mut commission = self.get_existing(commission_id);
            assert(caller == commission.creator, 'Not the creator');

            let amount = commission.creator_claim;
            assert(amount > 0, 'Nothing to claim');
            commission.creator_claim = 0;
            let payment_token = commission.payment_token;
            self.commissions.write(commission_id, commission);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let success = token.transfer(caller, amount);
            assert(success, 'Payment failed');

            self.emit(CreatorFundsClaimed { commission_id, creator: caller, amount });
            amount
        }

        fn claim_commissioner_refund(ref self: ContractState, commission_id: u256) -> u256 {
            let caller = get_caller_address();
            let mut commission = self.get_existing(commission_id);
            assert(caller == commission.commissioner, 'Not the commissioner');

            let amount = commission.commissioner_refund;
            assert(amount > 0, 'Nothing to claim');
            commission.commissioner_refund = 0;
            let payment_token = commission.payment_token;
            self.commissions.write(commission_id, commission);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let success = token.transfer(caller, amount);
            assert(success, 'Payment failed');

            self.emit(CommissionerRefundClaimed { commission_id, commissioner: caller, amount });
            amount
        }

        fn get_commission(self: @ContractState, commission_id: u256) -> Commission {
            self.get_existing(commission_id)
        }

        fn get_milestone(
            self: @ContractState, commission_id: u256, milestone_index: u32,
        ) -> Milestone {
            self.get_existing_milestone(commission_id, milestone_index)
        }

        fn commission_count(self: @ContractState) -> u256 {
            self.next_commission_id.read() - 1
        }

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing(self: @ContractState, commission_id: u256) -> Commission {
            let commission = self.commissions.read(commission_id);
            assert(!commission.commissioner.is_zero(), 'Commission not found');
            commission
        }

        fn get_existing_milestone(
            self: @ContractState, commission_id: u256, milestone_index: u32,
        ) -> Milestone {
            let milestone = self.milestones.read((commission_id, milestone_index));
            assert(milestone.amount > 0, 'Milestone not found');
            milestone
        }

        /// Approves the milestone under review: credits the creator, and
        /// completes the commission on the last approval. `approver` is the
        /// commissioner, or the creator via the review-window timeout.
        fn approve_submitted(
            ref self: ContractState,
            commission_id: u256,
            milestone_index: u32,
            approver: ContractAddress,
        ) {
            let mut commission = self.get_existing(commission_id);
            assert(commission.status == CommissionStatus::InProgress, 'Commission not in progress');

            let mut milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(milestone.status == MilestoneStatus::Submitted, 'Milestone not under review');

            milestone.status = MilestoneStatus::Approved;
            let amount = milestone.amount;
            self.milestones.write((commission_id, milestone_index), milestone);

            commission.released_amount += amount;
            commission.approved_milestone_count += 1;
            commission.creator_claim += amount;
            let completed = commission.approved_milestone_count == commission.milestone_count;
            if completed {
                commission.status = CommissionStatus::Completed;
            }
            let released_amount = commission.released_amount;
            self.commissions.write(commission_id, commission);

            self
                .emit(
                    MilestoneApproved {
                        commission_id,
                        milestone_index,
                        amount,
                        approver,
                        approved_at: get_block_timestamp(),
                    },
                );
            if completed {
                self.emit(CommissionCompleted { commission_id, released_amount });
            }
        }

        /// Shared terminal path for cancel (commissioner) and abandon
        /// (creator): unreleased escrow becomes refundable, earned
        /// milestones stay claimable.
        fn settle_cancellation(
            ref self: ContractState,
            commission_id: u256,
            ref commission: Commission,
            ended_by: ContractAddress,
        ) {
            let refund_amount = commission.total_amount - commission.released_amount;
            commission.status = CommissionStatus::Cancelled;
            commission.commissioner_refund += refund_amount;
            self.commissions.write(commission_id, commission.clone());

            self.emit(CommissionCancelled { commission_id, ended_by, refund_amount });
        }
    }

    fn assert_content_addressed(uri: @ByteArray) {
        let valid_uri = bytearray_starts_with(uri, @"ipfs://")
            || bytearray_starts_with(uri, @"ar://");
        assert(valid_uri, 'URI must be ipfs:// or ar://');
    }
}
