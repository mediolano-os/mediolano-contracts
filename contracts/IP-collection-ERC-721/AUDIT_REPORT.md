# IP Collection ERC-721 Redesign and Audit Report

**Date:** 2026-05-23
**Package:** `contracts/IP-collection-ERC-721`
**Status:** Rebuilt from legacy implementation
**Result:** Build passes. Test suite passes: 35 passed, 0 failed.

## Summary

`IP-collection-ERC-721` has been redesigned as an owner-minted ERC-721 collection for canonical IP issuance.

The product slot is valid and distinct from `IP-Programmable-ERC-721`:

- `IP-Programmable-ERC-721`: shared collection where anyone can mint.
- `IP-collection-ERC-721`: permissionless-to-deploy collection where only the collection owner can mint.

This aligns with Mediolano's public-goods posture: anyone can deploy and use the primitive, no platform database gates deployment or transfers, no protocol fee exists, and the contract itself is the authority for ownership, minting, metadata pointers, and provenance.

## Service Identity

Recommended registry identity:

```text
owner-minted-erc721
```

This service ID describes the behavior without confusing it with the shared permissionless `ip-erc721` collection or a broader `mip-erc721` factory/per-creator model.

## Legacy Issues Addressed

The previous implementation had material issues:

| Legacy issue | Resolution |
|---|---|
| Token ID counter was never incremented | Replaced with `next_token_id`, initialized at `1` and incremented on mint |
| No per-token metadata URI in mint | `mint_item(recipient, token_uri)` stores full `ByteArray` URI |
| URI storage used `felt252` | Replaced with `Map<u256, ByteArray>` |
| No IP provenance fields | Added immutable `token_issuers` and `token_registered_at` |
| Upgradeable by owner | Removed `UpgradeableComponent` |
| Unsafe custom `transfer_token` helper | Removed; standard ERC-721 transfers only |
| Manual `user_tokens` ledger drifted from ERC-721 ownership | Removed; `ERC721EnumerableComponent` is used |
| Unused shadow `owners` and `balances` storage | Removed |
| Alexandria list dependency | Removed |
| Incomplete/out-of-sync tests | Replaced with 35 passing tests |
| Stale test runner dependency | Updated `snforge_std` to `0.59.0` |
| `.tool-versions` selected unavailable Scarb | Updated to `scarb 2.17.0` |
| No custom interface detection | Added SRC5 registration for `IIP_COLLECTION_ID` |

## Architecture Baseline

The redesign was evaluated against the current Medialane/Mediolano architecture:

| Principle | Result |
|---|---|
| Smart contract is the only truth | Ownership, token existence, URI, mint authority, and provenance are on-chain |
| Permissionless public good | Anyone can deploy a collection; mint authority is transparent contract logic |
| Interoperable assets | ERC-721 and ERC-721 Enumerable are exposed through OpenZeppelin components |
| Licensing in metadata | Contract stores content-addressed URI; license terms live in metadata attributes |
| Soft enforcement by default | No license enforcement or policy logic in the contract |
| Protocol/app split | No platform fees, curation, allowlists, or database-dependent gates |
| Immutable IP records | No upgrade path; token URI and provenance have no setters |
| Indexer rebuildability | ERC-721 events plus `IPMinted` provide indexing surface |
| Agent/indexer detection | Custom `IIP_COLLECTION_ID` is registered through SRC5 |

## Trust Model

The collection owner is the sole mint authority.

The owner can:

- Mint new tokens.
- Transfer collection ownership through OpenZeppelin Ownable.
- Renounce ownership, which permanently disables future owner-only minting.

The owner cannot:

- Upgrade the contract.
- Change a token URI after mint.
- Change a token issuer after mint.
- Change a token registration timestamp after mint.
- Use a custom contract transfer path.
- Take protocol fees.

This is an explicit service model, not a hidden platform gate.

## Contract Surface

### Constructor

```cairo
fn constructor(
    name: ByteArray,
    symbol: ByteArray,
    owner: ContractAddress,
)
```

The constructor rejects the zero owner, initializes ERC-721 metadata, initializes enumerable storage, initializes Ownable, registers `IIP_COLLECTION_ID`, records `collection_issuer`, and sets `next_token_id` to `1`.

### IP Collection Interface

```cairo
fn mint_item(
    recipient: ContractAddress,
    token_uri: ByteArray,
) -> u256
```

Owner-only. Uses `safe_mint`, validates the recipient and URI scheme, records immutable provenance, emits `IPMinted`, and returns the new token ID.

```cairo
fn get_collection_issuer() -> ContractAddress
fn get_token_issuer(token_id: u256) -> ContractAddress
fn get_token_registered_at(token_id: u256) -> u64
fn get_token_data(token_id: u256) -> TokenData
```

Read-only provenance helpers. Token-specific helpers revert for nonexistent tokens.

## Security Review

### Access Control

Minting calls `self.ownable.assert_only_owner()`. Tests cover owner minting, non-owner rejection, and minting after ownership transfer.

### Metadata Integrity

The contract accepts only `ipfs://` and `ar://` URIs. The URI is written once at mint and has no setter.

### Provenance Integrity

`token_issuers[token_id]` records `get_caller_address()` at mint time. Because minting is owner-only, this is the collection authority that issued the token. If ownership is transferred, future tokens record the new owner while `collection_issuer` remains the initial issuer.

`token_registered_at[token_id]` records `get_block_timestamp()` at mint time. There is no setter.

### Transfer Safety

The custom legacy transfer helper was removed. Transfers use OpenZeppelin ERC-721 `transfer_from` / approval behavior.

### Receiver Safety

Minting uses `safe_mint`. Tests cover minting to a mock SRC6 account, minting to an ERC-721 receiver, and rejection for a non-receiver contract.

### Upgrade Safety

No upgrade component is present. The contract class cannot be changed by the owner.

### Fee Safety

No fee logic exists.

### Interface Detection

The contract registers:

```cairo
pub const IIP_COLLECTION_ID: felt252 =
    0x0169025717e7d54a71b5dcbf608cd0a71b562570902dad8b7d4a7e80fe15eeb0;
```

The ID is the XOR of the owner-minted IP collection selectors:

- `mint_item`
- `get_collection_issuer`
- `get_token_issuer`
- `get_token_registered_at`
- `get_token_data`

Tests cover `supports_interface(IIP_COLLECTION_ID)`.

## Test Coverage

The rebuilt suite contains 35 tests:

| Category | Coverage |
|---|---|
| Constructor | name, symbol, owner, collection issuer, zero-owner rejection |
| Owner minting | IPFS URI, Arweave URI, sequential IDs, non-owner rejection |
| Ownership transfer | new owner can mint; initial issuer remains unchanged |
| Metadata | exact URI return, unsupported URI rejection, nonexistent token rejection |
| Provenance | issuer, timestamp, `get_token_data`, nonexistent token rejection |
| Events | `IPMinted` emitted with expected fields |
| Safe mint | mock account success, ERC-721 receiver success, non-receiver rejection |
| ERC-721 behavior | owner, balance, transfer, provenance preserved after transfer |
| Enumerable | total supply, global index, owner index, transfer updates |
| Interfaces | ERC-721, ERC-721 Enumerable, and IP collection SRC5 support |
| Helpers | URI prefix helper unit tests |

## Verification

Commands run from `contracts/IP-collection-ERC-721`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-collection-erc721 \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-collection-erc721 \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-collection-erc721 \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
  snforge test
```

Results:

```text
scarb fmt: passed
scarb build: Finished `dev` profile target(s)
snforge test: Tests: 35 passed, 0 failed, 0 ignored, 0 filtered out
```

## Remaining Recommendations

Before deployment:

1. Confirm the final service ID and registry description.
2. Decide whether ownership transfer should remain enabled or whether a future variant should be permanently owner-fixed.
3. Run a second review focused on ABI compatibility with frontend/indexer expectations.
4. Declare a fresh class hash rather than reusing any legacy class.

## Production Recommendation

This rebuilt version is a valid candidate for the owner-minted ERC-721 IP collection primitive, pending final human review, service-registry alignment, and deployment review.
