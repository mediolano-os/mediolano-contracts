# IP-Programmable-ERC1155-Collections

ERC-1155 multi-token IP collections with immutable provenance records, on-chain royalties (ERC-2981), and a permissionless factory — deployed on Starknet.

## Overview

This contract system lets anyone deploy their own ERC-1155 collection for intellectual property assets. Each collection is a standalone contract where every token type carries an immutable record of its original creator and registration timestamp, satisfying the authorship standard required under the Berne Convention.

Two contracts make up the system:

| Contract | Role |
|---|---|
| `IPCollectionFactory` | Permissionless factory — anyone calls it to deploy a new `IPCollection` |
| `IPCollection` | Standalone ERC-1155 collection — owner controls minting, provenance and royalties |

Security invariants are deliberately small: constructor inputs are validated, minting is collection-owner gated, token metadata pointers are immutable and capped at 2048 bytes, and creator/timestamp provenance is written once and never rewritten.

## Architecture

```
IPCollectionFactory  (ownerless, immutable)
  └── deploy_collection(name, symbol, base_uri)
        └── deploy_syscall → IPCollection (new standalone contract)
                               ├── ERC1155Component   (OZ v0.20.0)
                               ├── ERC2981Component   (OZ v0.20.0)
                               ├── OwnableComponent
                               └── SRC5Component
```

The factory uses a Poseidon-hashed salt `(caller, nonce)` to guarantee each deployed collection has a unique address. `ByteArray::serialize` takes a snapshot so no defensive clones are needed before or after calldata construction.

## Deployments

| Network | Contract | Address / class hash |
|---|---|---|
| Mainnet | `IPCollectionFactory` v0.3.0 | `0x0083543c3ee15040a419fc539fa6889f5b956e7d071bcfa97842cb0ae42ad6cc` |
| Mainnet | `IPCollectionFactory` v0.3.0 (class) | `0x0331a69da8655a882ba1fbcb55188b8fa09116521db901bbbaafc9fead0689f8` |
| Mainnet | `IPCollection` v0.3.0 (class) | `0x04e110b59af240ae6c7742999964c4eae13fb2ed935c47fe97653ec017ebea34` |

## IPCollection

### Storage

| Field | Type | Description |
|---|---|---|
| `collection_name` | `ByteArray` | Human-readable name (display only) |
| `collection_symbol` | `ByteArray` | Ticker symbol (display only) |
| `collection_base_uri` | `ByteArray` | Collection-level metadata URI; fallback for `uri(token_id)` on unminted ids |
| `collection_creator` | `ContractAddress` | Address that deployed this collection |
| `next_token_id` | `u256` | Next edition id to assign — initialized to 1, incremented per new edition |
| `token_uris` | `Map<u256, ByteArray>` | Per-token URI, written once at first mint |
| `token_creators` | `Map<u256, ContractAddress>` | Original minter per token type — immutable |
| `token_registered_at` | `Map<u256, u64>` | Block timestamp at first mint — immutable |
| `ERC2981_default_royalty_info` | `RoyaltyInfo` | Collection-wide royalty (receiver + fraction) |
| `ERC2981_token_royalty_info` | `Map<u256, RoyaltyInfo>` | Per-token royalty overrides |

### Version

Both `IPCollection` and `IPCollectionFactory` expose:

```cairo
fn version() -> ByteArray
```

Current implementation version: `0.3.0`.

### Minting

Only the collection owner can mint. Edition ids are assigned **on-chain**, sequentially
from 1 — callers never supply a token id when creating a new edition.

- `mint_edition(to, value, token_uri) -> u256` mints a **new** edition and returns its
  assigned id. The URI is stored permanently (non-empty, ≤ 2048 bytes), the caller is
  recorded as the original IP creator, and the block timestamp as the registration date.
- `batch_mint_edition(to, values, token_uris) -> Span<u256>` creates N new editions in
  one call; ids are assigned sequentially.
- `add_supply(to, token_id, value)` mints additional copies of an **existing** edition.
  It reverts if the edition has never been minted; URI and provenance are unchanged.

The assigned id is also emitted in the `IPMinted` event (indexed key), so integrators can
read it from the transaction receipt.

### Royalties (ERC-2981)

Every collection advertises ERC-2981 in its SRC5 interface from deploy. The default royalty is set to **0%** at construction — the owner activates it post-deploy.

```
Fee denominator: 10,000
  500 → 5%
  800 → 8%
 1000 → 10%
```

| Function | Access | Description |
|---|---|---|
| `royalty_info(token_id, sale_price)` | Public | Returns `(receiver, amount)` — called by marketplaces |
| `default_royalty()` | Public | Returns `(receiver, numerator, denominator)` |
| `token_royalty(token_id)` | Public | Per-token royalty or default if unset |
| `set_default_royalty(receiver, fee_numerator)` | Owner | Set collection-wide royalty |
| `delete_default_royalty()` | Owner | Reset to 0% |
| `set_token_royalty(token_id, receiver, fee_numerator)` | Owner | Override for a specific token type |
| `reset_token_royalty(token_id)` | Owner | Remove per-token override, falls back to default |

### Interface

```cairo
// IIPCollection
fn name() -> ByteArray
fn symbol() -> ByteArray
fn base_uri() -> ByteArray
fn version() -> ByteArray
fn mint_edition(to, value, token_uri) -> u256
fn batch_mint_edition(to, values, token_uris) -> Span<u256>
fn add_supply(to, token_id, value)
fn get_collection_creator() -> ContractAddress
fn get_token_creator(token_id) -> ContractAddress
fn get_token_registered_at(token_id) -> u64
fn get_token_data(token_id) -> TokenData
fn total_editions() -> u256
fn token_exists(token_id) -> bool
```

`get_token_creator`, `get_token_registered_at`, and `get_token_data` revert if the token ID has never been minted.

### Events

```
IPMinted {
    token_id: u256           [indexed]
    recipient: ContractAddress  [indexed]
    value: u256
    uri: ByteArray
    creator: ContractAddress
    registered_at: u64
}
```

## IPCollectionFactory

### Interface

```cairo
fn collection_class_hash() -> ClassHash
fn version() -> ByteArray
fn deploy_collection(name, symbol, base_uri) -> ContractAddress
```

`deploy_collection` is callable by **anyone** — the caller becomes the owner of the deployed collection. The factory is **ownerless and immutable**: the collection class hash is fixed at deploy time and can never change. Protocol evolution means deploying a new factory, never mutating this one.
Factory and collection constructors reject zero owner/class-hash inputs, so deployed collections start from explicit, valid authority and implementation values.

### Events

```
CollectionDeployed {
    collection_address: ContractAddress  [indexed]
    owner: ContractAddress               [indexed]
    name: ByteArray
    symbol: ByteArray
    base_uri: ByteArray
}
```

## TokenData Struct

```cairo
struct TokenData {
    token_id: u256,
    metadata_uri: ByteArray,
    original_creator: ContractAddress,  // immutable — Berne Convention record
    registered_at: u64,                 // immutable — proof of creation date
}
```

## URI Policy

Token URIs are immutable once a token type is first minted. The contract intentionally validates only that the URI is non-empty and no longer than 2048 bytes, so future content-addressing systems and metadata protocols can be used without redeploying the collection implementation.

Frontends, SDKs, and indexers should validate and classify known URI formats off-chain, fetch and preview metadata before minting, and warn users when metadata is unreachable or unsupported.

## Design Decisions

- **Sequential on-chain edition ids** — `next_token_id` starts at 1 and the contract assigns every new edition's id atomically. This removes the caller-supplied-id scheme of v0.2.0 (and the client-side id-collision risk that came with it). `total_editions()` is always the highest assigned id.
- **Ownerless, immutable factory** — no admin, no class-hash setter. A new protocol version is a new factory deployment; existing collections are never affected.
- **No upgradeability on `IPCollection`** — collections are permanent, immutable contracts. Provenance records can never be altered.
- **Protocol-neutral token URIs** — the contract requires a non-empty metadata pointer capped at 2048 bytes but does not hard-code storage schemes such as IPFS or Arweave.
- **ERC-2981 defaults to 0%** — no royalty is taken unless the owner explicitly sets one. Any ERC-2981-aware marketplace will read this automatically without platform-specific configuration.
- **Caller is the creator** — the collection owner who mints the first supply of a token type is recorded as the immutable IP creator. The `to` address only receives the minted balance.
- **`ERC1155Impl` + `ERC1155CamelImpl`, not `ERC1155MixinImpl`** — the Mixin's `uri()` returns a base URI. Embedding the two impls separately allows a custom `IERC1155MetadataURI` implementation that returns per-token URIs from storage.

## Development

```bash
cd contracts/IP-Programmable-ERC1155-Collections

# Build
scarb build

# Run all tests (69 across IPCollectionTest + IPCollectionFactoryTest)
scarb test

# Run a specific test
snforge test test_deploy_collection_caller_is_owner
```

## Dependencies

| Package | Version |
|---|---|
| `starknet` | `2.12.0` |
| `openzeppelin` | `v0.20.0` |
| `snforge_std` | `0.59.0` |
