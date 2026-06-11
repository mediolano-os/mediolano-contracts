# IP Club — v2 Redesign Audit (2026-06-11)

**Date:** 2026-06-11
**Scope:** Principle-conformance audit of the post-2026-05-23 implementation, followed by the v2 redesign in this tree.
**Result:** v2 implemented; `scarb build` clean; `snforge test` 28 passed, 0 failed.

## Why a v2

The 2026-05-23 remediation already established the right architecture
(permissionless creation, non-transferable memberships enforced in the ERC-721
hook, safe_mint, direct creator fees, no platform fee). The v2 findings:

| # | Severity | Finding | v2 resolution |
| --- | --- | --- | --- |
| K1 | Medium (member sovereignty) | No exit path: non-transferable membership with no burn meant joining a public on-chain roster was permanent, and capped clubs never freed seats. The transfer hook already *permitted* burns (`to == 0`) but nothing exposed one | `leave_club(club_id, token_id)`: the member burns their own NFT via the registry (`IPClubNFT.burn` is manager-gated and verifies ownership). Always allowed — open or closed; no fee refund (paid value flowed to the creator at join). Frees the seat (tested: capped club accepts a new member after a leave) |
| K2 | Medium | `close_club` was terminal — a club could never reopen, inconsistent with the reversible creator switches in IP-Subscription/IP-Tickets v2 | Replaced by `set_club_open(club_id, open)` — creator-only, gates new joins only; leaving still works while closed (tested) |
| K3 | Low | `NewClubCreated` did not emit the deployed `club_nft` address — indexers had to call `get_club_record` per event | Event now carries `club_nft`; `ClubStatusUpdated` and `MemberLeft` added |
| K4 | Low | Manual `join_locked` reentrancy lock was redundant (state written before the fee transfer and mint; membership guarded by the NFT's one-per-wallet invariant) and cost two storage writes per join | Lock removed. The reentrancy mock now attempts exactly one nested join and the transaction reverts atomically (the token contract is not an ERC-721 receiver) — unbounded mock recursion previously masked rather than tested the behavior |
| K5 | Low | `ClubRecord` stored `id` (map key), `name`/`symbol`/`metadata_uri` (duplicated from the club's NFT contract — the asset is the source of truth), and a three-state `ClubStatus` enum with `Inactive` as a existence sentinel | Record slimmed to what the registry enforces: creator, club_nft, open, num_members, caps, fee terms. Existence ⇔ `creator != 0` |
| K6 | Info | `panic!` ByteArray error in the fee branch | felt252 asserts; fee settlement unwraps under the create-time invariant (paid club ⇔ non-zero token, terms immutable) |
| K7 | Info (measured optimization) | `join_club` duplicated the membership check (`is_member` cross-contract call) that `IPClubNFT.mint` already enforces ('Already has nft'), and `NftMinted` triplicated what ERC-721 `Transfer` + registry `NewMember` carry | Both removed. Measured with snforge before/after: **−437k L2 gas per join** (join-path tests −2.3% to −4.2%). Duplicate joins still revert atomically — the asset-side check covers every caller |

## v2 invariants

1. **Permissionless / ownerless / immutable**: anyone creates clubs; the registry has no admin; the NFT class hash is fixed at deploy; no fee taken by the contracts.
2. **One membership per wallet, non-transferable**: enforced by the NFT hook (mint and burn are the only movements).
3. **Creator's only lever is the join gate**: `set_club_open` never affects existing memberships or the right to leave.
4. **Exit is unconditional**: a member can always burn their own membership; the seat frees; the fee is not refunded.
5. **CEI**: registry state is final before the fee transfer and the mint; a failing external call reverts the join atomically.

## Interface changes (v1 → v2)

- `IIPClub`: `close_club` → `set_club_open(club_id, open)`; `leave_club(club_id, token_id)` added.
- `IIPClubNFT`: `burn(member, token_id)` added (manager-only, ownership-verified).
- `ClubRecord`: drops `id`/`name`/`symbol`/`metadata_uri`/`status`; gains `open: bool`.
- Events: `NewClubCreated` + `club_nft`; `ClubClosed` → `ClubStatusUpdated`; `MemberLeft` new.
- New SRC5 IDs: `starknet_keccak("mediolano.ip-club.v2")`, `starknet_keccak("mediolano.ip-club-nft.v2")`.

## Verification

```bash
scarb fmt && scarb build   # clean (scarb 2.17.0 / snforge 0.59.0, pinned)
snforge test               # 28 passed, 0 failed
```

New coverage: leave frees seat + rejoin under cap; leave while closed;
foreign-token leave rejected; direct NFT burn by non-manager rejected;
close/reopen cycle; reopened club accepts joins; bounded-reentrancy atomic
revert.

## Production recommendation

Pre-production until external review and deployment rehearsal (declare both
class hashes, deploy registry, verify the NFT class hash binding). The v1
report below is retained for history.

---

# IP Club Audit And Remediation Report

**Date:** 2026-05-23
**Package:** `contracts/IP-Club`
**Scope:** `IPClub.cairo`, `IPClubNFT.cairo`, interfaces, types, events, tests, README, and package manifests.
**Status:** Legacy audit completed; first-principles remediation implemented in the current working tree.

## Executive Summary

`IP-Club` is a two-contract protocol for NFT-gated IP communities:

- `IPClub` is a permissionless registry/factory. It creates club records, deploys one `IPClubNFT` per club, validates membership, and optionally processes an ERC-20 entry fee paid directly to the creator.
- `IPClubNFT` is the per-club ERC-721 membership pass. The `IPClub` manager is the only minter.

The legacy implementation had a sound product intent, but it mixed transferable ERC-721 pass behavior with membership-count semantics, accepted mutable metadata URLs, used unsafe minting, included admin upgradeability without a governance model, and had a reentrancy-prone fee path.

The refactored implementation now aligns with the Medialane public-goods posture:

- Anyone can create a club.
- No platform fee or database allowlist is introduced.
- Club metadata must be content-addressed: `ipfs://` or `ar://`.
- Membership NFTs are non-transferable.
- `join_club` uses a reentrancy lock and reserves membership state before external calls.
- Membership NFT minting uses `safe_mint`.
- Club-specific interfaces are SRC5 discoverable.
- Tests cover the remediated security and architecture decisions.

## Architecture Baseline

| Principle | Expectation For IP Club | Current Result |
| --- | --- | --- |
| Smart contract is the only truth | Membership, club status, limits, fees, and NFT ownership are reconstructable from chain state/events. | Pass |
| Permissionless public good | Anyone can create or join clubs according to visible contract rules. | Pass |
| Protocol/app split | No platform fees, database allowlists, or app-only gates in the protocol. | Pass |
| Metadata durability | Club metadata is content-addressed and portable. | Pass |
| Membership semantics | `is_member` and `num_members` should describe the same model. | Pass: membership NFTs are non-transferable |
| Asset safety | ERC-721 membership NFTs should not be locked in non-receiver contracts. | Pass: `safe_mint` |
| Agent/indexer readiness | Interfaces and events should be discoverable and unambiguous. | Pass |

## Remediated Findings

### Critical: Reentrancy In Fee-Based Joins

**Legacy issue:** `join_club` called arbitrary ERC-20 `transfer_from` before minting the membership NFT and before incrementing `num_members`. A malicious payment token could reenter `join_club` and bypass a max-member cap.

**Resolution:** `join_club` now:

- checks club existence, status, duplicate membership, and max-member cap;
- uses `join_locked` to reject reentrant calls;
- reserves `num_members` before external ERC-20 and ERC-721 receiver calls;
- relies on transaction rollback if payment or minting fails.

**Coverage:** `test_join_club_rejects_reentrant_payment_token`.

### High: Unclear Membership Semantics

**Legacy issue:** Membership was based on current NFT ownership, but the membership NFT was transferable and `num_members` only counted joins. Transfers could make `is_member` and `num_members` mean different things.

**Resolution:** `IPClubNFT` now blocks transfers after mint. Membership equals ownership of the non-transferable pass, and `num_members` represents active minted memberships for the club model.

**Coverage:** `test_membership_nft_is_non_transferable`.

### High: Mutable Or Invalid Metadata URI

**Legacy issue:** `metadata_uri` accepted arbitrary strings, including HTTP-style test URLs.

**Resolution:** `create_club` and the `IPClubNFT` constructor require metadata to start with `ipfs://` or `ar://`.

**Coverage:** `test_create_club_accepts_ar_uri`, `test_create_club_rejects_http_metadata`.

### High: Unsafe NFT Minting

**Legacy issue:** `IPClubNFT.mint` used plain `mint`, which could lock NFTs in contracts that cannot receive or manage ERC-721 tokens.

**Resolution:** `IPClubNFT.mint` now uses `safe_mint`.

**Coverage:** `test_join_club_mints_safe_membership_nft`, `test_join_club_rejects_non_receiver_contract`.

### High: Undeclared Upgrade Governance

**Legacy issue:** `IPClub` was upgradeable by an admin role, but the package did not define a governance model or upgrade invariants.

**Resolution:** Upgradeability and admin roles were removed. The manager is now a simpler, non-upgradeable public-good primitive.

### Medium: Constructor Validation

**Legacy issue:** The manager constructor did not validate the NFT class hash, and the admin argument could be invalid.

**Resolution:** The manager constructor now accepts only `ip_club_nft_class_hash` and rejects zero class hash. The admin argument no longer exists.

### Medium: Nonexistent Clubs

**Legacy issue:** Unknown club reads returned default records or failed indirectly through zero-address dispatches.

**Resolution:** `get_club_record`, `join_club`, `close_club`, and `is_member` explicitly reject missing clubs with `Club does not exist`.

**Coverage:** `test_get_club_record_rejects_missing_club`.

### Medium: Event And Interface Discoverability

**Legacy issue:** Events lacked key fields, and custom protocol interfaces were not registered in SRC5.

**Resolution:** Events now key club/member/token fields. `IPClub` registers `IIP_CLUB_ID`, and `IPClubNFT` registers `IIP_CLUB_NFT_ID`.

**Coverage:** `test_supports_custom_interfaces`.

### Medium: Caller Ergonomics

**Legacy issue:** README documented `create_club(...) -> u256`, but the interface returned nothing.

**Resolution:** `create_club` now returns `next_club_id`.

**Coverage:** `test_create_club_successfully`.

### Low: Toolchain Drift

**Legacy issue:** README and manifests were pinned to older Starknet Foundry/Scarb expectations.

**Resolution:** The package now uses the tested baseline:

- `starknet = "2.12.0"`
- OpenZeppelin split packages `0.20.0`
- `snforge_std = "0.59.0"`
- `assert_macros = "2.12.0"`

## Remaining Notes

The refactor intentionally chooses non-transferable membership NFTs. If Medialane later wants transferable club passes, that should be a separate contract or explicit mode with renamed counters such as `total_memberships` and clear cap semantics.

Entry fees are still paid directly to the club creator. That preserves protocol neutrality, but frontends should make the payment token and amount highly visible before joining.

`deploy_syscall` now uses a deterministic salt derived from creator and club ID, making club NFT deployment intent explicit while preserving one membership collection per club.

## Verification

Commands run from `contracts/IP-Club`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-club-redesign \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-club-redesign \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-club-redesign \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
  snforge test
```

Result:

```text
scarb build: passed
snforge test: 23 passed, 0 failed
```

## Production Recommendation

This implementation is materially safer and more coherent than the legacy contract. Before mainnet deployment, it should still receive an external security review, deployment rehearsal, and class-hash verification for the intended `IPClubNFT` artifact.
