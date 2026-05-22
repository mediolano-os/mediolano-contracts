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
IPCollectionFactory
  └── deploy_collection(name, symbol)
        └── deploy_syscall → IPCollection (new standalone contract)
                               ├── ERC1155Component   (OZ v0.20.0)
                               ├── ERC2981Component   (OZ v0.20.0)
                               ├── OwnableComponent
                               └── SRC5Component
```

The factory uses a Poseidon-hashed salt `(caller, nonce)` to guarantee each deployed collection has a unique address. `ByteArray::serialize` takes a snapshot so no defensive clones are needed before or after calldata construction.

## Deployments

| Network | Contract | Address |
|---|---|---|
| Mainnet | `IPCollectionFactory` | `0x0459a9a3c04be5d884a038744f977dff019897264d4a281f9e0f87af417b3bec` |
| Mainnet | `IPCollection` (class) | `0x02da5e81be7a1ca493b9441522c450f8ff4c54b14ec16a0c2349f5e6e6fdc5d7` |

## IPCollection

### Storage

| Field | Type | Description |
|---|---|---|
| `collection_name` | `ByteArray` | Human-readable name (display only) |
| `collection_symbol` | `ByteArray` | Ticker symbol (display only) |
| `collection_creator` | `ContractAddress` | Address that deployed this collection |
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

Current implementation version: `0.2.0`.

### Minting

Only the collection owner can mint. On the **first mint** of a token ID:
- The URI is stored permanently and must be non-empty and no longer than 2048 bytes.
- The caller (collection owner) is recorded as the original IP creator.
- The block timestamp is recorded as the registration date.

On **subsequent mints** of the same token ID the URI argument is ignored and all provenance fields remain unchanged. Balances accumulate normally.

The `_mint_single` internal captures `get_block_timestamp()` once per call and uses local variables to populate the `IPMinted` event on first mint — avoiding redundant storage reads.

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
fn mint_item(to, token_id, value, token_uri)
fn batch_mint_item(to, token_ids, values, token_uris)
fn version() -> ByteArray
fn get_collection_creator() -> ContractAddress
fn get_token_creator(token_id) -> ContractAddress
fn get_token_registered_at(token_id) -> u64
fn get_token_data(token_id) -> TokenData
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
fn update_collection_class_hash(new_class_hash)   // owner only
fn deploy_collection(name, symbol, base_uri) -> ContractAddress
```

`deploy_collection` is callable by **anyone** — the caller becomes the owner of the deployed collection. The factory owner can update the class hash for future deployments without affecting existing ones.
Factory and collection constructors reject zero owner/class-hash inputs, so deployed collections start from explicit, valid authority and implementation values.
`update_collection_class_hash` rejects the zero class hash and emits `CollectionClassHashUpdated`.

### Events

```
CollectionDeployed {
    collection_address: ContractAddress  [indexed]
    owner: ContractAddress               [indexed]
    name: ByteArray
    symbol: ByteArray
    base_uri: ByteArray
}

CollectionClassHashUpdated {
    previous_class_hash: ClassHash
    new_class_hash: ClassHash
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

# Run all 71 tests
scarb test

# Run a specific test
snforge test test_mint_item_http_uri_allowed
```

## Dependencies

| Package | Version |
|---|---|
| `starknet` | `2.12.0` |
| `openzeppelin` | `v0.20.0` |
| `snforge_std` | `0.59.0` |
