# IP Colab Collections

Collaborative ERC-721 IP collection for Starknet/Cairo.

This package has been redesigned from the legacy contribution ledger into a MIP-style collaborative NFT collection. The old code treated minting as an event-only flag; the current contract deploys a backing `IPNft` ERC-721 contract, stores full content-addressed metadata URIs, and mints actual transferable NFTs to approved contributors.

## Design Summary

`IP-Colab-Collections` lets a collection owner run a curated collaborative NFT project:

1. The owner creates contribution types with quality rules, submission deadlines, and max supply.
2. Contributors submit IPFS or Arweave metadata URIs.
3. The owner or an authorized verifier approves or rejects each submission.
4. An approved contributor can mint exactly one NFT for that contribution.
5. The minted NFT lives in the backing `IPNft` contract, is owned by the original contributor, and behaves as a standard ERC-721 asset.
6. Marketplace integration happens through the ERC-721 transfer/approval/token URI surface, not through internal listing state.

## Architecture Principles

The redesigned contract follows the Medialane/Mediolano architecture:

- **Contract as source of truth:** contribution lifecycle lives in `IPCollabCollection`; token ownership, token URI, contributor provenance, and registration timestamp live in the backing `IPNft`.
- **MIP-compatible NFT shape:** the backing NFT follows the `MIP-Collections-ERC721` `IPNft` model: immutable ERC-721, enumerable, permanent token URI, original creator, and registration timestamp.
- **Interoperable assets:** the backing `IPNft` exposes ERC-721, ERC-721 Enumerable, ERC-721 Metadata, and SRC5 interface detection.
- **OpenSea-compatible metadata:** each contribution stores a full `ByteArray` token URI expected to resolve to standard NFT metadata.
- **Content-addressed storage:** accepted URI schemes are `ipfs://` and `ar://`.
- **Soft licensing by default:** license terms belong in the metadata attributes, not in hardcoded transfer restrictions.
- **No protocol fee:** the contract has no marketplace fee or platform fee.
- **Marketplace separation:** listings, offers, purchases, auctions, and settlement belong in Medialane marketplace services.

## Trust Model

The collection owner can:

- Register contribution types.
- Add and remove verifiers.
- Approve or reject submissions, either directly or through verifiers.
- Transfer ownership through OpenZeppelin Ownable.

Contributors can:

- Submit metadata URIs before a contribution type deadline.
- Mint their own approved contribution exactly once.
- Transfer or list the minted `IPNft` through standard ERC-721 flows.
- Archive their minted token through `IPCollabCollection`, preserving the legal record while making it non-transferable.

The owner and verifiers cannot:

- Mint an approved contribution to themselves.
- Change a token URI after mint.
- Change token contributor provenance after mint.
- Take protocol fees.
- Create listings or settle marketplace trades inside this contract.
- Archive someone else's token.

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

Initializes Ownable/SRC5, stores contribution counters, and deploys a backing MIP-style `IPNft` contract using `ip_nft_class_hash`. The zero owner and zero class hash are rejected.

Production deployments should pass the reviewed `MIP-Collections-ERC721` `IPNft` class hash when ABI-compatible. The local `IPNft.cairo` exists to keep this package testable and to mirror the MIP NFT shape.

### Contribution Type Management

```cairo
fn register_contribution_type(
    type_id: felt252,
    min_quality_score: u8,
    submission_deadline: u64,
    max_supply: u256,
)
```

Owner-only. Defines a category of accepted work, such as visual art, music, or game items.

- `type_id` must be nonzero.
- duplicate type IDs are rejected.
- `max_supply` must be greater than zero.
- `max_supply` limits approved contributions for the type.

### Contribution Submission

```cairo
fn submit_contribution(
    token_uri: ByteArray,
    contribution_type: felt252,
) -> u256
```

Creates a pending contribution for the caller.

- the contribution type must exist.
- the deadline must not have passed.
- `token_uri` must start with `ipfs://` or `ar://`.
- the returned `contribution_id` is the permanent on-chain ID for the submission.

The metadata document should follow the OpenSea NFT metadata baseline:

```json
{
  "name": "Collaborative Work #1",
  "description": "Original contribution for a collaborative IP collection.",
  "image": "ipfs://...",
  "attributes": [
    { "trait_type": "License", "value": "CC BY-SA" },
    { "trait_type": "Medium", "value": "Illustration" }
  ]
}
```

### Review

```cairo
fn approve_contribution(contribution_id: u256, quality_score: u8)
fn reject_contribution(contribution_id: u256, quality_score: u8)
```

Owner or verifier only.

Approval requires the quality score to meet the contribution type's `min_quality_score` and requires the type's approved count to remain below `max_supply`. Rejection can record the actual score even when it is below the minimum.

### Minting

```cairo
fn mint_contribution(contribution_id: u256) -> u256
```

Contributor-only. Mints a real ERC-721 token to the contribution's original contributor.

- the contribution must exist.
- the contribution must be approved.
- the caller must be the original contributor.
- each contribution can be minted once.
- the minted token is created in the backing `IPNft`.
- `IPNft` stores the contributor as `original_creator` and stores the registration timestamp.
- `IPCollabCollection` stores the contribution-to-token link.

### Archiving

```cairo
fn archive_contribution_token(token_id: u256)
```

Token-owner-only. Calls the backing `IPNft.archive(token_id)` and marks the contribution as archived. Archived tokens preserve their URI, original creator, owner, and registration timestamp, but cannot transfer.

### Verifier Management

```cairo
fn add_verifier(verifier: ContractAddress)
fn remove_verifier(verifier: ContractAddress)
fn is_verifier(verifier: ContractAddress) -> bool
```

Owner-only management for the verifier set. The current owner is always treated as a verifier.

### Reads

```cairo
fn get_collection_issuer() -> ContractAddress
fn get_ip_nft() -> ContractAddress
fn get_uri_policy() -> felt252
fn get_collection_config() -> CollectionConfig
fn get_contribution(contribution_id: u256) -> Contribution
fn get_contribution_type(type_id: felt252) -> ContributionType
fn get_contributions_count() -> u256
fn get_contributor_contributions(contributor: ContractAddress) -> Array<u256>
fn get_token_contribution(token_id: u256) -> u256
fn get_token_contributor(token_id: u256) -> ContractAddress
fn get_token_registered_at(token_id: u256) -> u64
fn get_token_data(token_id: u256) -> TokenData
```

Token reads revert for nonexistent token IDs. Contribution reads reject nonexistent contribution IDs.

## Events

`IPCollabCollection` emits:

- OpenZeppelin Ownable events
- `BackingCollectionDeployed`
- `ContributionTypeRegistered`
- `ContributionSubmitted`
- `ContributionApproved`
- `ContributionRejected`
- `ContributionMinted`
- `ContributionTokenArchived`
- `VerifierAdded`
- `VerifierRemoved`

The backing `IPNft` emits the standard ERC-721 / ERC-721 Enumerable events. `ContributionMinted` links `contribution_id`, `token_id`, and `ip_nft`, making the indexer projection rebuildable from standard ERC-721 events plus service-specific events.

## Interface Detection

The contract registers:

```cairo
pub const IIP_COLLABORATIVE_COLLECTION_ID: felt252 =
    0x037f7abfe8ddddc21679794c218b559402e56bf1e6e6e2409c389038cd63f7cd;
```

The backing `IPNft` exposes ERC-721 and ERC-721 Enumerable interface support through OpenZeppelin SRC5 integration.

## Development

```bash
cd contracts/IP-Colab-Collections

SCARB_CACHE=/private/tmp/scarb-cache-ip-colab \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-colab \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
snforge test
```

## Verification

Current result:

```text
scarb build: passed
snforge test: 31 passed, 0 failed
```

## Dependencies

| Package | Version |
|---|---|
| `starknet` | `2.12.0` |
| `openzeppelin` | `v0.20.0` |
| `snforge_std` | `0.59.0` |
| `assert_macros` | `2.12.0` |

## Recommended Service Registry Entry

Suggested service ID:

```text
ip-collab-erc721
```

Suggested capabilities:

```text
mint, transfer, list
```

Notes:

- `mint` means "approved contributor can mint their accepted contribution."
- `list` is a marketplace capability through standard ERC-721 marketplace services, not an internal contract listing function.
- Enforcement should be declared as soft licensing unless future versions add explicit royalty, escrow, or split enforcement.
