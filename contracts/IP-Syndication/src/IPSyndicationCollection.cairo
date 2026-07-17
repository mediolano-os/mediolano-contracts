#[starknet::contract]
pub mod IPSyndicationCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc1155::interface::{IERC1155MetadataURI, IERC1155_METADATA_URI_ID};
    use openzeppelin_token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::interface::{IIPSyndicationCollection, IIP_SYNDICATION_COLLECTION_ID};
    use crate::types::{Position, Status, Syndication, bytearray_starts_with};

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
        syndications: Map<u256, Syndication>,
        positions: Map<(u256, ContractAddress), Position>,
        whitelisted: Map<(u256, ContractAddress), bool>,
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
        SyndicationCreated: SyndicationCreated,
        DepositReceived: DepositReceived,
        Withdrawn: Withdrawn,
        SyndicationCompleted: SyndicationCompleted,
        SyndicationCancelled: SyndicationCancelled,
        RefundClaimed: RefundClaimed,
        ProceedsClaimed: ProceedsClaimed,
        SharesMinted: SharesMinted,
        WhitelistUpdated: WhitelistUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SyndicationCreated {
        #[key]
        pub token_id: u256,
        pub target_amount: u256,
        pub payment_token: ContractAddress,
        pub whitelist: bool,
        pub royalty_bps: u16,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DepositReceived {
        #[key]
        pub token_id: u256,
        #[key]
        pub participant: ContractAddress,
        pub amount: u256,
        pub total_raised: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdrawn {
        #[key]
        pub token_id: u256,
        #[key]
        pub participant: ContractAddress,
        pub amount: u256,
        pub total_raised: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SyndicationCompleted {
        #[key]
        pub token_id: u256,
        pub total_raised: u256,
        pub completed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SyndicationCancelled {
        #[key]
        pub token_id: u256,
        pub cancelled_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RefundClaimed {
        #[key]
        pub token_id: u256,
        #[key]
        pub participant: ContractAddress,
        pub amount: u256,
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
    pub struct SharesMinted {
        #[key]
        pub token_id: u256,
        #[key]
        pub participant: ContractAddress,
        pub shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WhitelistUpdated {
        #[key]
        pub token_id: u256,
        #[key]
        pub account: ContractAddress,
        pub allowed: bool,
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
        // uri() resolves per token_id from the syndications map; the ERC1155 base is unused.
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.src5.register_interface(IIP_SYNDICATION_COLLECTION_ID);
        self.src5.register_interface(IERC2981_ID);
        self.src5.register_interface(IERC1155_METADATA_URI_ID);
        self.name.write(name);
        self.symbol.write(symbol);
        self.base_uri.write(base_uri);
        self.next_token_id.write(1);
    }

    /// Per-syndication metadata URI instead of base+id concatenation.
    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, token_id: u256) -> ByteArray {
            let syndication = self.syndications.read(token_id);
            assert(syndication.target_amount > 0, 'Syndication not found');
            syndication.metadata_uri
        }
    }

    #[abi(embed_v0)]
    pub impl IPSyndicationCollectionImpl of IIPSyndicationCollection<ContractState> {
        fn create_syndication(
            ref self: ContractState,
            target_amount: u256,
            payment_token: ContractAddress,
            whitelist: bool,
            royalty_bps: u16,
            metadata_uri: ByteArray,
        ) -> u256 {
            self.ownable.assert_only_owner();
            assert(target_amount > 0, 'Target is zero');
            assert(!payment_token.is_zero(), 'Payment token is zero');
            assert(royalty_bps <= 10000, 'Royalty exceeds 10000');

            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            let syndication = Syndication {
                target_amount,
                total_raised: 0,
                payment_token,
                whitelist,
                status: Status::Active,
                proceeds_claimed: false,
                royalty_bps,
                metadata_uri: metadata_uri.clone(),
            };
            self.syndications.write(token_id, syndication);

            self
                .emit(
                    SyndicationCreated {
                        token_id,
                        target_amount,
                        payment_token,
                        whitelist,
                        royalty_bps,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            token_id
        }

        fn deposit(ref self: ContractState, token_id: u256, amount: u256) -> u256 {
            let participant = get_caller_address();
            assert(amount > 0, 'Amount is zero');

            let mut syndication = self.get_existing(token_id);
            assert(syndication.status == Status::Active, 'Syndication not active');
            if syndication.whitelist {
                assert(self.whitelisted.read((token_id, participant)), 'Not whitelisted');
            }

            let remaining = syndication.target_amount - syndication.total_raised;
            let deposit_amount = if amount > remaining {
                remaining
            } else {
                amount
            };

            let mut position = self.positions.read((token_id, participant));
            position.deposited += deposit_amount;
            syndication.total_raised += deposit_amount;

            let completed = syndication.total_raised == syndication.target_amount;
            if completed {
                syndication.status = Status::Completed;
            }
            let total_raised = syndication.total_raised;
            let payment_token = syndication.payment_token;

            self.positions.write((token_id, participant), position);
            self.syndications.write(token_id, syndication);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let this = get_contract_address();
            let balance_before = token.balance_of(this);
            let success = token.transfer_from(participant, this, deposit_amount);
            assert(success, 'Payment failed');
            assert(token.balance_of(this) - balance_before >= deposit_amount, 'Payment failed');

            self
                .emit(
                    DepositReceived { token_id, participant, amount: deposit_amount, total_raised },
                );
            if completed {
                self
                    .emit(
                        SyndicationCompleted {
                            token_id, total_raised, completed_at: get_block_timestamp(),
                        },
                    );
            }

            deposit_amount
        }

        fn withdraw(ref self: ContractState, token_id: u256, amount: u256) {
            let participant = get_caller_address();
            assert(amount > 0, 'Amount is zero');

            let mut syndication = self.get_existing(token_id);
            assert(syndication.status == Status::Active, 'Syndication not active');

            let mut position = self.positions.read((token_id, participant));
            assert(position.deposited >= amount, 'Insufficient deposit');

            position.deposited -= amount;
            syndication.total_raised -= amount;
            let total_raised = syndication.total_raised;
            let payment_token = syndication.payment_token;

            self.positions.write((token_id, participant), position);
            self.syndications.write(token_id, syndication);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let success = token.transfer(participant, amount);
            assert(success, 'Withdrawal failed');

            self.emit(Withdrawn { token_id, participant, amount, total_raised });
        }

        fn cancel_syndication(ref self: ContractState, token_id: u256) {
            self.ownable.assert_only_owner();

            let mut syndication = self.get_existing(token_id);
            assert(syndication.status == Status::Active, 'Syndication not active');

            syndication.status = Status::Cancelled;
            self.syndications.write(token_id, syndication);

            self.emit(SyndicationCancelled { token_id, cancelled_at: get_block_timestamp() });
        }

        fn claim_refund(ref self: ContractState, token_id: u256) -> u256 {
            let participant = get_caller_address();

            let syndication = self.get_existing(token_id);
            assert(syndication.status == Status::Cancelled, 'Syndication not cancelled');

            let mut position = self.positions.read((token_id, participant));
            let amount = position.deposited;
            assert(amount > 0, 'No refund available');

            position.deposited = 0;
            self.positions.write((token_id, participant), position);

            let token = IERC20Dispatcher { contract_address: syndication.payment_token };
            let success = token.transfer(participant, amount);
            assert(success, 'Refund failed');

            self.emit(RefundClaimed { token_id, participant, amount });
            amount
        }

        fn claim_proceeds(ref self: ContractState, token_id: u256) -> u256 {
            self.ownable.assert_only_owner();
            let owner = get_caller_address();

            let mut syndication = self.get_existing(token_id);
            assert(syndication.status == Status::Completed, 'Syndication not completed');
            assert(!syndication.proceeds_claimed, 'Proceeds already claimed');

            let amount = syndication.total_raised;
            syndication.proceeds_claimed = true;
            let payment_token = syndication.payment_token;
            self.syndications.write(token_id, syndication);

            let token = IERC20Dispatcher { contract_address: payment_token };
            let success = token.transfer(owner, amount);
            assert(success, 'Proceeds transfer failed');

            self.emit(ProceedsClaimed { token_id, owner, amount });
            amount
        }

        fn mint_shares(ref self: ContractState, token_id: u256) {
            let participant = get_caller_address();

            let syndication = self.get_existing(token_id);
            assert(syndication.status == Status::Completed, 'Syndication not completed');

            let mut position = self.positions.read((token_id, participant));
            assert(position.deposited > 0, 'Not a participant');
            assert(!position.shares_minted, 'Shares already minted');

            let shares = position.deposited;
            position.shares_minted = true;
            self.positions.write((token_id, participant), position);

            self.erc1155.mint_with_acceptance_check(participant, token_id, shares, array![].span());

            self.emit(SharesMinted { token_id, participant, shares });
        }

        fn set_whitelist(
            ref self: ContractState, token_id: u256, account: ContractAddress, allowed: bool,
        ) {
            self.ownable.assert_only_owner();
            assert(!account.is_zero(), 'Account is zero');

            let syndication = self.get_existing(token_id);
            assert(syndication.whitelist, 'Not a whitelist campaign');
            assert(syndication.status == Status::Active, 'Syndication not active');

            self.whitelisted.write((token_id, account), allowed);
            self.emit(WhitelistUpdated { token_id, account, allowed });
        }

        fn is_whitelisted(self: @ContractState, token_id: u256, account: ContractAddress) -> bool {
            self.whitelisted.read((token_id, account))
        }

        fn get_syndication(self: @ContractState, token_id: u256) -> Syndication {
            self.get_existing(token_id)
        }

        fn get_position(
            self: @ContractState, token_id: u256, participant: ContractAddress,
        ) -> Position {
            self.positions.read((token_id, participant))
        }

        fn syndication_count(self: @ContractState) -> u256 {
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

        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let syndication = self.get_existing(token_id);
            let amount = (sale_price * syndication.royalty_bps.into()) / 10000;
            (self.ownable.owner(), amount)
        }

        fn royaltyInfo(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            self.royalty_info(token_id, sale_price)
        }

        fn version(self: @ContractState) -> ByteArray {
            "1.0.0"
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_existing(self: @ContractState, token_id: u256) -> Syndication {
            let syndication = self.syndications.read(token_id);
            assert(syndication.target_amount > 0, 'Syndication not found');
            syndication
        }
    }
}
