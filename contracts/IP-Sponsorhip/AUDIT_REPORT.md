# IP Sponsorship — v2 Redesign Audit (2026-06-11)

**Date:** 2026-06-11
**Package:** `contracts/IP-Sponsorhip`
**Scope:** First audit of this contract (it never received the 2026-05 remediation pass), followed by the v2 rewrite in this tree.
**Result:** Full rewrite; `scarb build` clean; `snforge test` 24 passed, 0 failed.

## Findings (legacy implementation)

| # | Severity | Finding | v2 resolution |
| --- | --- | --- | --- |
| S1 | **Critical** | **No payment existed anywhere.** `sponsor_ip` stored bid numbers; `accept_sponsorship` issued a license recording an `amount_paid` that no token transfer ever backed. The economic core was fictional | Allowance-based settlement: a bid is a signal + an open ERC-20 allowance; `accept_bid` transfers sponsor → author directly (no escrow, the contract never custodies funds). Balance-asserted in tests |
| S2 | **Critical** | **Admin + revocable licenses.** A constructor-set `admin` could deactivate any registered IP; the author *or admin* could `revoke_license` at will — a sponsor's paid license was never safe | No admin exists (empty constructor). No revocation path exists for anyone: a license runs to its expiry, unconditionally (sold-value-inviolable) |
| S3 | High | **Parallel mutable IP registry.** `register_ip` kept a mini-registry with `felt252` metadata (too small for an IPFS CID) that the owner could rewrite after bids (`update_ip_metadata`) and the admin could kill | Registry removed entirely. Offers reference `(nft_contract, token_id)`; ownership is verified via `owner_of` at creation **and re-verified at acceptance** (an offer does not survive the sale of the asset). License terms are content-addressed ByteArray URIs (`ipfs://`/`ar://`) |
| S4 | High | **Unbounded O(n) Vec surgery as a griefing surface.** Bids, user lists, and the active-offers list were on-chain Vecs with clear-and-repopulate rewrite loops; free bid spam could make `accept_sponsorship` unaffordable | All enumeration structures removed. One standing bid per `(offer, sponsor)` in a Map (rebid overwrites, O(1) accept); history lives in keyed events |
| S5 | Medium | Mutable offer terms (`update_sponsorship_offer` changed the price range under standing bids); `reject_sponsorship` only emitted an event while the bid remained acceptable; `deactivate_ip` left stale active-offer entries forever | Terms are immutable (new terms = new offer). Rejection removed — the author simply doesn't accept; sponsors `retract_bid` (or revoke allowance, which makes acceptance revert atomically). Reversible `set_offer_open` is the author's only lever |
| S6 | Low | `min_price`/`max_price` range: capping what a sponsor may *offer* served no one; `transferable: true` was hardcoded on every license | `min_amount` floor only; `transferable` chosen per offer at creation |
| S7 | Info | Stale toolchain (starknet 2.11.2 / snforge 0.40), no SRC5 discovery, no README, ad-hoc error module | Baseline toolchain (2.12.0 / 0.59.0, pinned in `.tool-versions`), SRC5 ID `starknet_keccak("mediolano.ip-sponsorship.v2")`, README + this report, inline felt252 asserts |
| S8 | Info (documented, unchanged) | Bid amounts are public on-chain — competitor-visible negotiation. Sealed bids / confidential amounts are commercial-layer concerns (commitments + ZK), deliberately not in this substrate primitive | Documented in the README; the offer's `specific_sponsor` targeting covers the private-invitation case |

## v2 invariants

1. **Permissionless / ownerless / immutable**: anyone owning an ERC-721 may offer; no admin, no upgrade path, no fee; offer terms never change.
2. **The asset layer is the registry**: every license traces to an ERC-721 the author provably owned at acceptance time.
3. **No custody**: the contract never holds tokens; settlement is a single `transfer_from(sponsor → author)` inside acceptance.
4. **Issued licenses are inviolable**: valid while `expires_at >= now`; nothing can shorten or revoke them.
5. **CEI**: offer closed, bid consumed, and license recorded before the payment interaction; a failing transfer reverts the acceptance atomically.
6. **Minimal storage**: three maps + two counters; no enumerable lists; existence derived from `author != 0`.

## Verification

```bash
scarb fmt && scarb build   # clean (scarb 2.17.0 / snforge 0.59.0)
snforge test               # 24 passed, 0 failed
```

Coverage highlights: owner-verified creation + non-owner rejection;
settlement balance assertions; accept-after-IP-sale rejection; no-allowance
atomic revert (the sponsor's de-facto withdrawal); retract; rebid overwrite;
invited-sponsor restriction; closed/reopened offer gating; license expiry
boundary (inclusive), transfer rules, non-transferable enforcement; SRC5.

## Notes

- The directory name carries a historical typo (`IP-Sponsorhip`). Renaming is
  deliberately out of scope for this PR (it would touch CI path detection and
  external links in one diff with a full rewrite); track as a small follow-up.

## Production recommendation

Pre-production until external review and deployment rehearsal.
