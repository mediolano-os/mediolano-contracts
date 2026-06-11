# IP Subscription — v2 Redesign Audit (2026-06-10)

**Date:** 2026-06-10
**Scope:** Principle-conformance audit of the post-2026-05-23 implementation, followed by the v2 redesign in this tree.
**Result:** v2 implemented; `scarb build` clean; `snforge test` 27 passed, 0 failed.

## Why a v2

The 2026-05-23 remediation produced a sound state machine (payment collection,
expiry-derived status, sequential IDs, CEI ordering — all verified again before
this redesign; 22/22 legacy tests passed). The remaining findings were
conformance gaps against the Mediolano principles, which are stricter than what
that audit measured:

| # | Severity | Finding | v2 resolution |
| --- | --- | --- | --- |
| A1 | High (ownerless primitives) | Contract had an `owner` who alone could create plans — a per-creator, admin-gated deployment, unlike siblings `IP-Club` / `IP-Time-Capsule` | Owner removed. `create_plan` permissionless; `plan.creator` recorded per plan; only the plan creator can toggle that plan |
| A2 | Medium (data minimization) | `subscriber_plan_ids` stored an enumerable on-chain subscriber roster serving only a convenience view; unbounded Vec | Removed. Indexers rebuild views from keyed events; data not held cannot be compelled |
| A3 | Low | `tier: felt252` stored but never enforced — display data in storage | Removed; tier naming belongs in the plan's content-addressed `metadata_uri` |
| B1 | Medium | `unsubscribe` set `expires_at = now`, forfeiting access the subscriber had paid for; with no on-chain auto-renew there is nothing to cancel | Function removed. Paid time always runs to expiry; no code path can shorten it |
| B2 | Medium | `switch_subscription` had the same forfeiture (instant kill, zero credit, full new price) and duplicated `subscribe` | Function removed; account abstraction composes the same outcome as a multicall |
| B3 | Low | Renewal stacking lets subscribers prepay indefinitely at the plan's immutable price | Kept, now documented as intended (terms immutability makes it safe) |
| B4 | Low | Deactivation semantics were implicit | Decided + tested: `set_plan_active(false)` blocks new subscriptions **and** renewals; existing paid access is preserved (`test_deactivation_preserves_paid_access`) |
| B5 | Info | Manual reentrancy lock was redundant (CEI already final before the external call) and cost two storage writes per paid op; records duplicated their own map keys | Lock removed with rationale tested (`test_reentrant_payment_token_is_isolated`: a malicious token reenters under its own caller context and can only subscribe itself); `SubscriptionRecord` reduced to `{ started_at, expires_at }` |

## v2 invariants

1. **Permissionless**: any caller can create a plan; any caller can subscribe to an active plan.
2. **Ownerless / immutable**: no contract owner, no admin, no upgrade path, no fee. Plan economic terms never change; new terms = new plan.
3. **Paid time is inviolable**: no function — including the plan creator's — can reduce an existing `expires_at`.
4. **Disjoint verbs**: `subscribe` requires no active subscription; `renew_subscription` requires one. Exactly one of the two applies at any moment.
5. **CEI**: subscription state is final before the ERC-20 `transfer_from`; a reverting payment reverts the whole transaction.
6. **Minimal storage**: a subscription is two `u64` timestamps; existence is `expires_at != 0`; no enumerable rosters.

## Interface changes (v1 → v2)

- Removed: `unsubscribe`, `switch_subscription`, `get_owner`, `get_user_plan_ids`, constructor `owner` arg, `tier` param.
- Changed: `PlanRecord` gains `creator`, drops `id`/`tier`; `SubscriptionRecord` is `{ started_at, expires_at }`; `renew_subscription` requires an *active* subscription (expired ones restart via `subscribe`).
- New SRC5 ID (interface changed): `0x013f7d8dc8964bc1dc290304c1f2641165381c97e48c9f1497f90a93f7d513ac` = `starknet_keccak("mediolano.ip-subscription.v2")`.

## Verification

```bash
scarb fmt && scarb build   # clean
snforge test               # 27 passed, 0 failed
```

Coverage highlights: permissionless creation by two creators; creator-only
toggle; deactivation blocking subscribe + renew while preserving paid access;
expiry boundary (`expires_at` second inclusive); renewal stacking; paid
subscribe/renew balance assertions; allowance-failure revert; reentrant-token
isolation; SRC5 discovery; missing-record reverts.

## Production recommendation

Materially smaller surface than v1 (4 state-changing functions, no admin
paths). Before mainnet deployment: external review, deployment rehearsal
(declare/deploy, verify class hash), and registry/doctrine review for the
service entry. The prior v1 report below is retained for history.

---

# IP Subscription Audit And Remediation Report (v1, historical)

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
