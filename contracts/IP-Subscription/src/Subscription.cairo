// IP-Subscription v2 — permissionless, ownerless, immutable.
//
// One deployment serves every creator: anyone can create a plan, and only a
// plan's creator can manage that plan. There is no contract owner, no admin,
// no upgrade path, and no fee taken by the contract. Payments flow directly
// from subscriber to the plan's recipient.
//
// Subscriptions are prepaid, time-bound access: `subscribe` starts a period,
// `renew_subscription` extends an active one. Paid time always runs to
// expiry — nothing in this contract can confiscate it, including the plan
// creator (deactivating a plan only stops new payments).
#[starknet::contract]
pub mod Subscription {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
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
        last_plan_id: u256,
        plans: Map<u256, PlanRecord>,
        subscriptions: Map<(ContractAddress, u256), SubscriptionRecord>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        PlanCreated: PlanCreated,
        PlanStatusUpdated: PlanStatusUpdated,
        Subscribed: Subscribed,
        SubscriptionRenewed: SubscriptionRenewed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PlanCreated {
        #[key]
        pub plan_id: u256,
        #[key]
        pub creator: ContractAddress,
        pub recipient: ContractAddress,
        pub price: u256,
        pub duration: u64,
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
    pub struct SubscriptionRenewed {
        #[key]
        pub subscriber: ContractAddress,
        #[key]
        pub plan_id: u256,
        pub renewed_at: u64,
        pub expires_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.src5.register_interface(IIP_SUBSCRIPTION_ID);
    }

    #[abi(embed_v0)]
    impl SubscriptionImpl of ISubscription<ContractState> {
        fn create_plan(
            ref self: ContractState,
            price: u256,
            duration: u64,
            payment_token: Option<ContractAddress>,
            recipient: ContractAddress,
            metadata_uri: ByteArray,
        ) -> u256 {
            let creator = get_caller_address();
            assert(!creator.is_zero(), 'Creator is zero address');
            assert(duration > 0, 'Duration cannot be zero');
            assert(!recipient.is_zero(), 'Recipient is zero address');

            // Plan metadata must be content-addressed so the record stays
            // durable and verifiable independently of any gateway.
            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if price == 0 {
                assert(payment_token.is_none(), 'Free plan cannot use token');
            } else {
                assert(payment_token.is_some(), 'Paid plan requires token');
                assert(!payment_token.unwrap().is_zero(), 'Payment token is zero');
            }

            let plan_id = self.last_plan_id.read() + 1;
            let plan = PlanRecord {
                creator,
                recipient,
                price,
                duration,
                payment_token,
                metadata_uri: metadata_uri.clone(),
                active: true,
            };

            self.plans.entry(plan_id).write(plan);
            self.last_plan_id.write(plan_id);

            self
                .emit(
                    PlanCreated {
                        plan_id,
                        creator,
                        recipient,
                        price,
                        duration,
                        payment_token,
                        metadata_uri,
                        created_at: get_block_timestamp(),
                    },
                );

            plan_id
        }

        fn set_plan_active(ref self: ContractState, plan_id: u256, active: bool) {
            let mut plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), 'Plan does not exist');
            assert(get_caller_address() == plan.creator, 'Only plan creator');

            plan.active = active;
            self.plans.entry(plan_id).write(plan);

            self.emit(PlanStatusUpdated { plan_id, active, updated_at: get_block_timestamp() });
        }

        fn subscribe(ref self: ContractState, plan_id: u256) {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Subscriber is zero address');

            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), 'Plan does not exist');
            assert(plan.active, 'Plan is inactive');

            let now = get_block_timestamp();
            let key = (caller, plan_id);
            let existing = self.subscriptions.entry(key).read();
            assert(!is_active(existing, now), 'Already subscribed');

            let expires_at = now + plan.duration;
            self.subscriptions.entry(key).write(SubscriptionRecord { started_at: now, expires_at });

            // State is final before the external transfer (checks-effects-
            // interactions); a reentrant call observes consistent storage and
            // runs under the attacker's own caller context.
            collect_payment(caller, @plan);

            self.emit(Subscribed { subscriber: caller, plan_id, started_at: now, expires_at });
        }

        fn renew_subscription(ref self: ContractState, plan_id: u256) {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Subscriber is zero address');

            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), 'Plan does not exist');
            assert(plan.active, 'Plan is inactive');

            let now = get_block_timestamp();
            let key = (caller, plan_id);
            let mut record = self.subscriptions.entry(key).read();
            // Renewal extends an active subscription; an expired one restarts
            // via `subscribe`. The two paths are deliberately disjoint.
            assert(is_active(record, now), 'Subscription inactive');

            record.expires_at = record.expires_at + plan.duration;
            self.subscriptions.entry(key).write(record);

            collect_payment(caller, @plan);

            self
                .emit(
                    SubscriptionRenewed {
                        subscriber: caller, plan_id, renewed_at: now, expires_at: record.expires_at,
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
            assert(record.expires_at != 0, 'Subscription does not exist');
            record
        }

        fn get_plan(self: @ContractState, plan_id: u256) -> PlanRecord {
            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), 'Plan does not exist');
            plan
        }

        fn get_last_plan_id(self: @ContractState) -> u256 {
            self.last_plan_id.read()
        }
    }

    fn collect_payment(payer: ContractAddress, plan: @PlanRecord) {
        if *plan.price > 0 {
            // create_plan guarantees a paid plan carries a non-zero payment
            // token, and plan terms are immutable.
            let token = IERC20Dispatcher { contract_address: (*plan.payment_token).unwrap() };
            let result = token.transfer_from(payer, *plan.recipient, *plan.price);
            assert(result, 'Token Transfer Failed');
        }
    }

    fn is_active(record: SubscriptionRecord, now: u64) -> bool {
        record.expires_at != 0 && record.expires_at >= now
    }
}
