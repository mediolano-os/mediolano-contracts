# IP Time Capsule — v2 Redesign Audit (2026-06-10)

**Date:** 2026-06-10
**Package:** `contracts/IP-Time-Capsule`
**Scope:** Principle-conformance + security audit of the existing implementation, followed by the v2 redesign in this tree.
**Result:** v2 implemented; `scarb build` clean; `snforge test` 30 passed, 0 failed.

## Summary

IP-Time-Capsule was the best-conforming contract in the catalog before this
pass: permissionless mint, no owner, no admin, no fee, content-addressed URIs,
and an honest commitment-based privacy model (the contract never stores
plaintext before reveal). The audit still found one genuine
checks-effects-interactions bug and the usual data-minimization candidates.

## Findings

| # | Severity | Finding | v2 resolution |
| --- | --- | --- | --- |
| C1 | **High** | `mint_capsule` called `safe_mint` (external receiver callback) **before** writing the capsule record. A reentrant receiver observed a minted token with an empty capsule: `get_capsule_data` returned zeros, and `is_unlocked` returned `true` (reveal_at = 0). A forged reveal was still blocked (zero commitment can't be matched), but integrators reading mid-mint saw inconsistent state | Capsule record is written before `safe_mint`. Proven by a new `ProbingReceiver` mock that reads the capsule from inside `on_erc721_received` and reverts on an empty commitment (`test_capsule_state_written_before_receiver_callback`) |
| C2 | Medium | `ERC721EnumerableComponent` taxed every transfer with enumeration bookkeeping that indexers rebuild from standard Transfer events anyway (the contract is the source of truth; enumeration is a cache concern) | Component removed; empty ERC-721 hooks |
| C3 | Low | `TimeCapsule.token_id` duplicated the map key; `status: u8` + two constants duplicated derivable state; `content_salt` was stored forever after reveal despite having no post-reveal utility (commitment already verified; salt preserved in the reveal event) | All three dropped. Revealed ⇔ `revealed_at != 0`; `TimeCapsuleData` exposes a derived `revealed: bool` |
| C4 | Info | Reveal assertions ran input validation and the Poseidon commitment check before the cheaper unlock/authorization checks | Reordered: sealed → unlocked → authorized → inputs → commitment. Behavior identical (asserts are all-or-nothing) |
| C5 | Info (documented, unchanged) | If both the creator and owner lose `content_hash`/`content_salt`, the capsule is unrevealable forever — inherent to a commitment scheme; the contract cannot decrypt. Liveness mitigation (threshold/timelock encryption of the off-chain payload) belongs in the off-chain layer, not this primitive | Documented here; no contract change |
| C6 | Info (documented, unchanged) | `max_lock_duration` and `hidden_uri` are per-deployment constructor parameters — deliberate deployment-time configuration, not runtime admin (there are no setters; the deployment stays immutable) | Kept; noted for the canonical-deployment decision |

## What was already right (kept verbatim)

- Commitment-first privacy: only `encrypted_uri` + salted Poseidon commitment
  on-chain before reveal; plaintext URI only after `reveal_at`.
- Permissionless mint to any non-zero recipient; creator-or-current-owner
  reveal authorization (the creator holds the plaintext and salt; the owner
  holds the asset — either can complete disclosure).
- Content-addressed URI enforcement (`ipfs://` / `ar://`), URI/name/symbol
  length caps, future-bounded `reveal_at`.
- Inclusive unlock boundary (`now >= reveal_at`), shared hidden URI before
  reveal, SRC5 discovery.

## v2 invariants

1. **Permissionless / ownerless / immutable**: no admin, no setters, no fee; deployment parameters are fixed at construction.
2. **No plaintext before reveal**: storage and events carry only the encrypted pointer and the commitment until `reveal_capsule` succeeds.
3. **CEI**: capsule state is final before any external call in `mint_capsule`.
4. **Commitment binding**: a reveal is accepted only when `Poseidon(content_hash, content_salt)` matches the mint-time commitment; first valid reveal is final.
5. **Minimal storage**: no enumeration structures, no derivable fields; the salt lives only in the reveal event.

## Interface changes (v1 → v2)

- Removed: ERC721Enumerable surface (`total_supply`, `token_by_index`, …), `STATUS_*` constants, `content_salt`/`status` from `TimeCapsuleData` (replaced by `revealed: bool`).
- Unchanged: all `ITimeCapsule` entry points and their semantics.
- New SRC5 ID (surface changed): `0x035accb37e9eaf4dc53e1afab6bb09430fb0e4b53b2f8fc0abc76174ce7121a9` = `starknet_keccak("mediolano.ip-time-capsule.v2")`.

## Verification

```bash
scarb fmt && scarb build   # clean (scarb 2.17.0 / snforge 0.59.0, pinned in .tool-versions)
snforge test               # 30 passed, 0 failed
```

Coverage highlights: CEI probe inside the mint callback; hidden→revealed
`token_uri` transition; unlock boundary; wrong-commitment / empty-salt /
double-reveal / unauthorized-reveal rejections; owner-after-transfer reveal;
receiver and non-receiver mint paths; SRC5 discovery.

## Production recommendation

Pre-production until external review and deployment rehearsal. The canonical
deployment's `hidden_uri` and `max_lock_duration` should be chosen
deliberately at that point (C6).
