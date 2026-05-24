#[starknet::contract]
pub mod IPCommissionEscrow {
    use core::num::traits::Zero;
    use ip_commission_escrow::errors::Errors;
    use ip_commission_escrow::interface::{IIPCommissionEscrow, IIP_COMMISSION_ESCROW_ID};
    use ip_commission_escrow::types::{
        Commission, CommissionStatus, MilestoneDetails, MilestoneStatus, OfferMode,
        bytearray_starts_with,
    };
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
        last_commission_id: u256,
        commissions: Map<u256, Commission>,
        milestones: Map<(u256, u32), MilestoneDetails>,
        token_uris: Map<u256, ByteArray>,
        deliverable_uris: Map<(u256, u32), ByteArray>,
        creator_claims: Map<(u256, ContractAddress), u256>,
        commissioner_refunds: Map<(u256, ContractAddress), u256>,
        reentrancy_locked: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        CommissionCreated: CommissionCreated,
        CommissionFunded: CommissionFunded,
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
        pub mode: OfferMode,
        pub milestone_count: u32,
        pub brief_uri: ByteArray,
        pub license_uri: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionFunded {
        #[key]
        pub commission_id: u256,
        #[key]
        pub commissioner: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommissionAccepted {
        #[key]
        pub commission_id: u256,
        #[key]
        pub creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneSubmitted {
        #[key]
        pub commission_id: u256,
        #[key]
        pub milestone_index: u32,
        #[key]
        pub creator: ContractAddress,
        pub deliverable_uri: ByteArray,
        pub deliverable_hash: felt252,
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
            "Mediolano Commission Offer"
        }

        fn symbol(self: @ContractState) -> ByteArray {
            "MCOM"
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.token_uris.entry(token_id).read()
        }
    }

    #[abi(embed_v0)]
    pub impl CommissionEscrowImpl of IIPCommissionEscrow<ContractState> {
        fn create_commission(
            ref self: ContractState,
            invited_creator: ContractAddress,
            payment_token: ContractAddress,
            total_amount: u256,
            brief_uri: ByteArray,
            brief_hash: felt252,
            license_uri: ByteArray,
            license_hash: felt252,
            revisions_allowed: u32,
            deadline: u64,
            milestone_amounts: Array<u256>,
        ) -> u256 {
            let commissioner = get_caller_address();
            assert(!commissioner.is_zero(), Errors::INVALID_CREATOR);
            assert(!payment_token.is_zero(), Errors::INVALID_PAYMENT_TOKEN);
            assert(total_amount > 0, Errors::AMOUNT_IS_ZERO);
            assert(brief_hash != 0, Errors::INVALID_HASH);
            assert(license_hash != 0, Errors::INVALID_HASH);
            assert_content_addressed(@brief_uri);
            assert_content_addressed(@license_uri);
            assert(deadline > get_block_timestamp(), Errors::DEADLINE_EXPIRED);

            let milestone_count = milestone_amounts.len();
            assert(milestone_count > 0, Errors::INVALID_MILESTONES);

            let commission_id = self.last_commission_id.read() + 1;
            let mode = if invited_creator.is_zero() {
                OfferMode::Open
            } else {
                assert(invited_creator != commissioner, Errors::INVALID_CREATOR);
                OfferMode::Exclusive
            };

            let mut total_from_milestones: u256 = 0;
            let mut index: u32 = 0;
            loop {
                if index == milestone_count {
                    break;
                }
                let amount = *milestone_amounts.at(index);
                assert(amount > 0, Errors::AMOUNT_IS_ZERO);
                total_from_milestones += amount;
                self
                    .milestones
                    .entry((commission_id, index))
                    .write(
                        MilestoneDetails {
                            commission_id,
                            milestone_index: index,
                            amount,
                            status: MilestoneStatus::Pending,
                            revision_count: 0,
                            deliverable_hash: 0,
                            submitted_at: 0,
                            approved_at: 0,
                            exists: true,
                        },
                    );
                index += 1;
            }
            assert(total_from_milestones == total_amount, Errors::INVALID_MILESTONES);

            let commission = Commission {
                commission_id,
                commissioner,
                invited_creator,
                creator: Zero::zero(),
                payment_token,
                total_amount,
                escrowed_amount: 0,
                released_amount: 0,
                refunded_amount: 0,
                milestone_count,
                approved_milestone_count: 0,
                revisions_allowed,
                deadline,
                status: CommissionStatus::Open,
                mode,
                brief_uri: brief_uri.clone(),
                brief_hash,
                license_uri: license_uri.clone(),
                license_hash,
                exists: true,
            };

            self.commissions.entry(commission_id).write(commission);
            self.token_uris.entry(commission_id).write(brief_uri.clone());
            self.last_commission_id.write(commission_id);
            self.erc721.mint(commissioner, commission_id);

            self
                .emit(
                    CommissionCreated {
                        commission_id,
                        commissioner,
                        invited_creator,
                        payment_token,
                        total_amount,
                        mode,
                        milestone_count,
                        brief_uri,
                        license_uri,
                    },
                );

            commission_id
        }

        fn fund_commission(ref self: ContractState, commission_id: u256) -> u256 {
            self.enter_non_reentrant();
            let caller = get_caller_address();
            let mut commission = self.get_existing_commission(commission_id);
            assert(caller == commission.commissioner, Errors::NOT_COMMISSIONER);
            assert(commission.status == CommissionStatus::Open, Errors::INVALID_STATUS);

            let token = IERC20Dispatcher { contract_address: commission.payment_token };
            let contract_address = get_contract_address();
            let balance_before = token.balance_of(contract_address);
            let success = token.transfer_from(caller, contract_address, commission.total_amount);
            assert(success, Errors::PAYMENT_FAILED);
            let balance_after = token.balance_of(contract_address);
            assert(
                balance_after - balance_before == commission.total_amount, Errors::PAYMENT_FAILED,
            );

            commission.escrowed_amount = commission.total_amount;
            commission.status = CommissionStatus::Funded;
            let funded_amount = commission.total_amount;
            self.commissions.entry(commission_id).write(commission);
            self.exit_non_reentrant();

            self
                .emit(
                    CommissionFunded { commission_id, commissioner: caller, amount: funded_amount },
                );

            funded_amount
        }

        fn accept_commission(ref self: ContractState, commission_id: u256) {
            let caller = get_caller_address();
            let mut commission = self.get_existing_commission(commission_id);
            assert(commission.status == CommissionStatus::Funded, Errors::INVALID_STATUS);
            self.assert_before_deadline(commission.deadline);
            assert(caller != commission.commissioner, Errors::INVALID_CREATOR);
            if commission.mode == OfferMode::Exclusive {
                assert(caller == commission.invited_creator, Errors::NOT_INVITED_CREATOR);
            }

            commission.creator = caller;
            commission.status = CommissionStatus::InProgress;
            self.commissions.entry(commission_id).write(commission);
            self.emit(CommissionAccepted { commission_id, creator: caller });
        }

        fn submit_milestone(
            ref self: ContractState,
            commission_id: u256,
            milestone_index: u32,
            deliverable_uri: ByteArray,
            deliverable_hash: felt252,
        ) {
            let caller = get_caller_address();
            let commission = self.get_existing_commission(commission_id);
            assert(commission.status == CommissionStatus::InProgress, Errors::INVALID_STATUS);
            self.assert_before_deadline(commission.deadline);
            assert(caller == commission.creator, Errors::NOT_CREATOR);
            assert(deliverable_hash != 0, Errors::INVALID_HASH);
            assert_content_addressed(@deliverable_uri);

            if milestone_index > 0 {
                let previous = self.get_existing_milestone(commission_id, milestone_index - 1);
                assert(
                    previous.status == MilestoneStatus::Approved, Errors::PREVIOUS_MILESTONE_OPEN,
                );
            }

            let mut milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(
                milestone.status == MilestoneStatus::Pending
                    || milestone.status == MilestoneStatus::RevisionRequested,
                Errors::INVALID_STATUS,
            );
            milestone.status = MilestoneStatus::Submitted;
            milestone.deliverable_hash = deliverable_hash;
            milestone.submitted_at = get_block_timestamp();
            self.milestones.entry((commission_id, milestone_index)).write(milestone);
            self
                .deliverable_uris
                .entry((commission_id, milestone_index))
                .write(deliverable_uri.clone());

            self
                .emit(
                    MilestoneSubmitted {
                        commission_id,
                        milestone_index,
                        creator: caller,
                        deliverable_uri,
                        deliverable_hash,
                    },
                );
        }

        fn request_revision(ref self: ContractState, commission_id: u256, milestone_index: u32) {
            let caller = get_caller_address();
            let commission = self.get_existing_commission(commission_id);
            assert(caller == commission.commissioner, Errors::NOT_COMMISSIONER);
            assert(commission.status == CommissionStatus::InProgress, Errors::INVALID_STATUS);

            let mut milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(milestone.status == MilestoneStatus::Submitted, Errors::INVALID_STATUS);
            assert(
                milestone.revision_count < commission.revisions_allowed,
                Errors::REVISION_LIMIT_REACHED,
            );
            milestone.revision_count += 1;
            milestone.status = MilestoneStatus::RevisionRequested;
            self.milestones.entry((commission_id, milestone_index)).write(milestone);

            self
                .emit(
                    MilestoneRevisionRequested {
                        commission_id, milestone_index, revision_count: milestone.revision_count,
                    },
                );
        }

        fn approve_milestone(ref self: ContractState, commission_id: u256, milestone_index: u32) {
            let caller = get_caller_address();
            let mut commission = self.get_existing_commission(commission_id);
            assert(caller == commission.commissioner, Errors::NOT_COMMISSIONER);
            assert(commission.status == CommissionStatus::InProgress, Errors::INVALID_STATUS);

            let mut milestone = self.get_existing_milestone(commission_id, milestone_index);
            assert(milestone.status == MilestoneStatus::Submitted, Errors::INVALID_STATUS);
            milestone.status = MilestoneStatus::Approved;
            milestone.approved_at = get_block_timestamp();

            commission.released_amount += milestone.amount;
            commission.approved_milestone_count += 1;
            let claim_key = (commission_id, commission.creator);
            let creator_claim = self.creator_claims.entry(claim_key).read() + milestone.amount;
            self.creator_claims.entry(claim_key).write(creator_claim);

            if commission.approved_milestone_count == commission.milestone_count {
                commission.status = CommissionStatus::Completed;
            }
            let is_completed = commission.status == CommissionStatus::Completed;
            let released_amount = commission.released_amount;

            self.milestones.entry((commission_id, milestone_index)).write(milestone);
            self.commissions.entry(commission_id).write(commission);

            self
                .emit(
                    MilestoneApproved { commission_id, milestone_index, amount: milestone.amount },
                );
            if is_completed {
                self.emit(CommissionCompleted { commission_id, released_amount });
            }
        }

        fn cancel_commission(ref self: ContractState, commission_id: u256) {
            let caller = get_caller_address();
            let mut commission = self.get_existing_commission(commission_id);
            assert(caller == commission.commissioner, Errors::NOT_COMMISSIONER);
            let cancellable_before_accept = commission.status == CommissionStatus::Open
                || commission.status == CommissionStatus::Funded;
            let cancellable_after_deadline = commission.status == CommissionStatus::InProgress
                && get_block_timestamp() > commission.deadline;
            assert(cancellable_before_accept || cancellable_after_deadline, Errors::INVALID_STATUS);

            let refund_amount = commission.escrowed_amount
                - commission.released_amount
                - commission.refunded_amount;
            commission.status = CommissionStatus::Cancelled;
            commission.refunded_amount += refund_amount;
            self.commissions.entry(commission_id).write(commission);
            if refund_amount > 0 {
                let refund_key = (commission_id, caller);
                let refund = self.commissioner_refunds.entry(refund_key).read() + refund_amount;
                self.commissioner_refunds.entry(refund_key).write(refund);
            }

            self.emit(CommissionCancelled { commission_id, refund_amount });
        }

        fn claim_creator_funds(ref self: ContractState, commission_id: u256) -> u256 {
            self.enter_non_reentrant();
            let caller = get_caller_address();
            let commission = self.get_existing_commission(commission_id);
            assert(caller == commission.creator, Errors::NOT_CREATOR);
            let key = (commission_id, caller);
            let amount = self.creator_claims.entry(key).read();
            assert(amount > 0, Errors::NOTHING_TO_CLAIM);
            self.creator_claims.entry(key).write(0);

            let token = IERC20Dispatcher { contract_address: commission.payment_token };
            let success = token.transfer(caller, amount);
            assert(success, Errors::PAYMENT_FAILED);
            self.exit_non_reentrant();

            self.emit(CreatorFundsClaimed { commission_id, creator: caller, amount });
            amount
        }

        fn claim_commissioner_refund(ref self: ContractState, commission_id: u256) -> u256 {
            self.enter_non_reentrant();
            let caller = get_caller_address();
            let commission = self.get_existing_commission(commission_id);
            assert(caller == commission.commissioner, Errors::NOT_COMMISSIONER);
            let key = (commission_id, caller);
            let amount = self.commissioner_refunds.entry(key).read();
            assert(amount > 0, Errors::NOTHING_TO_CLAIM);
            self.commissioner_refunds.entry(key).write(0);

            let token = IERC20Dispatcher { contract_address: commission.payment_token };
            let success = token.transfer(caller, amount);
            assert(success, Errors::PAYMENT_FAILED);
            self.exit_non_reentrant();

            self.emit(CommissionerRefundClaimed { commission_id, commissioner: caller, amount });
            amount
        }

        fn get_commission(self: @ContractState, commission_id: u256) -> Commission {
            self.get_existing_commission(commission_id)
        }

        fn get_milestone(
            self: @ContractState, commission_id: u256, milestone_index: u32,
        ) -> MilestoneDetails {
            self.get_existing_milestone(commission_id, milestone_index)
        }

        fn get_milestone_deliverable_uri(
            self: @ContractState, commission_id: u256, milestone_index: u32,
        ) -> ByteArray {
            self.get_existing_milestone(commission_id, milestone_index);
            self.deliverable_uris.entry((commission_id, milestone_index)).read()
        }

        fn get_claimable_creator_funds(
            self: @ContractState, commission_id: u256, creator: ContractAddress,
        ) -> u256 {
            self.creator_claims.entry((commission_id, creator)).read()
        }

        fn get_claimable_commissioner_refund(
            self: @ContractState, commission_id: u256, commissioner: ContractAddress,
        ) -> u256 {
            self.commissioner_refunds.entry((commission_id, commissioner)).read()
        }

        fn get_last_commission_id(self: @ContractState) -> u256 {
            self.last_commission_id.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing_commission(self: @ContractState, commission_id: u256) -> Commission {
            let commission = self.commissions.entry(commission_id).read();
            assert(commission.exists, Errors::COMMISSION_NOT_FOUND);
            commission
        }

        fn get_existing_milestone(
            self: @ContractState, commission_id: u256, milestone_index: u32,
        ) -> MilestoneDetails {
            let milestone = self.milestones.entry((commission_id, milestone_index)).read();
            assert(milestone.exists, Errors::MILESTONE_NOT_FOUND);
            milestone
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
