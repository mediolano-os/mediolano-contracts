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
  │                           └── token_registered_at: Map<u256, u64>
  ├── mint(collection_id, recipient, token_uri) → token_id
  ├── batch_mint(collection_id, recipients[], token_uris[]) → token_ids[]
  ├── transfer_collection_ownership(collection_id, new_owner)
  ├── archive(token) / batch_archive(tokens[])
  └── transfer_token(from, to, token) / batch_transfer(from, to, tokens[])
```

## Token Identifier Format

Tokens are identified by a `ByteArray` string in the format `"collection_id:token_id"`, e.g. `"3:17"`. This is parsed by `TokenTrait::from_bytes` which validates that exactly one `:` separator is present and both segments are valid decimal numbers.

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
    total_transfers: u256,       // transfers routed through IPCollection only
    last_mint_time: u64,
    last_archive_time: u64,
    last_transfer_time: u64,     // last IPCollection-routed transfer
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
```

### Token operations
```cairo
fn mint(collection_id, recipient, token_uri) -> u256
fn batch_mint(collection_id, recipients[], token_uris[]) -> Span<u256>
fn archive(token: ByteArray)              // replaces burn — record preserved
fn batch_archive(tokens: Array<ByteArray>)
fn transfer_token(from, to, token)
fn batch_transfer(from, to, tokens[])
fn get_token(token: ByteArray) -> TokenData
fn is_valid_token(token: ByteArray) -> bool
fn is_transferable_token(token: ByteArray) -> bool
fn list_user_tokens_per_collection(collection_id, user) -> Span<u256>
```

There are no admin or upgrade entrypoints.

## Minting And Provenance

Only the collection owner can mint. The `recipient` receives the ERC-721 token, while the caller is recorded as the immutable `original_creator` / author for the token. This keeps custody and authorship separate: tokens can be minted directly to another wallet without rewriting the legal provenance record.

Each mint writes the token URI, original creator, and registration timestamp exactly once. Later transfers, protocol-routed transfers, and collection ownership transfers do not modify those fields.

## Events

| Event | Key fields |
|---|---|
| `CollectionCreated` | collection_id, owner, name, symbol, base_uri |
| `CollectionOwnershipTransferred` | collection_id, previous_owner, new_owner, timestamp |
| `TokenMinted` | collection_id, token_id, owner, metadata_uri |
| `TokenMintedBatch` | collection_id, token_ids, owners, operator, timestamp |
| `TokenArchived` | collection_id, token_id, operator, timestamp |
| `TokenArchivedBatch` | tokens, operator, timestamp |
| `TokenTransferred` | collection_id, token_id, from, to, operator, timestamp |
| `TokenTransferredBatch` | from, to, tokens, operator, timestamp |

## Archive vs Burn

This contract uses **archive** instead of ERC-721 burn. Archiving marks a token as inactive while preserving the on-chain provenance record — the original creator address and registration timestamp in the `IPNft` contract are never deleted. This satisfies the Berne Convention requirement that IP authorship records be permanent.

## Collection Ownership

Collection ownership can be transferred atomically by the current collection owner. This moves future mint authority and owner collection listings to the new wallet in one transaction. It does not modify any existing token legal record: `metadata_uri`, `original_creator`, and `registered_at` remain immutable.

## Transfer Flow

Active tokens support standard ERC-721 direct transfers on `IPNft`, preserving marketplace and wallet compatibility. Archived tokens cannot be transferred.

The `IPCollection.transfer_token` and `batch_transfer` methods are optional protocol-aware transfer paths. They update collection transfer stats and emit protocol transfer events. Before using them, the token owner must approve `IPCollection` either with per-token approval or `set_approval_for_all`. The caller must be the token owner, token-approved address, or an approved operator.

Indexers that need complete transfer history should subscribe to both native `IPNft` ERC-721 `Transfer` events and `IPCollection` protocol transfer events. `CollectionStats.total_transfers` counts only transfers routed through `IPCollection`.

## Metadata URI Semantics

Each minted token stores an immutable per-token `metadata_uri` and `token_uri()` / `tokenURI()` return that value directly. Token metadata strings are protocol-neutral: they must be non-empty and no longer than 2048 bytes, but are not restricted to any URI scheme. The collection `base_uri` is informational collection metadata; it is not concatenated with token IDs.

Frontends, SDKs, and indexers should validate and classify known URI formats off-chain, fetch and preview metadata before minting, and warn users when metadata is unreachable or unsupported.

## Deployments

### Starknet Mainnet

| Component | Class hash | Address |
|---|---|---|
| `IPNft` immutable ERC-721 class | `0x02d50b7e6d1a14f17a8fdc2df24d6e493bae6fae579656d81959b8c92de4b13f` | Collection instances are deployed by `IPCollection` |
| `IPCollection` immutable registry/factory class | `0x00203f0e03a472cb6e058327ca22147c75e574cc2876f4981e99bcbcbe716a29` | `0x07c2207d200a1dce1cc82a117d8ba91dabfe3d1cc5072d9e4cdd9654fbb0ff10` |

| Action | Transaction | Actual fee |
|---|---|---|
| Declare `IPNft` | `0x0602f832d8bf6590780bb592c18e98aae9a0df9ad86245f94a92e1467ddbe2b8` | `24.308705 STRK` |
| Declare `IPCollection` | `0x04c89525842cf5e9f95e23942017bbd7caac40ab1f193a4603a52799ddf59194` | `29.224179 STRK` |
| Deploy `IPCollection` | `0x0543d8fe9e00c8981f6dd7d4148ad94cba8b9e6dfed69f1d4583c6034f71435f` | `0.036002 STRK` |

Deployment verification:

- The deployed registry class hash is `0x00203f0e03a472cb6e058327ca22147c75e574cc2876f4981e99bcbcbe716a29`.
- The registry constructor received `0x02d50b7e6d1a14f17a8fdc2df24d6e493bae6fae579656d81959b8c92de4b13f` as its immutable `IPNft` class hash.
- `get_collection_count()` returns `0` immediately after deployment.

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
