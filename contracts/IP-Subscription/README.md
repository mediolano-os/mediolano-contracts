# IP Subscription

`IP-Subscription` is a Starknet smart contract for time-bound access plans. It lets a creator deploy a subscription service, create plans, and let users subscribe, renew, cancel, or switch plans.

The protocol is designed as the subscription sibling of `IP-Club`:

- `IP-Club`: non-transferable membership access.
- `IP-Subscription`: time-bound access with explicit expiry and renewal.

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
| `src5_interface_id` | `IIP_SUBSCRIPTION_ID` |

The current contract intentionally keeps access state as a plan-specific record
rather than a tradable asset. If this service becomes asset-backed, the asset
should be designed explicitly as a non-transferable receipt, transferable time
pass, or ERC-1155 plan edition.

## Features

- Sequential plan IDs.
- Explicit plan existence and active state.
- Free plans.
- Paid ERC-20 plans with direct payment to the configured recipient.
- Plan-specific subscription records keyed by `(subscriber, plan_id)`.
- Expiry-derived access checks.
- Renewal from current expiry when still active, or from current time when expired.
- Reentrancy guard for payment flows.
- Keyed events for indexers.
- SRC5 interface detection.

## Interface

```cairo
fn create_plan(
    price: u256,
    duration: u64,
    tier: felt252,
    payment_token: Option<ContractAddress>,
    recipient: ContractAddress,
    metadata_uri: ByteArray,
) -> u256;

fn set_plan_active(plan_id: u256, active: bool);
fn subscribe(plan_id: u256);
fn renew_subscription(plan_id: u256);
fn unsubscribe(plan_id: u256);
fn switch_subscription(current_plan_id: u256, new_plan_id: u256);

fn is_subscribed(subscriber: ContractAddress, plan_id: u256) -> bool;
fn get_subscription(subscriber: ContractAddress, plan_id: u256) -> SubscriptionRecord;
fn get_plan(plan_id: u256) -> PlanRecord;
fn get_last_plan_id() -> u256;
fn get_owner() -> ContractAddress;
fn get_user_plan_ids(subscriber: ContractAddress) -> Array<u256>;
```

Custom SRC5 interface ID:

```cairo
IIP_SUBSCRIPTION_ID =
0x02b8b00d09660d14a71dfb5dd9f0acd39174877cf4e400f727b397a385e61ae3
```

## Plan Rules

Free plan:

```text
price = 0
payment_token = Option::None
recipient = non-zero creator/payment recipient
metadata_uri = ipfs://... or ar://...
```

Paid plan:

```text
price > 0
payment_token = Option::Some(erc20_address)
recipient = non-zero creator/payment recipient
metadata_uri = ipfs://... or ar://...
```

HTTP metadata is rejected.

## Access Semantics

A subscription is active when:

```text
record.exists && record.active && record.expires_at >= get_block_timestamp()
```

Unsubscribing sets `active = false` and moves `expires_at` to the unsubscribe timestamp.

Renewing an active subscription extends from its current expiry. Renewing an expired subscription starts from the current block timestamp.

## Development

```bash
cd contracts/IP-Subscription
scarb build
snforge test
```

Tested baseline:

| Package | Version |
| --- | --- |
| `starknet` | `2.12.0` |
| `openzeppelin_*` | `0.20.0` |
| `snforge_std` | `0.59.0` |

## Status

This package has been redesigned from the legacy prototype. It is still pre-production until it receives external security review and deployment rehearsal.
