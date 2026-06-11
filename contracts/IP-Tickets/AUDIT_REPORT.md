# IP Tickets — v2 Redesign Audit (2026-06-10)

**Date:** 2026-06-10
**Scope:** Principle-conformance audit of the post-2026-05-23 implementation, followed by the v2 redesign in this tree.
**Result:** v2 implemented; `scarb build` clean; `snforge test` 26 passed, 0 failed.

## Why a v2

Unlike IP-Subscription, the 2026-05-23 IP-Tickets remediation already satisfied
the load-bearing Mediolano principles: permissionless series creation, no
contract owner, zero fees, direct creator payment, standard ERC-721 interop,
content-addressed metadata. The v2 findings are correspondingly smaller:

| # | Severity | Finding | v2 resolution |
| --- | --- | --- | --- |
| T1 | Medium | No way for a creator to stop sales of a series (e.g. a cancelled event) — expiration was the only sunset | `set_series_active(series_id, active)` added: series-creator-only, gates **minting only**. Existing tickets keep access, transferability, and redemption (tested) — mirrors the IP-Subscription v2 deactivation decision |
| T2 | Medium | `royaltyInfo` was camelCase-only and the ERC-2981 interface ID was not registered in SRC5, so royalty-aware marketplaces could not discover it | `IERC2981_ID` registered in the constructor; snake_case `royalty_info` added alongside the legacy camelCase entry point |
| T3 | Low | Manual `mint_locked` reentrancy lock was redundant: all series/token state is written before `collect_payment` and `safe_mint` (checks-effects-interactions), and a reentrant call runs under its own caller context | Lock removed; `test_reentrant_payment_token_reverts_atomically` documents the failure mode (the reentrant token can only mint to itself, it is not an ERC-721 receiver, the whole tx reverts, the buyer is never charged) |
| T4 | Low | `TicketSeries.id` and `.exists` duplicated the map key / derivable state; wasted `redeemed_tickets.write(false)` on every mint | Both fields dropped (existence = `creator != 0`); wasted write removed |
| T5 | Info | `panic!` ByteArray errors in two branches, inconsistent with felt252 asserts | Replaced with felt252 asserts; `collect_payment` unwraps under the create-time invariant (paid series always carries a non-zero token) |
| T6 | Info (documented, not changed) | Redeemed/expired tickets remain transferable ERC-721s that no longer grant access — a secondary buyer could overpay for a worthless ticket | Kept by design (standard-interop over lock-in); README now states loudly that integrators must surface `get_ticket_data().valid` on secondary listings |
| T7 | Info (deferred) | Redemption events publicly link wallet → attendance. Privacy-preserving redemption (ZK entitlement proofs) is a commercial-layer concern, not a substrate concern | Out of scope for the public primitive; tracked in the Medialane privacy-model work |

## v2 invariants

1. **Permissionless**: anyone creates series; anyone mints from an active, unexpired, unsold-out series.
2. **Ownerless / immutable**: no contract owner, no admin, no upgrade path, no fee. Series terms (price, supply, expiration, royalty, token) never change.
3. **Sold tickets are inviolable**: nothing the series creator does (including deactivation) affects access, transfer, or redemption of existing tickets.
4. **CEI**: all storage writes precede the external calls in `mint_ticket`; a reverting payment or receiver check reverts the whole transaction.
5. **One accounting source**: `active_ticket_balance` is maintained exclusively by the ERC-721 transfer hook and `redeem_ticket`; redeemed tickets are excluded from hook accounting.

## Interface changes (v1 → v2)

- Added: `set_series_active(series_id, active)`, snake_case `royalty_info`, `SeriesStatusUpdated` event, ERC-2981 SRC5 registration.
- Changed: `TicketSeries` drops `id`/`exists`, gains `active`.
- New SRC5 ID (interface changed): `0x01362a7858e49627a551fd488764bb296e2e74caaffd1d6a171580904c90c344` = `starknet_keccak("mediolano.ip-tickets.v2")`.

## Verification

```bash
scarb fmt && scarb build   # clean
snforge test               # 26 passed, 0 failed
```

New coverage: creator-only toggle, deactivation blocks mint, deactivation
preserves access/transfer/redemption, reactivation, snake_case royalty,
ERC-2981 SRC5 discovery, atomic revert on reentrant payment token.

## Production recommendation

Pre-production until external review and deployment rehearsal. The v1 report
below is retained for history.

---

# IP Tickets Audit And Remediation Report

**Date:** 2026-05-23
**Package:** `contracts/IP-Tickets`
**Scope:** `IPTicketService.cairo`, interface, types, tests, mocks, manifest, and service-asset doctrine alignment.
**Status:** Legacy audit completed; first-principles remediation implemented in the current working tree.

## Executive Summary

`IP-Tickets` is now a transferable ERC-721 ticket service where ticket access follows current ownership until expiration or redemption.

The legacy implementation had the right instinct because it minted an indexable ERC-721 asset, but access was tracked through a separate minted-balance map that did not update on transfers. That meant a seller could keep access after selling a ticket, while the buyer received the visible NFT without the right to use it.

The redesigned implementation fixes that mismatch:

- Tickets are ERC-721 assets.
- Tickets are transferable.
- Access follows current ERC-721 ownership.
- Redeeming a ticket removes access.
- Expiration removes access.
- Paid minting is protected by a reentrancy guard.
- Ticket metadata is content-addressed and exposed through ERC-721 `token_uri`.
- The service has a custom SRC5 interface ID.

## Service Asset Declaration

| Field | Value |
| --- | --- |
| `service_id` | `ip-tickets` |
| `asset_standard` | ERC721 |
| `asset_role` | Transferable ticket / redeemable access pass |
| `transferability` | Transferable until/after redemption, but redeemed tickets do not grant access |
| `access_semantics` | Current ownership of at least one unredeemed, unexpired ticket in a series |
| `marketplace_visibility` | Display and list as ERC721 tickets |
| `metadata_uri_policy` | `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_TICKET_SERVICE_ID` |

This model intentionally makes tradability honest: if a ticket is sold, the access moves to the buyer.

## Remediated Findings

### Critical: Ticket Access Did Not Follow ERC-721 Transfers

**Legacy issue:** `has_valid_ticket` checked a minted balance that never changed on transfer.

**Resolution:** ERC-721 transfer hooks now update active ticket balances for unredeemed tickets. `has_valid_ticket(user, series_id)` checks the current active balance and the series expiration.

**Coverage:** `test_transfer_moves_access`.

### Critical: Reentrancy In Paid Mint Flow

**Legacy issue:** The contract called arbitrary ERC-20 `transfer_from` before updating ticket supply.

**Resolution:** `mint_ticket` now uses a reentrancy guard, reserves supply and token-series state before external calls, and relies on transaction rollback if payment or `safe_mint` fails.

**Coverage:** `test_reentrant_payment_token_rejected`.

### High: Expired Tickets Could Be Minted

**Legacy issue:** Users could pay for already-expired tickets.

**Resolution:** Series creation requires future expiration, and minting requires `get_block_timestamp() < expiration`.

**Coverage:** `test_create_ticket_series_rejects_past_expiration`, `test_mint_ticket_rejects_expired_series`.

### High: Plain Mint Could Lock Tickets

**Legacy issue:** The contract used plain `mint`.

**Resolution:** Ticket minting now uses `safe_mint`.

**Coverage:** `test_mint_to_non_receiver_rejected`.

### High: ERC-20 Transfer Result Was Ignored

**Legacy issue:** Ticket minting ignored the return value of `transfer_from`.

**Resolution:** Payment collection asserts that `transfer_from` returns true.

**Coverage:** `test_paid_ticket_transfers_tokens`.

### High: Metadata Was Not Content-Addressed Or Token-Discoverable

**Legacy issue:** Series metadata was stored as `felt252` and not exposed as standard ERC-721 token metadata.

**Resolution:** Series metadata is a `ByteArray`, must start with `ipfs://` or `ar://`, and each ticket's `token_uri` returns its series metadata.

**Coverage:** `test_mint_free_ticket`, `test_create_ticket_series_rejects_http_uri`.

### High: Royalty Percentage Was Unbounded

**Legacy issue:** Royalty basis points could exceed `10000`.

**Resolution:** Series creation requires `royalty_bps <= 10000`, and `royaltyInfo` requires an existing token.

**Coverage:** `test_create_ticket_series_rejects_bad_royalty`, `test_royalty_info`, `test_royalty_info_rejects_missing_token`.

### Medium: Missing Validation

**Legacy issue:** Constructor and series creation lacked validation for important fields.

**Resolution:** Constructor validates name and symbol. Series creation validates creator, supply, expiration, royalty, metadata, and payment-token configuration.

### Medium: Missing Service Discoverability

**Legacy issue:** The contract did not register a custom SRC5 service interface.

**Resolution:** The contract registers `IIP_TICKET_SERVICE_ID`.

**Coverage:** `test_supports_ticket_service_interface`.

### Medium: Events Were Not Keyed

**Legacy issue:** Event fields were not keyed for indexers.

**Resolution:** Ticket series, token, creator, and owner fields are keyed in lifecycle events.

### Medium: Missing Read APIs

**Legacy issue:** SDKs and agents could not query structured ticket/series state.

**Resolution:** The interface now exposes:

- `get_ticket_series`
- `get_ticket_data`
- `get_ticket_series_id`
- `get_active_ticket_balance`
- `get_last_series_id`
- `total_supply`

## Current Semantics

Ticket access is valid when:

```text
series.exists
&& get_block_timestamp() < series.expiration
&& active_ticket_balance[(user, series_id)] > 0
```

Redeeming a ticket:

- requires the current token owner;
- requires the ticket to be unredeemed;
- requires the series to be unexpired;
- marks the token redeemed;
- decrements the owner's active ticket balance.

Transfers:

- move active access for unredeemed tickets;
- do not restore access for redeemed tickets;
- remain standard ERC-721 transfers for marketplace compatibility.

## Verification

Commands run from `contracts/IP-Tickets`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-tickets-redesign \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-tickets-redesign \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-tickets-redesign \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/installs/starknet-foundry/0.59.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
  /Users/kalamaha/.asdf/installs/starknet-foundry/0.59.0/bin/snforge test
```

Result:

```text
scarb build: passed
snforge test: 20 passed, 0 failed
```

## Remaining Notes

The current model does not block transfer after redemption. This keeps the ERC-721 asset visible and movable as a collectible receipt, but redeemed tickets do not grant access.

There is no refund or cancellation mechanism. Ticket sales are direct creator payments.

Royalty calculation is exposed through `royaltyInfo`, but marketplace enforcement remains marketplace-specific.

## Production Recommendation

The redesigned implementation is materially safer and now aligns visibility, tradability, and access semantics. Before mainnet deployment, it should still receive an external security review and deployment rehearsal.
