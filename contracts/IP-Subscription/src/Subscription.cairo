#[starknet::contract]
pub mod Subscription {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::interface::{IIP_SUBSCRIPTION_ID, ISubscription};
    use crate::types::{PlanRecord, SubscriptionRecord, bytearray_starts_with};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        owner: ContractAddress,
        last_plan_id: u256,
        plans: Map<u256, PlanRecord>,
        subscriptions: Map<(ContractAddress, u256), SubscriptionRecord>,
        subscriber_plan_ids: Map<ContractAddress, Vec<u256>>,
        subscription_locked: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        PlanCreated: PlanCreated,
        PlanStatusUpdated: PlanStatusUpdated,
        Subscribed: Subscribed,
        Unsubscribed: Unsubscribed,
        SubscriptionRenewed: SubscriptionRenewed,
        SubscriptionSwitched: SubscriptionSwitched,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PlanCreated {
        #[key]
        pub plan_id: u256,
        #[key]
        pub recipient: ContractAddress,
        pub price: u256,
        pub duration: u64,
        pub tier: felt252,
        pub payment_token: Option<ContractAddress>,
        pub metadata_uri: ByteArray,
        pub created_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PlanStatusUpdated {
        #[key]
        pub plan_id: u256,
        pub active: bool,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Subscribed {
        #[key]
        pub subscriber: ContractAddress,
        #[key]
        pub plan_id: u256,
        pub started_at: u64,
        pub expires_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unsubscribed {
        #[key]
        pub subscriber: ContractAddress,
        #[key]
        pub plan_id: u256,
        pub unsubscribed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SubscriptionRenewed {
        #[key]
        pub subscriber: ContractAddress,
        #[key]
        pub plan_id: u256,
        pub renewed_at: u64,
        pub expires_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SubscriptionSwitched {
        #[key]
        pub subscriber: ContractAddress,
        #[key]
        pub current_plan_id: u256,
        #[key]
        pub new_plan_id: u256,
        pub switched_at: u64,
        pub expires_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        assert(!owner.is_zero(), 'Owner is zero address');
        self.src5.register_interface(IIP_SUBSCRIPTION_ID);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl SubscriptionImpl of ISubscription<ContractState> {
        fn create_plan(
            ref self: ContractState,
            price: u256,
            duration: u64,
            tier: felt252,
            payment_token: Option<ContractAddress>,
            recipient: ContractAddress,
            metadata_uri: ByteArray,
        ) -> u256 {
            assert(get_caller_address() == self.owner.read(), 'Only owner can create plans');
            assert(duration > 0, 'Duration cannot be zero');
            assert(!recipient.is_zero(), 'Recipient is zero address');

            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if price == 0 {
                assert(payment_token.is_none(), 'Free plan cannot use token');
            } else {
                let token = match payment_token {
                    Option::Some(token) => token,
                    Option::None => panic!("Paid plan requires token"),
                };
                assert(!token.is_zero(), 'Payment token is zero');
            }

            let plan_id = self.last_plan_id.read() + 1;
            let plan = PlanRecord {
                id: plan_id,
                price,
                duration,
                tier,
                payment_token,
                recipient,
                metadata_uri: metadata_uri.clone(),
                active: true,
                exists: true,
            };

            self.plans.entry(plan_id).write(plan);
            self.last_plan_id.write(plan_id);

            self
                .emit(
                    PlanCreated {
                        plan_id,
                        recipient,
                        price,
                        duration,
                        tier,
                        payment_token,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            plan_id
        }

        fn set_plan_active(ref self: ContractState, plan_id: u256, active: bool) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can update plans');

            let mut plan = self.plans.entry(plan_id).read();
            assert(plan.exists, 'Plan does not exist');
            plan.active = active;
            self.plans.entry(plan_id).write(plan);

            self.emit(PlanStatusUpdated { plan_id, active, updated_at: get_block_timestamp() });
        }

        fn subscribe(ref self: ContractState, plan_id: u256) {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Subscriber is zero address');

            let plan = self.plans.entry(plan_id).read();
            assert(plan.exists, 'Plan does not exist');
            assert(plan.active, 'Plan is inactive');

            let now = get_block_timestamp();
            let key = (caller, plan_id);
            let existing = self.subscriptions.entry(key).read();
            assert(!is_active(existing, now), 'Already subscribed');

            self.enter_subscription();

            let expires_at = now + plan.duration;
            let record = SubscriptionRecord {
                subscriber: caller,
                plan_id,
                started_at: now,
                expires_at,
                active: true,
                exists: true,
            };
            self.subscriptions.entry(key).write(record);

            if !existing.exists {
                self.subscriber_plan_ids.entry(caller).push(plan_id);
            }

            collect_payment(caller, @plan);
            self.exit_subscription();

            self.emit(Subscribed { subscriber: caller, plan_id, started_at: now, expires_at });
        }

        fn renew_subscription(ref self: ContractState, plan_id: u256) {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Subscriber is zero address');

            let plan = self.plans.entry(plan_id).read();
            assert(plan.exists, 'Plan does not exist');
            assert(plan.active, 'Plan is inactive');

            let now = get_block_timestamp();
            let key = (caller, plan_id);
            let mut record = self.subscriptions.entry(key).read();
            assert(record.exists, 'Subscription does not exist');

            self.enter_subscription();

            let mut base_time = now;
            if is_active(record, now) {
                base_time = record.expires_at;
            }

            record.started_at = now;
            record.expires_at = base_time + plan.duration;
            record.active = true;
            self.subscriptions.entry(key).write(record);

            collect_payment(caller, @plan);
            self.exit_subscription();

            self
                .emit(
                    SubscriptionRenewed {
                        subscriber: caller, plan_id, renewed_at: now, expires_at: record.expires_at,
                    },
                );
        }

        fn unsubscribe(ref self: ContractState, plan_id: u256) {
            let caller = get_caller_address();
            let key = (caller, plan_id);
            let mut record = self.subscriptions.entry(key).read();
            assert(record.exists, 'Subscription does not exist');
            assert(record.active, 'Not currently subscribed');

            let now = get_block_timestamp();
            record.active = false;
            record.expires_at = now;
            self.subscriptions.entry(key).write(record);

            self.emit(Unsubscribed { subscriber: caller, plan_id, unsubscribed_at: now });
        }

        fn switch_subscription(ref self: ContractState, current_plan_id: u256, new_plan_id: u256) {
            let caller = get_caller_address();
            assert(current_plan_id != new_plan_id, 'Plan ids must differ');

            let now = get_block_timestamp();
            let current_key = (caller, current_plan_id);
            let mut current_record = self.subscriptions.entry(current_key).read();
            assert(is_active(current_record, now), 'Current subscription inactive');

            let new_plan = self.plans.entry(new_plan_id).read();
            assert(new_plan.exists, 'Plan does not exist');
            assert(new_plan.active, 'Plan is inactive');

            let new_key = (caller, new_plan_id);
            let existing_new_record = self.subscriptions.entry(new_key).read();
            assert(!is_active(existing_new_record, now), 'Already subscribed');

            self.enter_subscription();

            current_record.active = false;
            current_record.expires_at = now;
            self.subscriptions.entry(current_key).write(current_record);

            let expires_at = now + new_plan.duration;
            let new_record = SubscriptionRecord {
                subscriber: caller,
                plan_id: new_plan_id,
                started_at: now,
                expires_at,
                active: true,
                exists: true,
            };
            self.subscriptions.entry(new_key).write(new_record);

            if !existing_new_record.exists {
                self.subscriber_plan_ids.entry(caller).push(new_plan_id);
            }

            collect_payment(caller, @new_plan);
            self.exit_subscription();

            self
                .emit(
                    SubscriptionSwitched {
                        subscriber: caller,
                        current_plan_id,
                        new_plan_id,
                        switched_at: now,
                        expires_at,
                    },
                );
        }

        fn is_subscribed(self: @ContractState, subscriber: ContractAddress, plan_id: u256) -> bool {
            let record = self.subscriptions.entry((subscriber, plan_id)).read();
            is_active(record, get_block_timestamp())
        }

        fn get_subscription(
            self: @ContractState, subscriber: ContractAddress, plan_id: u256,
        ) -> SubscriptionRecord {
            let record = self.subscriptions.entry((subscriber, plan_id)).read();
            assert(record.exists, 'Subscription does not exist');
            record
        }

        fn get_plan(self: @ContractState, plan_id: u256) -> PlanRecord {
            let plan = self.plans.entry(plan_id).read();
            assert(plan.exists, 'Plan does not exist');
            plan
        }

        fn get_last_plan_id(self: @ContractState) -> u256 {
            self.last_plan_id.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn get_user_plan_ids(self: @ContractState, subscriber: ContractAddress) -> Array<u256> {
            let subscriber_plan_ids = self.subscriber_plan_ids.entry(subscriber);
            let mut plan_ids: Array<u256> = array![];
            let len: u64 = subscriber_plan_ids.len();
            for i in 0..len {
                plan_ids.append(subscriber_plan_ids.at(i).read());
            }
            plan_ids
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn enter_subscription(ref self: ContractState) {
            assert(!self.subscription_locked.read(), 'Reentrant subscription');
            self.subscription_locked.write(true);
        }

        fn exit_subscription(ref self: ContractState) {
            self.subscription_locked.write(false);
        }
    }

    fn collect_payment(payer: ContractAddress, plan: @PlanRecord) {
        if *plan.price > 0 {
            let payment_token = match *plan.payment_token {
                Option::Some(token) => token,
                Option::None => panic!("Payment token missing"),
            };
            let token = IERC20Dispatcher { contract_address: payment_token };
            let result = token.transfer_from(payer, *plan.recipient, *plan.price);
            assert(result, 'Token Transfer Failed');
        }
    }

    fn is_active(record: SubscriptionRecord, now: u64) -> bool {
        record.exists && record.active && record.expires_at >= now
    }
}
