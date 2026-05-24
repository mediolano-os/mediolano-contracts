# IP Subscription Audit And Remediation Report

**Date:** 2026-05-23
**Package:** `contracts/IP-Subscription`
**Scope:** `Subscription.cairo`, interface, types, tests, manifest, and architecture alignment.
**Status:** Legacy audit completed; first-principles remediation implemented in the current working tree.

## Executive Summary

`IP-Subscription` is now a time-bound access primitive for Medialane services. It is the subscription sibling of `IP-Club`:

- `IP-Club` models non-transferable membership access.
- `IP-Subscription` models plan-specific access with explicit expiry, renewal, cancellation, and optional ERC-20 payment.

The legacy implementation stored subscription labels but did not enforce payment or expiration. The redesigned implementation makes the subscription state machine explicit and queryable:

- Plan IDs are sequential and deterministic.
- Plans have explicit existence state.
- Free plans are supported.
- Paid plans require an ERC-20 payment token and recipient.
- Subscription activity is derived from `active && expires_at >= now`.
- `subscribe`, `renew_subscription`, and `switch_subscription` collect payment and are protected by a reentrancy lock.
- Events key subscriber and plan fields for indexers.
- The custom interface is SRC5 discoverable.
- The owner can be read directly with `get_owner`.

## Remediated Findings

### Critical: No Payment Was Collected

**Legacy issue:** Plans stored `price`, but subscription actions did not transfer tokens.

**Resolution:** Paid plans now require `payment_token` and `recipient`. `subscribe`, `renew_subscription`, and `switch_subscription` transfer `price` from the subscriber to the recipient.

**Coverage:** `test_paid_subscribe_transfers_tokens`.

### Critical: Active Status Ignored Expiration

**Legacy issue:** `get_subscription_status` returned a stored boolean and ignored `subscription_end`.

**Resolution:** `is_subscribed(subscriber, plan_id)` derives status from `record.exists && record.active && record.expires_at >= get_block_timestamp()`.

**Coverage:** `test_subscription_expires_by_time`.

### Critical: Initial Subscribe Did Not Persist Expiry

**Legacy issue:** `subscribe` calculated `subscription_end` after writing the subscriber record, so the new expiry was never stored.

**Resolution:** `subscribe` writes a complete `SubscriptionRecord` with `started_at` and `expires_at`.

**Coverage:** `test_subscribe_free_plan_records_expiry`.

### High: Plan IDs Were Timestamp-Based

**Legacy issue:** Plan IDs were generated from block timestamp, block number, and plan fields, causing predictable collisions.

**Resolution:** Plan IDs are now sequential `u256` IDs from `last_plan_id + 1`.

**Coverage:** `test_create_free_plan`.

### High: Free Plans Were Impossible

**Legacy issue:** `price == 0` meant "plan does not exist."

**Resolution:** `PlanRecord` has explicit `exists` and `active` fields. Free plans use `price = 0` and `payment_token = Option::None`.

**Coverage:** `test_create_free_plan`, `test_free_plan_rejects_payment_token`.

### High: Subscriber Model Was Ambiguous

**Legacy issue:** The contract mixed one `SubscriberInfo` per user with many plan IDs per user.

**Resolution:** Subscription state is now keyed by `(subscriber, plan_id)`. This supports multiple independent plan subscriptions without ambiguity.

**Coverage:** `test_switch_subscription`, `test_subscribe_free_plan_records_expiry`.

### High: Duplicate Active Subscriptions Were Allowed

**Legacy issue:** A user could repeatedly append the same plan ID.

**Resolution:** `subscribe` rejects duplicate active subscriptions. Renewal is the explicit path for extending access.

**Coverage:** `test_cannot_duplicate_active_subscription`.

### Medium: Constructor Did Not Validate Owner

**Legacy issue:** A zero owner could permanently disable plan creation.

**Resolution:** Constructor rejects zero owner.

**Coverage:** `test_constructor_rejects_zero_owner`.

### Medium: Events Were Not Indexed

**Legacy issue:** Subscriber and plan fields were not keyed.

**Resolution:** Lifecycle events key `subscriber`, `plan_id`, and relevant plan transition IDs.

### Medium: No Custom SRC5 Interface Detection

**Legacy issue:** Agents and SDKs could not detect subscription-service support via `supports_interface`.

**Resolution:** `Subscription` registers `IIP_SUBSCRIPTION_ID`.

**Coverage:** `test_supports_subscription_interface`.

### Low: Owner Was Not Directly Queryable

**Legacy issue:** The plan administrator was stored but not exposed by the subscription interface.

**Resolution:** The interface now includes `get_owner()`.

**Coverage:** `test_create_free_plan`.

### Medium: Getter API Was Caller-Only

**Legacy issue:** Status and plan-list getters only inspected the caller.

**Resolution:** Query methods accept `subscriber` and `plan_id`, making the contract composable for gates, agents, indexers, and apps.

## Architecture Compliance

| Principle | Current Result |
| --- | --- |
| Smart contract is the only truth | Pass: access, expiry, plan, and payment state are on-chain |
| Permissionless use | Pass: any user can subscribe under public rules |
| Protocol/app split | Pass: no app-only payment accounting |
| Public-goods fee posture | Pass: no platform fee; paid plans route directly to creator recipient |
| Agent readiness | Pass: SRC5 interface, keyed events, explicit query methods |
| Time-bound service model | Pass: expiry and renewal are first-class |

## Verification

Commands run from `contracts/IP-Subscription`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-subscription-redesign \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-subscription-redesign \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-subscription-redesign \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/installs/starknet-foundry/0.59.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
  /Users/kalamaha/.asdf/installs/starknet-foundry/0.59.0/bin/snforge test
```

Result:

```text
scarb build: passed
snforge test: 22 passed, 0 failed
```

## Remaining Notes

This contract intentionally models plan-specific subscriptions, not a single global subscriber state. A user can hold independent subscriptions to multiple plans, and apps should query `(subscriber, plan_id)`.

`switch_subscription` cancels the current plan and starts the new plan immediately. It does not pro-rate unused time or refund the prior plan; that kind of pricing policy should be explicit if introduced later.

The protocol collects ERC-20 payments only. Native-token subscription support should be added deliberately as a separate payment path if needed.

## Production Recommendation

The redesigned implementation is materially stronger than the legacy prototype and now represents a real subscription primitive. Before mainnet deployment, it should still receive an external security review, deployment rehearsal, and service-registry integration review.
