#[starknet::contract]
pub mod IPCrowdfundingCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::ERC1155Component;
    use openzeppelin_token::erc1155::interface::{IERC1155MetadataURI, IERC1155_METADATA_URI_ID};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::interface::{IIPCrowdfundingCollection, IIP_CROWDFUNDING_COLLECTION_ID};
    use crate::types::{Campaign, CampaignStatus, Position, bytearray_starts_with};

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
        campaigns: Map<u256, Campaign>,
        positions: Map<(u256, ContractAddress), Position>,
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
        CampaignCreated: CampaignCreated,
        ContributionReceived: ContributionReceived,
        Withdrawn: Withdrawn,
        CampaignCancelled: CampaignCancelled,
        ProceedsClaimed: ProceedsClaimed,
        RefundClaimed: RefundClaimed,
        ReceiptMinted: ReceiptMinted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignCreated {
        #[key]
        pub token_id: u256,
        pub goal_amount: u256,
        pub payment_token: ContractAddress,
        pub end_time: u64,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionReceived {
        #[key]
        pub token_id: u256,
        #[key]
        pub backer: ContractAddress,
        pub amount: u256,
        pub total_raised: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdrawn {
        #[key]
        pub token_id: u256,
        #[key]
        pub backer: ContractAddress,
        pub amount: u256,
        pub total_raised: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignCancelled {
        #[key]
        pub token_id: u256,
        pub cancelled_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProceedsClaimed {
        #[key]
        pub token_id: u256,
        #[key]
        pub owner: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RefundClaimed {
        #[key]
        pub token_id: u256,
        #[key]
        pub backer: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReceiptMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub backer: ContractAddress,
        pub amount: u256,
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
        // uri() resolves per token_id from the campaigns map; the ERC1155 base is unused.
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_CROWDFUNDING_COLLECTION_ID);
        self.src5.register_interface(IERC1155_METADATA_URI_ID);
        self.name.write(name);
        self.symbol.write(symbol);
        self.base_uri.write(base_uri);
        self.next_token_id.write(1);
    }

    /// Supporter receipts are soulbound: only minting (from == 0) passes.
    impl ERC1155HooksImpl of ERC1155Component::ERC1155HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC1155Component::ComponentState<ContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
        ) {
            assert(from.is_zero(), 'Receipt is non-transferable');
        }

        fn after_update(
            ref self: ERC1155Component::ComponentState<ContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
        ) {}
    }

    /// Per-campaign metadata URI instead of base+id concatenation.
    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, token_id: u256) -> ByteArray {
            let campaign = self.campaigns.read(token_id);
            assert(campaign.goal_amount > 0, 'Campaign not found');
            campaign.metadata_uri
        }
    }

    #[abi(embed_v0)]
    pub impl IPCrowdfundingCollectionImpl of IIPCrowdfundingCollection<ContractState> {
        fn create_campaign(
            ref self: ContractState,
            goal_amount: u256,
            payment_token: ContractAddress,
            end_time: u64,
            metadata_uri: ByteArray,
        ) -> u256 {
            self.ownable.assert_only_owner();
            assert(goal_amount > 0, 'Goal is zero');
            assert(!payment_token.is_zero(), 'Payment token is zero');
            assert(end_time > get_block_timestamp(), 'End time in the past');

            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            let campaign = Campaign {
                goal_amount,
                total_raised: 0,
                payment_token,
                end_time,
                cancelled: false,
                proceeds_claimed: false,
                metadata_uri: metadata_uri.clone(),
            };
            self.campaigns.write(token_id, campaign);

            self
                .emit(
                    CampaignCreated {
                        token_id,
                        goal_amount,
                        payment_token,
                        end_time,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            token_id
        }

        fn contribute(ref self: ContractState, token_id: u256, amount: u256) -> u256 {
            let backer = get_caller_address();
            assert(amount > 0, 'Amount is zero');

            let mut campaign = self.get_existing(token_id);
            assert(status_of(@campaign) == CampaignStatus::Active, 'Campaign not active');

            let mut position = self.positions.read((token_id, backer));
            position.contributed += amount;
            campaign.total_raised += amount;
            let total_raised = campaign.total_raised;
            let payment_token = campaign.payment_token;

            self.positions.write((token_id, backer), position);
            self.campaigns.write(token_id, campaign);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let this = get_contract_address();
            let balance_before = token.balance_of(this);
            let success = token.transfer_from(backer, this, amount);
            assert(success, 'Payment failed');
            assert(token.balance_of(this) - balance_before >= amount, 'Payment failed');

            self.emit(ContributionReceived { token_id, backer, amount, total_raised });

            amount
        }

        fn withdraw(ref self: ContractState, token_id: u256, amount: u256) {
            let backer = get_caller_address();
            assert(amount > 0, 'Amount is zero');

            let mut campaign = self.get_existing(token_id);
            assert(status_of(@campaign) == CampaignStatus::Active, 'Campaign not active');

            let mut position = self.positions.read((token_id, backer));
            assert(position.contributed >= amount, 'Insufficient contribution');

            position.contributed -= amount;
            campaign.total_raised -= amount;
            let total_raised = campaign.total_raised;
            let payment_token = campaign.payment_token;

            self.positions.write((token_id, backer), position);
            self.campaigns.write(token_id, campaign);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let success = token.transfer(backer, amount);
            assert(success, 'Withdrawal failed');

            self.emit(Withdrawn { token_id, backer, amount, total_raised });
        }

        fn cancel_campaign(ref self: ContractState, token_id: u256) {
            self.ownable.assert_only_owner();

            let mut campaign = self.get_existing(token_id);
            assert(status_of(@campaign) == CampaignStatus::Active, 'Campaign not active');

            campaign.cancelled = true;
            self.campaigns.write(token_id, campaign);

            self.emit(CampaignCancelled { token_id, cancelled_at: get_block_timestamp() });
        }

        fn claim_proceeds(ref self: ContractState, token_id: u256) -> u256 {
            self.ownable.assert_only_owner();
            let owner = get_caller_address();

            let mut campaign = self.get_existing(token_id);
            assert(status_of(@campaign) == CampaignStatus::Succeeded, 'Campaign not succeeded');
            assert(!campaign.proceeds_claimed, 'Proceeds already claimed');

            let amount = campaign.total_raised;
            campaign.proceeds_claimed = true;
            let payment_token = campaign.payment_token;
            self.campaigns.write(token_id, campaign);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let success = token.transfer(owner, amount);
            assert(success, 'Proceeds transfer failed');

            self.emit(ProceedsClaimed { token_id, owner, amount });
            amount
        }

        fn claim_refund(ref self: ContractState, token_id: u256) -> u256 {
            let backer = get_caller_address();

            let campaign = self.get_existing(token_id);
            let status = status_of(@campaign);
            assert(
                status == CampaignStatus::Failed || status == CampaignStatus::Cancelled,
                'Campaign not refundable',
            );

            let mut position = self.positions.read((token_id, backer));
            let amount = position.contributed;
            assert(amount > 0, 'No refund available');

            position.contributed = 0;
            self.positions.write((token_id, backer), position);

            let token = IERC20Dispatcher { contract_address: campaign.payment_token };
            let success = token.transfer(backer, amount);
            assert(success, 'Refund failed');

            self.emit(RefundClaimed { token_id, backer, amount });
            amount
        }

        fn mint_receipt(ref self: ContractState, token_id: u256) {
            let backer = get_caller_address();

            let campaign = self.get_existing(token_id);
            assert(status_of(@campaign) == CampaignStatus::Succeeded, 'Campaign not succeeded');

            let mut position = self.positions.read((token_id, backer));
            assert(position.contributed > 0, 'Not a backer');
            assert(!position.receipt_minted, 'Receipt already minted');

            let amount = position.contributed;
            position.receipt_minted = true;
            self.positions.write((token_id, backer), position);

            self.erc1155.mint_with_acceptance_check(backer, token_id, amount, array![].span());

            self.emit(ReceiptMinted { token_id, backer, amount });
        }

        fn campaign_status(self: @ContractState, token_id: u256) -> CampaignStatus {
            let campaign = self.get_existing(token_id);
            status_of(@campaign)
        }

        fn get_campaign(self: @ContractState, token_id: u256) -> Campaign {
            self.get_existing(token_id)
        }

        fn get_position(self: @ContractState, token_id: u256, backer: ContractAddress) -> Position {
            self.positions.read((token_id, backer))
        }

        fn campaign_count(self: @ContractState) -> u256 {
            self.next_token_id.read() - 1
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

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing(self: @ContractState, token_id: u256) -> Campaign {
            let campaign = self.campaigns.read(token_id);
            assert(campaign.goal_amount > 0, 'Campaign not found');
            campaign
        }
    }

    /// The outcome is arithmetic, never stored.
    fn status_of(campaign: @Campaign) -> CampaignStatus {
        if *campaign.cancelled {
            return CampaignStatus::Cancelled;
        }
        if get_block_timestamp() < *campaign.end_time {
            return CampaignStatus::Active;
        }
        if *campaign.total_raised >= *campaign.goal_amount {
            CampaignStatus::Succeeded
        } else {
            CampaignStatus::Failed
        }
    }
}
