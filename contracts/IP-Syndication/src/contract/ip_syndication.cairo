#[starknet::contract]
pub mod IPSyndication {
    use core::num::traits::Zero;
    use ip_syndication::errors::Errors;
    use ip_syndication::interface::{IIPSyndication, IIP_SYNDICATION_ID};
    use ip_syndication::types::{
        IPMetadata, Mode, ParticipantDetails, Status, SyndicationDetails, bytearray_starts_with,
    };
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::ERC1155Component;
    use openzeppelin_token::erc1155::interface::IERC1155MetadataURI;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155CamelImpl = ERC1155Component::ERC1155CamelImpl<ContractState>;
    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        last_ip_id: u256,
        ip_metadata: Map<u256, IPMetadata>,
        syndication_details: Map<u256, SyndicationDetails>,
        whitelisted: Map<(u256, ContractAddress), bool>,
        participant_addresses: Map<u256, Vec<ContractAddress>>,
        participant_details: Map<(u256, ContractAddress), ParticipantDetails>,
        token_uris: Map<u256, ByteArray>,
        shares_minted: Map<u256, u256>,
        reentrancy_locked: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        IPRegistered: IPRegistered,
        SyndicationActivated: SyndicationActivated,
        ParticipantAdded: ParticipantAdded,
        DepositReceived: DepositReceived,
        SyndicationCompleted: SyndicationCompleted,
        WhitelistUpdated: WhitelistUpdated,
        SyndicationCancelled: SyndicationCancelled,
        RefundClaimed: RefundClaimed,
        ProceedsClaimed: ProceedsClaimed,
        AssetMinted: AssetMinted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct IPRegistered {
        #[key]
        pub ip_id: u256,
        #[key]
        pub owner: ContractAddress,
        pub target_amount: u256,
        pub name: felt252,
        pub mode: Mode,
        pub payment_token: ContractAddress,
        pub metadata_uri: ByteArray,
        pub registered_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SyndicationActivated {
        #[key]
        pub ip_id: u256,
        pub activated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ParticipantAdded {
        #[key]
        pub ip_id: u256,
        #[key]
        pub participant: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DepositReceived {
        #[key]
        pub ip_id: u256,
        #[key]
        pub participant: ContractAddress,
        pub amount: u256,
        pub total_raised: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SyndicationCompleted {
        #[key]
        pub ip_id: u256,
        pub total_raised: u256,
        pub participant_count: u256,
        pub completed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WhitelistUpdated {
        #[key]
        pub ip_id: u256,
        #[key]
        pub account: ContractAddress,
        pub status: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SyndicationCancelled {
        #[key]
        pub ip_id: u256,
        pub cancelled_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RefundClaimed {
        #[key]
        pub ip_id: u256,
        #[key]
        pub participant: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProceedsClaimed {
        #[key]
        pub ip_id: u256,
        #[key]
        pub owner: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AssetMinted {
        #[key]
        pub ip_id: u256,
        #[key]
        pub recipient: ContractAddress,
        pub share: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc1155.initializer("");
        self.src5.register_interface(IIP_SYNDICATION_ID);
    }

    impl ERC1155HooksImpl of ERC1155Component::ERC1155HooksTrait<ContractState> {}

    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.token_uris.entry(token_id).read()
        }
    }

    #[abi(embed_v0)]
    pub impl IIPSyndicationImpl of IIPSyndication<ContractState> {
        fn register_ip(
            ref self: ContractState,
            target_amount: u256,
            name: felt252,
            description: ByteArray,
            metadata_uri: ByteArray,
            licensing_terms: felt252,
            mode: Mode,
            payment_token: ContractAddress,
        ) -> u256 {
            let owner = get_caller_address();
            assert(!owner.is_zero(), Errors::INVALID_RECIPIENT);
            assert(target_amount > 0, Errors::TARGET_IS_ZERO);
            assert(!payment_token.is_zero(), Errors::INVALID_PAYMENT_TOKEN);
            assert_content_addressed(@metadata_uri);

            let ip_id = self.last_ip_id.read() + 1;
            let metadata = IPMetadata {
                ip_id,
                owner,
                target_amount,
                name,
                description,
                metadata_uri: metadata_uri.clone(),
                licensing_terms,
                token_id: ip_id,
                exists: true,
            };
            let details = SyndicationDetails {
                ip_id,
                status: Status::Pending,
                mode,
                total_raised: 0,
                participant_count: 0,
                payment_token,
                proceeds_claimed: false,
                exists: true,
            };

            self.ip_metadata.entry(ip_id).write(metadata);
            self.syndication_details.entry(ip_id).write(details);
            self.token_uris.entry(ip_id).write(metadata_uri.clone());
            self.last_ip_id.write(ip_id);

            self
                .emit(
                    IPRegistered {
                        ip_id,
                        owner,
                        target_amount,
                        name,
                        mode,
                        payment_token,
                        metadata_uri,
                        registered_at: get_block_timestamp(),
                    },
                );

            ip_id
        }

        fn activate_syndication(ref self: ContractState, ip_id: u256) {
            let caller = get_caller_address();
            self.assert_ip_owner(ip_id, caller);

            let mut details = self.get_existing_details(ip_id);
            self.assert_pending(details);
            details.status = Status::Active;
            self.syndication_details.entry(ip_id).write(details);

            self.emit(SyndicationActivated { ip_id, activated_at: get_block_timestamp() });
        }

        fn update_whitelist(
            ref self: ContractState, ip_id: u256, account: ContractAddress, status: bool,
        ) {
            assert(!account.is_zero(), Errors::INVALID_RECIPIENT);
            let caller = get_caller_address();
            self.assert_ip_owner(ip_id, caller);
            let details = self.get_existing_details(ip_id);

            assert(details.mode == Mode::Whitelist, Errors::NOT_IN_WHITELIST_MODE);
            self.assert_pending_or_active(details);

            self.whitelisted.entry((ip_id, account)).write(status);
            self.emit(WhitelistUpdated { ip_id, account, status });
        }

        fn deposit(ref self: ContractState, ip_id: u256, amount: u256) -> u256 {
            self.enter_non_reentrant();
            let participant = get_caller_address();
            assert(!participant.is_zero(), Errors::INVALID_RECIPIENT);
            assert(amount > 0, Errors::AMOUNT_IS_ZERO);

            let metadata = self.get_existing_metadata(ip_id);
            let mut details = self.get_existing_details(ip_id);
            self.assert_active(details);
            if details.mode == Mode::Whitelist {
                assert(
                    self.whitelisted.entry((ip_id, participant)).read(),
                    Errors::ADDRESS_NOT_WHITELISTED,
                );
            }
            assert(details.total_raised < metadata.target_amount, Errors::FUNDRAISING_COMPLETED);

            let remaining = metadata.target_amount - details.total_raised;
            let deposit_amount = if amount > remaining {
                remaining
            } else {
                amount
            };
            assert(deposit_amount > 0, Errors::AMOUNT_IS_ZERO);

            let token = IERC20Dispatcher { contract_address: details.payment_token };
            assert(token.balance_of(participant) >= deposit_amount, Errors::INSUFFICIENT_BALANCE);
            let contract_address = get_contract_address();
            let balance_before = token.balance_of(contract_address);

            let key = (ip_id, participant);
            let mut participant_details = self.participant_details.entry(key).read();
            if !participant_details.exists {
                participant_details =
                    ParticipantDetails {
                        participant,
                        amount_deposited: 0,
                        amount_refunded: 0,
                        share: 0,
                        share_minted: false,
                        exists: true,
                    };
                self.participant_addresses.entry(ip_id).push(participant);
                details.participant_count += 1;
                self.emit(ParticipantAdded { ip_id, participant });
            }

            participant_details.amount_deposited += deposit_amount;
            participant_details.share += deposit_amount;
            details.total_raised += deposit_amount;

            if details.total_raised == metadata.target_amount {
                details.status = Status::Completed;
                self
                    .emit(
                        SyndicationCompleted {
                            ip_id,
                            total_raised: details.total_raised,
                            participant_count: details.participant_count,
                            completed_at: get_block_timestamp(),
                        },
                    );
            }

            self.participant_details.entry(key).write(participant_details);
            self.syndication_details.entry(ip_id).write(details);
            let success = token.transfer_from(participant, contract_address, deposit_amount);
            assert(success, Errors::PAYMENT_FAILED);
            let balance_after = token.balance_of(contract_address);
            assert(balance_after - balance_before == deposit_amount, Errors::PAYMENT_FAILED);
            self.exit_non_reentrant();

            self
                .emit(
                    DepositReceived {
                        ip_id,
                        participant,
                        amount: deposit_amount,
                        total_raised: details.total_raised,
                    },
                );

            deposit_amount
        }

        fn cancel_syndication(ref self: ContractState, ip_id: u256) {
            let caller = get_caller_address();
            self.assert_ip_owner(ip_id, caller);

            let mut details = self.get_existing_details(ip_id);
            self.assert_pending_or_active(details);

            details.status = Status::Cancelled;
            self.syndication_details.entry(ip_id).write(details);
            self.emit(SyndicationCancelled { ip_id, cancelled_at: get_block_timestamp() });
        }

        fn claim_refund(ref self: ContractState, ip_id: u256) -> u256 {
            self.enter_non_reentrant();
            let participant = get_caller_address();
            let details = self.get_existing_details(ip_id);
            assert(details.status == Status::Cancelled, Errors::SYNDICATION_NOT_CANCELLED);

            let key = (ip_id, participant);
            let mut participant_details = self.participant_details.entry(key).read();
            assert(participant_details.exists, Errors::NON_PARTICIPANT);

            let amount = participant_details.amount_deposited - participant_details.amount_refunded;
            assert(amount > 0, Errors::NO_REFUND_AVAILABLE);

            participant_details.amount_refunded += amount;
            self.participant_details.entry(key).write(participant_details);

            let token = IERC20Dispatcher { contract_address: details.payment_token };
            let success = token.transfer(participant, amount);
            assert(success, Errors::REFUND_FAILED);
            self.exit_non_reentrant();

            self.emit(RefundClaimed { ip_id, participant, amount });
            amount
        }

        fn claim_proceeds(ref self: ContractState, ip_id: u256) -> u256 {
            self.enter_non_reentrant();
            let caller = get_caller_address();
            self.assert_ip_owner(ip_id, caller);

            let mut details = self.get_existing_details(ip_id);
            assert(details.status == Status::Completed, Errors::SYNDICATION_NOT_COMPLETED);
            assert(!details.proceeds_claimed, Errors::PROCEEDS_ALREADY_CLAIMED);

            let amount = details.total_raised;
            details.proceeds_claimed = true;
            self.syndication_details.entry(ip_id).write(details);

            let token = IERC20Dispatcher { contract_address: details.payment_token };
            let success = token.transfer(caller, amount);
            assert(success, Errors::PROCEEDS_FAILED);
            self.exit_non_reentrant();

            self.emit(ProceedsClaimed { ip_id, owner: caller, amount });
            amount
        }

        fn mint_asset(ref self: ContractState, ip_id: u256) {
            self.enter_non_reentrant();
            let recipient = get_caller_address();
            assert(!recipient.is_zero(), Errors::INVALID_RECIPIENT);

            let details = self.get_existing_details(ip_id);
            assert(details.status == Status::Completed, Errors::SYNDICATION_NOT_COMPLETED);

            let key = (ip_id, recipient);
            let mut participant_details = self.participant_details.entry(key).read();
            assert(participant_details.exists, Errors::NON_PARTICIPANT);
            assert(!participant_details.share_minted, Errors::ALREADY_MINTED);

            let share = participant_details.amount_deposited - participant_details.amount_refunded;
            assert(share > 0, Errors::NON_PARTICIPANT);
            participant_details.share = share;
            participant_details.share_minted = true;
            self.participant_details.entry(key).write(participant_details);
            let total_minted = self.shares_minted.entry(ip_id).read() + share;
            self.shares_minted.entry(ip_id).write(total_minted);

            self.erc1155.mint_with_acceptance_check(recipient, ip_id, share, array![].span());
            self.exit_non_reentrant();

            self.emit(AssetMinted { ip_id, recipient, share });
        }

        fn is_whitelisted(self: @ContractState, ip_id: u256, account: ContractAddress) -> bool {
            self.whitelisted.entry((ip_id, account)).read()
        }

        fn get_ip_metadata(self: @ContractState, ip_id: u256) -> IPMetadata {
            self.get_existing_metadata(ip_id)
        }

        fn get_syndication_details(self: @ContractState, ip_id: u256) -> SyndicationDetails {
            self.get_existing_details(ip_id)
        }

        fn get_syndication_status(self: @ContractState, ip_id: u256) -> Status {
            self.get_syndication_details(ip_id).status
        }

        fn get_participant_details(
            self: @ContractState, ip_id: u256, participant: ContractAddress,
        ) -> ParticipantDetails {
            self.participant_details.entry((ip_id, participant)).read()
        }

        fn get_all_participants(self: @ContractState, ip_id: u256) -> Array<ContractAddress> {
            let count = self.get_participant_count(ip_id);
            self.get_participants(ip_id, 0, count)
        }

        fn get_participants(
            self: @ContractState, ip_id: u256, start: u256, limit: u256,
        ) -> Array<ContractAddress> {
            self.get_existing_metadata(ip_id);
            let mut participants = array![];
            let count = self.participant_addresses.entry(ip_id).len();
            if start >= count.into() || limit == 0 {
                return participants;
            }

            let remaining: u256 = count.into() - start;
            let bounded_limit = if limit > remaining {
                remaining
            } else {
                limit
            };
            let mut idx: u64 = start.try_into().unwrap();
            let end: u64 = (start + bounded_limit).try_into().unwrap();
            while idx < end {
                participants.append(self.participant_addresses.entry(ip_id).at(idx).read());
                idx += 1;
            }
            participants
        }

        fn get_participant_count(self: @ContractState, ip_id: u256) -> u256 {
            self.get_existing_metadata(ip_id);
            self.participant_addresses.entry(ip_id).len().into()
        }

        fn get_last_ip_id(self: @ContractState) -> u256 {
            self.last_ip_id.read()
        }

        fn get_claimable_refund(
            self: @ContractState, ip_id: u256, participant: ContractAddress,
        ) -> u256 {
            let details = self.syndication_details.entry(ip_id).read();
            if !details.exists || details.status != Status::Cancelled {
                return 0;
            }
            let participant_details = self.participant_details.entry((ip_id, participant)).read();
            if !participant_details.exists {
                return 0;
            }
            participant_details.amount_deposited - participant_details.amount_refunded
        }

        fn total_shares_minted(self: @ContractState, ip_id: u256) -> u256 {
            self.shares_minted.entry(ip_id).read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing_metadata(self: @ContractState, ip_id: u256) -> IPMetadata {
            let metadata = self.ip_metadata.entry(ip_id).read();
            assert(metadata.exists, Errors::IP_NOT_FOUND);
            metadata
        }

        fn get_existing_details(self: @ContractState, ip_id: u256) -> SyndicationDetails {
            let details = self.syndication_details.entry(ip_id).read();
            assert(details.exists, Errors::IP_NOT_FOUND);
            details
        }

        fn assert_ip_owner(
            self: @ContractState, ip_id: u256, caller: ContractAddress,
        ) -> IPMetadata {
            let metadata = self.get_existing_metadata(ip_id);
            assert(metadata.owner == caller, Errors::NOT_IP_OWNER);
            metadata
        }

        fn assert_pending(self: @ContractState, details: SyndicationDetails) {
            assert(details.status == Status::Pending, Errors::SYNDICATION_NOT_PENDING);
        }

        fn assert_active(self: @ContractState, details: SyndicationDetails) {
            assert(details.status == Status::Active, Errors::SYNDICATION_NOT_ACTIVE);
        }

        fn assert_pending_or_active(self: @ContractState, details: SyndicationDetails) {
            assert(
                details.status == Status::Pending || details.status == Status::Active,
                Errors::COMPLETED_OR_CANCELLED,
            );
        }

        fn enter_non_reentrant(ref self: ContractState) {
            assert(!self.reentrancy_locked.read(), Errors::REENTRANT_CALL);
            self.reentrancy_locked.write(true);
        }

        fn exit_non_reentrant(ref self: ContractState) {
            self.reentrancy_locked.write(false);
        }
    }

    fn assert_content_addressed(uri: @ByteArray) {
        let valid_uri = bytearray_starts_with(uri, @"ipfs://")
            || bytearray_starts_with(uri, @"ar://");
        assert(valid_uri, Errors::INVALID_URI);
    }
}
