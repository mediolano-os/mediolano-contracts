# IP Subscription

`IP-Subscription` is a permissionless Starknet contract for prepaid, time-bound
access plans. One immutable deployment serves every creator: anyone can create
a plan; subscribers pay the plan's recipient directly and receive access until
an explicit expiry.

The protocol is the subscription sibling of `IP-Club`:

- `IP-Club`: non-transferable membership access.
- `IP-Subscription`: time-bound access with explicit expiry and renewal.

## Design (v2, 2026-06-10)

The v2 redesign aligns the contract with the Mediolano principles
(permissionless, ownerless, immutable, zero-fee, minimal data):

- **No contract owner.** `create_plan` is open to any caller; the plan's
  creator is recorded per plan and is the only address that can toggle that
  plan's `active` flag. The contract itself has no admin, no upgrade path, and
  takes no fee.
- **Paid time is inviolable.** Nothing in the contract can shorten a paid
  period — including the plan creator. Deactivating a plan stops new
  subscriptions and renewals (no new money), but existing access always runs
  to its expiry.
- **Disjoint verbs.** `subscribe` starts a period when none is active;
  `renew_subscription` extends an active one from its current expiry. There is
  no `unsubscribe` (prepaid access has nothing to cancel on-chain — removing
  it removed the only path that could forfeit paid time) and no
  `switch_subscription` (account abstraction composes it as a multicall).
- **Minimal on-chain data.** A subscription is two timestamps keyed by
  `(subscriber, plan_id)`. There is no enumerable subscriber roster; indexers
  rebuild views from keyed events. Display data such as tier names lives in
  the plan's content-addressed `metadata_uri`, not in storage.

## Service Asset Declaration

This service follows the shared doctrine in
[`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-subscription` |
| `asset_standard` | None in the current implementation |
| `asset_role` | Time-bound subscription record |
| `transferability` | Not applicable |
| `access_semantics` | `is_subscribed(subscriber, plan_id)` derives access from expiry |
| `marketplace_visibility` | Service/event visibility; no asset listing yet |
| `metadata_uri_policy` | `ipfs://` or `ar://` for plan metadata |
| `src5_interface_id` | `IIP_SUBSCRIPTION_ID` (`starknet_keccak("mediolano.ip-subscription.v2")`) |

The contract intentionally keeps access state as a plan-specific record rather
than a tradable asset. If this service becomes asset-backed, the asset should
be designed explicitly as a non-transferable receipt, transferable time pass,
or ERC-1155 plan edition.

## Interface

```cairo
fn create_plan(
    price: u256,
    duration: u64,
    payment_token: Option<ContractAddress>,
    recipient: ContractAddress,
    metadata_uri: ByteArray,
) -> u256;

fn set_plan_active(plan_id: u256, active: bool); // plan creator only
fn subscribe(plan_id: u256);                     // starts a period; collects payment
fn renew_subscription(plan_id: u256);            // extends an active period from its expiry

fn is_subscribed(subscriber: ContractAddress, plan_id: u256) -> bool;
fn get_subscription(subscriber: ContractAddress, plan_id: u256) -> SubscriptionRecord;
fn get_plan(plan_id: u256) -> PlanRecord;
fn get_last_plan_id() -> u256;
```

Custom SRC5 interface ID:

```cairo
IIP_SUBSCRIPTION_ID =
0x013f7d8dc8964bc1dc290304c1f2641165381c97e48c9f1497f90a93f7d513ac
```

## Plan Rules

- Sequential plan IDs; plan economic terms (price, duration, token, recipient)
  are immutable — new terms mean a new plan.
- Free plans use `price = 0` and `payment_token = None`. Paid plans require an
  ERC-20 token and transfer `price` from the subscriber to `recipient` inside
  `subscribe`/`renew_subscription` (checks-effects-interactions; state is
  final before the external call).
- Renewing while active stacks duration onto the current expiry — subscribers
  may prepay ahead at the plan's immutable price. This is intended.
- Plan `metadata_uri` must be content-addressed (`ipfs://` or `ar://`) so the
  record stays verifiable independently of any gateway.

## Build & Test

```bash
scarb build
snforge test   # 27 tests
```
