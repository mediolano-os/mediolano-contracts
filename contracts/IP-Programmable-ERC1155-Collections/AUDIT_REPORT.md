# IP-Programmable-ERC1155-Collections — Audit Report

**Date:** 2026-05-19
**Scope:** `contracts/IP-Programmable-ERC1155-Collections` current source
**Implementation version:** `0.2.0`
**Status:** Build passes. Test suite requires the pinned Foundry/std toolchain.

## Overview

`IP-Programmable-ERC1155-Collections` is a two-contract Starknet system:

| Contract | Role |
|---|---|
| `IPCollectionFactory` | Permissionless factory for deploying `IPCollection` instances |
| `IPCollection` | Immutable ERC-1155 collection with owner-gated minting, immutable provenance, protocol-neutral token URIs, and ERC-2981 royalties |

The collection uses OpenZeppelin Cairo `v0.20.0` components for ERC-1155, Ownable, SRC5, and ERC-2981. There is no `UpgradeableComponent` in `IPCollection`; each deployed collection is immutable.

## Audit Findings And Resolution

### [RESOLVED] URI scheme allowlist was too restrictive

Earlier code accepted only `ipfs://` and `ar://` token URIs. This was brittle because immutable collections would reject future metadata and content-addressing systems.

**Resolution:** Token URI validation is now protocol-neutral. The contract only rejects empty URIs or URIs longer than 2048 bytes on first mint.

### [RESOLVED] Creator/provenance documentation conflicted with code

The README said `to` was recorded as creator, while the code records the caller/collection owner on first mint.

**Resolution:** Documentation now matches implementation: the caller is the immutable token creator, and `to` is only the balance recipient.

### [RESOLVED] Factory class-hash updates were silent

The factory owner could update the class hash for future deployments without emitting a dedicated event.

**Resolution:** `update_collection_class_hash` now emits `CollectionClassHashUpdated { previous_class_hash, new_class_hash }`.

### [RESOLVED] Factory accepted zero class hash

The factory owner could set the class hash to zero, making future deployments fail.

**Resolution:** `update_collection_class_hash` now rejects the zero class hash.

### [RESOLVED] Constructors accepted invalid authority or implementation inputs

The collection and factory constructors needed explicit guards for zero owner/class-hash inputs.

**Resolution:** `IPCollection` rejects a zero owner, and `IPCollectionFactory` rejects a zero owner or zero collection class hash.

### [RESOLVED] Version tracking was missing

Immutable deployments need a direct way to identify implementation generation after deployment.

**Resolution:** `IPCollection` and `IPCollectionFactory` expose `version() -> ByteArray`, currently returning `0.2.0`. Package version and lockfile were also bumped to `0.2.0`.

### [RESOLVED] Test dependency mismatch

The package had stale toolchain metadata and `snforge_std` did not match the installed Foundry runner.

**Resolution:** `.tool-versions` now pins Scarb `2.17.0` and Starknet Foundry `0.59.0`; `snforge_std` is pinned to `0.59.0`.

## Residual Risks

### [LOW] Batch mint is implemented as repeated single mints

`batch_mint_item` loops over `_mint_single`, producing one ERC-1155 single mint and one acceptance check per token type. This preserves per-token URI/provenance behavior but costs more gas and exposes per-item callback ordering.

**Recommendation:** Keep as-is unless gas pressure becomes material, or implement a dedicated internal batch mint that records provenance first and then calls OZ `batch_mint_with_acceptance_check`.

### [LOW] URI validity is off-chain by design

The contract only ensures token URIs are non-empty and no longer than 2048 bytes. It does not validate IPFS CIDs, Arweave transaction IDs, HTTP URLs, or future schemes.

**Recommendation:** SDKs/frontends should validate known URI formats, fetch metadata, preview it before minting, and indexers should classify URI status after mint.

## Verification

- `SCARB_CACHE=/private/tmp/scarb-cache-erc1155-audit scarb build` passes with Scarb `2.17.0`.
- Test suite contains 71 tests after the patch. Run with Starknet Foundry `0.59.0`.

## Files Audited

```text
contracts/IP-Programmable-ERC1155-Collections/
├── Scarb.toml
├── Scarb.lock
├── .tool-versions
├── src/IPCollection.cairo
├── src/IPCollectionFactory.cairo
├── src/interfaces/IIPCollection.cairo
├── src/interfaces/IIPCollectionFactory.cairo
├── src/types.cairo
└── src/tests/
```
