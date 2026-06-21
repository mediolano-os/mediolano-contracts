# MIP-Collections-ERC721

Immutable registry and factory contract for ERC-721 IP collections on Starknet. Each collection deploys its own standalone `IPNft` contract, keeping provenance records permanently immutable.

## Overview

`MIP-Collections-ERC721` is the core collection management contract for the Mediolano IP protocol. It operates as both a **registry** (tracking all collections and their metadata) and a **factory** (deploying a dedicated `IPNft` ERC-721 contract per collection via `deploy_syscall`).

The two-contract architecture is intentional:

| Contract | Upgradeable | Role |
|---|---|---|
| `IPCollection` | No | Registry, factory, index of all collections and stats |
| `IPNft` | No | Standalone ERC-721 — holds the immutable IP provenance record |

Both contracts are deployed once and never upgraded. There is no owner-only upgrade path, no mutable NFT class hash, and no collection pause switch.

Security invariants are deliberately small: constructor inputs are validated, minting is collection-owner gated, token metadata pointers are immutable and capped at 2048 bytes, and creator/timestamp provenance is written once and never rewritten.

## Architecture

```
IPCollection (immutable registry)
  ├── create_collection(name, symbol, base_uri)
  │     └── deploy_syscall → IPNft (standalone ERC-721, immutable)
  │                           ├── token_creators: Map<u256, ContractAddress>
  │                           ├── token_registered_at: Map<u256, u64>
  │                           └── EIP-2981 royalty per token (receiver = creator, immutable)
  ├── mint(collection_id, recipient, token_uri, royalty_bps) → token_id
  ├── batch_mint(collection_id, recipients[], token_uris[], royalty_bps[]) → token_ids[]
  ├── transfer_collection_ownership(collection_id, new_owner)
  ├── archive(collection_id, token_id) / batch_archive(collection_ids[], token_ids[])
  └── transfer_token(to, collection_id, token_id) / batch_transfer(from, to, collection_ids[], token_ids[])
```

## Token Identifier Format

Tokens are addressed by two explicit `u256` arguments — `collection_id` and `token_id` — on every
token operation (`archive`, `transfer_token`, `get_token`, `is_valid_token`,
`is_transferable_token`) and as parallel `collection_ids` / `token_ids` arrays on the batch calls.
There is no stringified `"collection_id:token_id"` form (the prior `ByteArray` parser was removed in
v0.4.0): integrators pass the two numbers directly — cheaper, and no parsing/validation surface.

## Storage

| Field | Type | Description |
|---|---|---|
| `collections` | `Map<u256, Collection>` | Collection metadata by ID |
| `collection_count` | `u256` | Total collections ever created (IDs start at 1) |
| `collection_stats` | `Map<u256, CollectionStats>` | Mint/archive counters and protocol-path transfer counters per collection |
| `ip_nft_class_hash` | `ClassHash` | Class hash used to deploy new `IPNft` contracts |
| `user_collections` | `Map<(ContractAddress, u256), u256>` | Enumerable list of collection IDs per owner |
| `user_collection_index` | `Map<ContractAddress, u256>` | Count of collections per owner |
| `collection_owner_index` | `Map<u256, u256>` | Position of each collection in its owner's enumerable list |

## Key Types

```cairo
struct Collection {
    name: ByteArray,
    symbol: ByteArray,
    base_uri: ByteArray,
    owner: ContractAddress,
    ip_nft: ContractAddress,   // address of the deployed IPNft contract
}

struct CollectionStats {
    total_minted: u256,
    total_archived: u256,
    protocol_routed_transfers: u256,  // transfers routed through IPCollection only
    last_mint_time: u64,
    last_archive_time: u64,
    last_transfer_time: u64,          // last IPCollection-routed transfer
}

struct TokenData {
    collection_id: u256,
    token_id: u256,
    owner: ContractAddress,
    metadata_uri: ByteArray,
    original_creator: ContractAddress,  // immutable creator/author — Berne Convention record
    registered_at: u64,                 // immutable — proof of creation date
}
```

## Interface

### Collection management
```cairo
fn create_collection(name, symbol, base_uri) -> u256
fn transfer_collection_ownership(collection_id, new_owner)
fn get_collection(collection_id) -> Collection
fn get_collection_count() -> u256
fn get_collection_stats(collection_id) -> CollectionStats
fn is_valid_collection(collection_id) -> bool
fn is_collection_owner(collection_id, owner) -> bool
fn list_user_collections(user) -> Span<u256>
fn version() -> ByteArray            // immutable implementation version, e.g. "0.4.0"
```

### Token operations
```cairo
fn mint(collection_id, recipient, token_uri, royalty_bps: u128) -> u256
fn batch_mint(collection_id, recipients[], token_uris[], royalty_bps: Array<u128>) -> Span<u256>
fn archive(collection_id, token_id)              // replaces burn — record preserved
fn batch_archive(collection_ids[], token_ids[])
fn transfer_token(to, collection_id, token_id)
fn batch_transfer(from, to, collection_ids[], token_ids[])
fn get_token(collection_id, token_id) -> TokenData
fn is_valid_token(collection_id, token_id) -> bool
fn is_transferable_token(collection_id, token_id) -> bool
fn list_user_tokens_per_collection(collection_id, user) -> Span<u256>
```

`royalty_bps` (≤ 10_000) sets the token's immutable EIP-2981 royalty with the creator as receiver.
The deployed `IPNft` exposes the standard read surface — `royalty_info`, `token_royalty`,
`default_royalty`, `supports_interface(IERC2981_ID)`, and `version()`.

There are no admin or upgrade entrypoints, and no royalty setter — royalty is fixed at mint.

## Minting And Provenance

Only the collection owner can mint. The `recipient` receives the ERC-721 token, while the caller is recorded as the immutable `original_creator` / author for the token. This keeps custody and authorship separate: tokens can be minted directly to another wallet without rewriting the legal provenance record.

Each mint writes the token URI, original creator, registration timestamp, and EIP-2981 royalty exactly once. The royalty receiver is the immutable `original_creator` (never the mutable collection owner), so secondary-sale royalties can never be redirected by an ownership transfer. Later transfers, protocol-routed transfers, and collection ownership transfers do not modify any of those fields.

## Events

| Event | Key fields |
|---|---|
| `CollectionCreated` | collection_id, owner, name, symbol, base_uri |
| `CollectionOwnershipTransferred` | collection_id, previous_owner, new_owner, timestamp |
| `TokenMinted` | collection_id, token_id, owner, metadata_uri, royalty_bps |
| `TokenMintedBatch` | collection_id, token_ids, owners, metadata_uris, operator, timestamp |
| `TokenArchived` | collection_id, token_id, operator, timestamp |
| `TokenArchivedBatch` | collection_ids, token_ids, operator, timestamp |
| `TokenTransferred` | collection_id, token_id, from, to, operator, timestamp |
| `TokenTransferredBatch` | from, to, collection_ids, token_ids, operator, timestamp |

## Archive vs Burn

This contract uses **archive** instead of ERC-721 burn. Archiving marks a token as inactive while preserving the on-chain provenance record — the original creator address and registration timestamp in the `IPNft` contract are never deleted. This satisfies the Berne Convention requirement that IP authorship records be permanent.

## Collection Ownership

Collection ownership can be transferred atomically by the current collection owner. This moves future mint authority and owner collection listings to the new wallet in one transaction. It does not modify any existing token legal record: `metadata_uri`, `original_creator`, and `registered_at` remain immutable.

## Transfer Flow

Active tokens support standard ERC-721 direct transfers on `IPNft`, preserving marketplace and wallet compatibility. Archived tokens cannot be transferred.

The `IPCollection.transfer_token` and `batch_transfer` methods are optional protocol-aware transfer paths. They update collection transfer stats and emit protocol transfer events. Before using them, the token owner must approve `IPCollection` either with per-token approval or `set_approval_for_all`. The caller must be the token owner, token-approved address, or an approved operator.

Indexers that need complete transfer history should subscribe to both native `IPNft` ERC-721 `Transfer` events and `IPCollection` protocol transfer events. `CollectionStats.protocol_routed_transfers` counts only transfers routed through `IPCollection`.

## Metadata URI Semantics

Each minted token stores an immutable per-token `metadata_uri` and `token_uri()` / `tokenURI()` return that value directly. Token metadata strings are protocol-neutral: they must be non-empty and no longer than 2048 bytes, but are not restricted to any URI scheme. The collection `base_uri` is informational collection metadata; it is not concatenated with token IDs.

Frontends, SDKs, and indexers should validate and classify known URI formats off-chain, fetch and preview metadata before minting, and warn users when metadata is unreachable or unsupported.

## Deployments

Chain is a first-class dimension of the protocol; today's deployment lives on **Starknet**.

### Starknet — v0.4.0

| Component | Class hash | Address |
|---|---|---|
| `IPNft` immutable ERC-721 class | `0x040551f0d009a6d665ddff980a375dfccc71a8928c8bfcc9ab56244bc4464fab` | Collection instances are deployed by `IPCollection` |
| `IPCollection` immutable registry/factory class | `0x063d4ac4ae317fd155216bf1b8a4d3a63172ff72965b9ac48dd5add0c2d32b70` | `0x0558c9b6ea4d403df6d765fb77be55702c572f0a811f037c6c4209fe1e5aeef2` |

| Action | Transaction |
|---|---|
| Declare `IPNft` | `0x0312d3292713a7d7208de7d0200c5ec456930d0d53a6e6bc97fb1d47c3dba4ba` |
| Declare `IPCollection` | `0x0569ed2167b826e38c27eb2d5b7cd7a823477a1d14a2ec1c7e21bfe7698c200f` |
| Deploy `IPCollection` | `0x0383633d4ee0140ac1acebc2a28a90aeeb4734f4cedc5b3ff0291411ec74be78` |

v0.4.0 adds per-token EIP-2981 royalties (receiver = creator, immutable), `version()` views,
`(collection_id, token_id)` token arguments, and the `protocol_routed_transfers` stat.

Deployment verification:

- The deployed registry class hash is `0x063d4ac4ae317fd155216bf1b8a4d3a63172ff72965b9ac48dd5add0c2d32b70`.
- The registry constructor received `0x040551f0d009a6d665ddff980a375dfccc71a8928c8bfcc9ab56244bc4464fab` as its immutable `IPNft` class hash.
- `get_collection_count()` returns `0` and `version()` returns `"0.4.0"` immediately after deployment.

Mainnet declaration/deployment flow:

```bash
cd contracts/MIP-Collections-ERC721

# Build Sierra/CASM artifacts
scarb build

# Declare IPNft first
sncast --profile medialane-mainnet --wait declare --contract-name IPNft

# Declare IPCollection
sncast --profile medialane-mainnet --wait declare --contract-name IPCollection

# Deploy IPCollection with the declared IPNft class hash as constructor calldata
sncast --profile medialane-mainnet --wait deploy \
  --class-hash <IPCollection_CLASS_HASH> \
  --constructor-calldata <IPNFT_CLASS_HASH>
```

## Development

```bash
cd contracts/MIP-Collections-ERC721

# Build
scarb build

# Run all tests
scarb test

# Current suite size
snforge test  # 67 tests

# Run a specific test
snforge test test_create_collection
```

## Dependencies

| Package | Version |
|---|---|
| `starknet` | `2.12.0` |
| `openzeppelin` | `v0.20.0` |
| `snforge_std` | `0.59.0` |
