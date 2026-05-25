# IP Colab Collections Redesign and Audit Report

**Date:** 2026-05-25  
**Package:** `contracts/IP-Colab-Collections`  
**Contract:** `src/IPCollabCollection.cairo`  
**Status:** Legacy implementation replaced  
**Result:** Build passes. Test suite passes: 31 passed, 0 failed.

## Summary

`IP-Colab-Collections` has been redesigned as a collaborative ERC-721 collection contract.

The legacy implementation was a contribution ledger that emitted an `NFTMinted` event but did not mint an NFT. The redesigned contract now deploys a MIP-style `IPNft` backing collection, stores full content-addressed token URIs, and mints real NFTs to approved contributors through that `IPNft`.

The product model is:

- the owner creates contribution types,
- contributors submit metadata URIs,
- owner-managed verifiers approve or reject submissions,
- each approved contribution grants the original contributor one mint right,
- the resulting NFT is a standard MIP-style `IPNft` ERC-721 asset and can be traded through Medialane marketplace services.

## Legacy Issues Addressed

| Legacy issue | Resolution |
|---|---|
| `mint_nft` only emitted an event | Replaced with `mint_contribution`, which mints through a backing MIP-style `IPNft` |
| Any caller could mark a verified contribution minted | Only the original contributor can mint an approved contribution |
| Caller could choose arbitrary mint recipient | Recipient is always the original contributor |
| No ERC-721 ownership or transfer surface | Added a backing `IPNft` contract with OpenZeppelin ERC-721, Metadata, Enumerable, and SRC5 |
| Metadata stored as `felt252` | Replaced with full `ByteArray` token URIs |
| No content-addressed URI validation | Accepts only `ipfs://` and `ar://` |
| Missing contribution existence checks | Added bounded ID checks before reads and lifecycle transitions |
| Fake lifecycle events possible for nonexistent IDs | Verification and minting require existing contribution IDs |
| Low-score rejection was blocked | Rejection can record any score; approval enforces the minimum |
| Type re-registration reset counts | Duplicate type IDs are rejected |
| Constructor accepted zero owner | Zero owner is rejected |
| Internal fake marketplace listing state | Removed; marketplace integration uses ERC-721 marketplace services |
| Royalty percentage field implied enforcement | Removed; licensing belongs in metadata unless a future service opts into enforcement |
| No test suite | Added 31 tests |
| No archive parity with MIP | Added token-owner archive flow through backing `IPNft` |
| Stale dependencies | Updated to Cairo/Starknet `2.12.0`, OpenZeppelin `v0.20.0`, snforge `0.59.0` |

## Architecture Alignment

| Principle | Result |
|---|---|
| Smart contract is the only truth | Contribution state and mint links are in `IPCollabCollection`; token ownership, URI, original creator, and timestamp are in `IPNft` |
| Permissionless public good | Anyone can submit to an open contribution type; no database/app gate exists |
| Explicit curated layer | Approval is verifier-gated by design and should be declared in the service registry |
| Interoperable assets | Minted outputs use the same `IPNft` ERC-721 shape as `MIP-Collections-ERC721` |
| Licensing in metadata | The contract stores a content-addressed metadata URI; license traits live in that metadata |
| Soft enforcement by default | No transfer restriction, royalty hook, or jurisdictional policy is baked into the contract |
| Protocol/app split | No protocol fee, listing ledger, app-specific curation, or database-dependent rule exists |
| Event rebuildability | Contribution and mint events include IDs, contributors, URIs, scores, and timestamps needed by indexers |
| Service discoverability | A custom SRC5 interface ID is registered |

## Trust Model

The owner is the collection administrator.

The owner can:

- register contribution types,
- add and remove verifiers,
- approve or reject submissions directly,
- transfer ownership through Ownable.

Verifiers can:

- approve pending contributions that meet the type quality floor,
- reject pending contributions and record the actual quality score.

Contributors can:

- submit metadata URIs before a deadline,
- mint their own approved contribution once,
- transfer the resulting ERC-721.

The owner and verifiers cannot:

- mint someone else's contribution to themselves,
- change token metadata after mint,
- change token contributor provenance after mint,
- enforce marketplace fees,
- create or settle marketplace listings inside this contract.

## Contract Surface

### Constructor

```cairo
fn constructor(
    name: ByteArray,
    symbol: ByteArray,
    base_uri: ByteArray,
    owner: ContractAddress,
    ip_nft_class_hash: ClassHash,
)
```

Rejects the zero owner and zero class hash, initializes Ownable/SRC5, and deploys the backing `IPNft` contract.

Production deployments should pass the reviewed `MIP-Collections-ERC721` `IPNft` class hash when ABI-compatible. The local `IPNft.cairo` is retained as a package-local test fixture and MIP-shape mirror.

### Contribution Types

```cairo
fn register_contribution_type(
    type_id: felt252,
    min_quality_score: u8,
    submission_deadline: u64,
    max_supply: u256,
)
```

Owner-only. Rejects zero type IDs, duplicate type IDs, and zero max supply.

`max_supply` limits approvals for the type. This keeps review quality flexible while preventing more approved mints than the collection intended.

### Submission

```cairo
fn submit_contribution(
    token_uri: ByteArray,
    contribution_type: felt252,
) -> u256
```

Open to any caller while the type is registered and before its deadline. The URI must be content-addressed with `ipfs://` or `ar://`.

### Review

```cairo
fn approve_contribution(contribution_id: u256, quality_score: u8)
fn reject_contribution(contribution_id: u256, quality_score: u8)
```

Owner/verifier only. Approval requires `quality_score >= min_quality_score` and remaining type supply. Rejection records the score without requiring it to meet the floor.

### Mint

```cairo
fn mint_contribution(contribution_id: u256) -> u256
```

Contributor-only. Requires approved status and mints one ERC-721 token to the original contributor through the backing `IPNft`, recording the contributor as the immutable original creator.

### Archive

```cairo
fn archive_contribution_token(token_id: u256)
```

Token-owner-only. Calls `IPNft.archive(token_id)` and marks the linked contribution as archived. The legal record remains queryable and the token becomes non-transferable.

### Provenance Reads

```cairo
fn get_token_contribution(token_id: u256) -> u256
fn get_token_contributor(token_id: u256) -> ContractAddress
fn get_token_registered_at(token_id: u256) -> u64
fn get_token_data(token_id: u256) -> TokenData
```

These helpers preserve the link between a minted ERC-721 and the contribution that produced it.

## Security Review

### Access Control

Administrative functions use OpenZeppelin Ownable. Review functions require owner or verifier. Minting requires `caller == contribution.contributor`.

Tests cover:

- non-owner type registration rejection,
- verifier addition,
- non-verifier approval rejection,
- non-contributor mint rejection.

### Mint Safety

Minting uses the MIP `IPNft.mint` model, not `safe_mint`, matching `MIP-Collections-ERC721`. This allows durable IP records to be minted without requiring recipient receiver callbacks while preserving standard ERC-721 ownership and transfer behavior.

### Metadata Integrity

The token URI is stored once at mint and has no setter. Only `ipfs://` and `ar://` URIs are accepted. The metadata document is expected to carry OpenSea-compatible fields and Medialane license traits.

### Contribution Integrity

Contribution IDs start at `1`; zero and future IDs are rejected. A contribution can move from pending to approved, rejected, or minted. It cannot be reviewed twice or minted twice.

### Supply Integrity

Each contribution type has `max_supply`, `approved_count`, and `minted_count`. Approval cannot exceed the type max supply.

### Marketplace Safety

The contract intentionally contains no listing, buy, escrow, fee, or order logic. This avoids stale internal marketplace state and keeps venue behavior in marketplace service contracts.

### Upgrade Safety

No upgrade component is present.

## Test Coverage

The suite contains 31 tests:

| Category | Coverage |
|---|---|
| Constructor | backing `IPNft` deployment, name, symbol, owner, issuer, zero-owner rejection |
| Contribution types | owner registration, non-owner rejection, duplicate rejection |
| Submission | URI storage, count, contributor index, HTTP rejection, deadline rejection |
| Review | owner approval, verifier approval, non-verifier rejection, low-score approval rejection, low-score rejection path |
| Existence checks | nonexistent contribution approval rejection |
| Minting | contributor-only mint through `IPNft`, real ERC-721 ownership, token URI, one-mint limit, rejected contribution cannot mint |
| Supply | approval cap enforced |
| Provenance | token data links token to contribution and contributor |
| Transfer | ERC-721 transfer preserves contributor provenance |
| Archive | token-owner archive, non-owner rejection, archived token transfer rejection |
| Interfaces | ERC-721, ERC-721 Enumerable, custom collaborative interface |
| Events | `ContributionMinted` emitted with expected fields |
| URI helper | `ipfs://`, `ar://`, and HTTP prefix behavior |

## Verification

Commands run from `contracts/IP-Colab-Collections`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-colab \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-colab \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-colab \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
  snforge test
```

Results:

```text
scarb fmt: passed
scarb build: Finished `dev` profile target(s)
snforge test: Tests: 31 passed, 0 failed, 0 ignored, 0 filtered out
```

## Remaining Recommendations

Before production deployment:

1. Confirm the final service ID. Recommended: `ip-collab-erc721`.
2. Add the service to the SDK registry with explicit curated-review semantics.
3. Confirm whether ownership transfer should remain enabled for this service.
4. Confirm whether contribution type deadlines should be immutable forever or whether a future owner-only extension mechanism is needed.
5. Run a second human security review focused on ABI compatibility, event indexing, and marketplace routing.

## Production Recommendation

The redesigned contract is a valid candidate for a collaborative ERC-721 IP collection primitive, pending final human review, service-registry alignment, and deployment review.
