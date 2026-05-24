# Service Asset Doctrine

**Status:** Draft contract-design doctrine for launchpad services.
**Scope:** Mediolano and Medialane service contracts in this repository.

## Core Rule

Every launchpad service should emit or mint an indexable asset whenever that asset helps discovery, ownership visibility, access display, or marketplace routing.

Tradability is a separate design choice.

An indexable asset can be:

- a transferable ERC-721 or ERC-1155;
- a non-transferable ERC-721 or ERC-1155;
- an ERC-20 membership/payment/community token;
- a receipt, badge, pass, edition, or entitlement token.

The asset makes the service visible. Transferability defines whether the asset is marketable.

## Why This Exists

Medialane indexes digital assets and displays them across creator pages, marketplace surfaces, launchpad views, SDK services, and agent workflows. If a service creates no asset, it can still be used on-chain, but it has weaker visibility and poorer composability.

At the same time, not every service asset should be tradable. Access credentials, proofs, subscriptions, and identity-like badges can become misleading if ownership moves but access state does not.

So the protocol should avoid this shortcut:

```text
asset exists == asset is tradable
```

Instead, every service should declare both:

```text
asset exists
transferability semantics
```

## Required Service Declaration

Each service README and future service-registry entry should answer:

| Field | Meaning |
| --- | --- |
| `service_id` | Stable kebab-case behavior ID. |
| `asset_standard` | ERC721, ERC1155, ERC20, or none. |
| `asset_role` | What the asset represents: membership, subscription, receipt, edition, proof, ticket, etc. |
| `transferability` | transferable, non-transferable, restricted, or not-applicable. |
| `access_semantics` | What grants access: ownership, balance, expiry, redemption, payment, or another rule. |
| `marketplace_visibility` | Whether the asset should be listed, displayed only, hidden, or routed through a custom market. |
| `metadata_uri_policy` | Content-addressed metadata requirements. |
| `src5_interface_id` | Custom interface ID for agent and SDK detection. |

## Visibility And Marketplace Rules

Indexers and marketplace clients should treat these as different states:

| Asset Type | Display | Trade |
| --- | --- | --- |
| Transferable asset | Show on profiles, collections, marketplace | Yes |
| Non-transferable access asset | Show on profiles, creator pages, access views | No default marketplace listing |
| Restricted-transfer asset | Show with service-specific badge | Only through declared service rules |
| Receipt/proof asset | Show as history/proof | Usually no |
| No asset | Service can still be indexed by events | No asset-level marketplace surface |

This keeps Medialane visible and composable without forcing every service into financialized behavior.

## Current Service Applications

### IP Club

`IP-Club` mints a per-club ERC-721 membership pass.

- `asset_standard`: ERC721
- `asset_role`: membership badge/access pass
- `transferability`: non-transferable
- `access_semantics`: current ownership of the non-transferable membership NFT
- `marketplace_visibility`: display/index, no default listing

The asset is valuable for visibility and access checks, but it should not be tradable unless a future transferable-pass service is intentionally designed.

### IP Subscription

`IP-Subscription` currently stores plan-specific subscription records and emits keyed lifecycle events. It does not yet mint an ERC-721 or ERC-1155 asset.

- `asset_standard`: none in current implementation
- `asset_role`: time-bound subscription record
- `transferability`: not applicable
- `access_semantics`: `is_subscribed(subscriber, plan_id)` derives access from expiry
- `marketplace_visibility`: service/event visibility, not asset marketplace listing

An asset-backed subscription should be a future explicit design, not an accidental property of the current record contract.

## Recommended Future Pattern For IP Subscription Assets

If `IP-Subscription` becomes asset-backed, prefer one of these explicit models:

### Non-Transferable Subscription Receipt

Mint a non-transferable ERC-721 or ERC-1155 receipt when a user subscribes.

- Best for visibility, profiles, creator analytics, and access display.
- Access still derives from contract expiry.
- Marketplace displays the asset but does not list it for sale.

### Transferable Time Pass

Mint a transferable ERC-721 or ERC-1155 pass where ownership controls the remaining access window.

- Best for markets around prepaid access.
- Requires explicit transfer semantics for expiry.
- More complex and should be a separate service mode or contract.

### Plan Edition Token

Mint ERC-1155 tokens where token IDs represent plan/time cohorts.

- Useful for batch visibility and edition-style access.
- Requires careful per-holder expiry or cohort expiry semantics.

## Design Constraint

Do not make a service asset tradable only to gain marketplace visibility.

Visibility is a platform/indexer responsibility. Tradability is a protocol right. Keep them separate.
