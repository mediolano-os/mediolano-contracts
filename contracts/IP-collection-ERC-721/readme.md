# IP Collection ERC-721

Owner-minted ERC-721 collection contract for canonical IP issuance on Starknet.

This contract is permissionless to deploy, but each deployed collection has one mint authority: the collection owner. It is designed for creators, studios, labels, institutions, estates, galleries, and other issuers that need an official collection where only the collection authority can mint canonical works.

It is distinct from `IP-Programmable-ERC-721`, which is a shared permissionless mint collection.

## Status

Rebuilt on 2026-05-23.

The previous implementation was replaced rather than patched. This version:

- Uses OpenZeppelin ERC-721, ERC-721 Enumerable, SRC5, and Ownable components.
- Allows only the current owner to mint.
- Stores a full per-token `ipfs://` or `ar://` metadata URI.
- Records immutable issuer provenance fields at mint time.
- Registers a custom SRC5 interface ID for owner-minted IP collection detection.
- Uses `safe_mint` to avoid locking tokens in non-receiver contracts.
- Removes upgradeability, custom transfer helpers, duplicate owner ledgers, Alexandria storage lists, and unused shadow storage.
- Uses standard ERC-721 transfer and approval behavior.
- Contains a focused test suite covering 35 cases.

## Design Model

| Property | Design |
|---|---|
| Deployment | Permissionless. Anyone can deploy their own collection. |
| Minting | Owner-only. The collection owner is the mint authority. |
| Ownership transfer | Supported through OpenZeppelin Ownable. New owners can mint future tokens. |
| Upgradeability | None. No `UpgradeableComponent`. |
| Metadata | Full per-token `ByteArray` URI, stored once at mint. |
| Accepted URI schemes | `ipfs://` and `ar://`. |
| Provenance | Collection issuer at mint plus block timestamp. |
| Transfers | Standard ERC-721 ABI. No custom transfer path. |
| Fees | None. No platform or protocol fee logic. |

## Service Identity

Recommended registry identity:

```text
owner-minted-erc721
```

This identifies a permissionless-to-deploy ERC-721 collection where the collection owner is the only mint authority. It should be kept distinct from:

- `ip-erc721`: shared permissionless mint collection.
- `mip-erc721`: per-creator/factory collection model, if the registry keeps that name for the broader MIP service.

## Public Interface

```cairo
fn mint_item(
    recipient: ContractAddress,
    token_uri: ByteArray,
) -> u256
```

Owner-only. Mints the next sequential token ID to `recipient` with a full content-addressed metadata URI. Reverts if the caller is not the owner, the recipient is zero, the URI does not start with `ipfs://` or `ar://`, or the recipient contract cannot receive ERC-721 tokens.

```cairo
fn get_collection_issuer() -> ContractAddress
```

Returns the initial collection issuer recorded at deployment. This value does not change if ownership is transferred.

```cairo
fn get_token_issuer(token_id: u256) -> ContractAddress
```

Returns the collection issuer that minted the token. This is immutable after mint.

```cairo
fn get_token_registered_at(token_id: u256) -> u64
```

Returns the block timestamp recorded when the token was minted.

```cairo
fn get_token_data(token_id: u256) -> TokenData
```

Returns the token ID, current owner, metadata URI, issuer, and registration timestamp in one call.

## TokenData

```cairo
pub struct TokenData {
    pub token_id: u256,
    pub owner: ContractAddress,
    pub metadata_uri: ByteArray,
    pub issuer: ContractAddress,
    pub registered_at: u64,
}
```

## Events

```cairo
pub struct IPMinted {
    #[key]
    pub token_id: u256,
    #[key]
    pub recipient: ContractAddress,
    pub uri: ByteArray,
    pub issuer: ContractAddress,
    pub registered_at: u64,
}
```

`issuer` is the collection owner/current mint authority at mint time.

## Interface Detection

The contract registers a custom SRC5 interface ID:

```cairo
pub const IIP_COLLECTION_ID: felt252 =
    0x0169025717e7d54a71b5dcbf608cd0a71b562570902dad8b7d4a7e80fe15eeb0;
```

Indexers, SDKs, and agents can use `supports_interface(IIP_COLLECTION_ID)` to detect this owner-minted IP collection surface.

## Metadata and Licensing

The contract stores only the metadata URI. The metadata document should follow the Medialane/Mediolano architecture:

- Use OpenSea-compatible ERC-721 metadata.
- Include `name`, `description`, `image`, and `attributes`.
- Encode license terms as plain attributes.
- Use immutable content-addressed storage such as IPFS or Arweave.

The contract does not enforce license terms on-chain. Licensing remains metadata-first and soft-enforced by apps, partners, and services unless a separate service explicitly opts into enforcement.

Example:

```json
{
  "name": "Composition No. 7",
  "description": "Canonical registration of the work.",
  "image": "ipfs://bafy.../cover.png",
  "animation_url": "ipfs://bafy.../master.wav",
  "attributes": [
    { "trait_type": "License", "value": "CC BY-SA" },
    { "trait_type": "Commercial Use", "value": "Allowed" },
    { "trait_type": "Derivatives", "value": "Share-alike" },
    { "trait_type": "Attribution", "value": "Required" },
    { "trait_type": "Territory", "value": "Worldwide" },
    { "trait_type": "AI Policy", "value": "Training allowed with attribution" },
    { "trait_type": "Royalty", "value": "None" }
  ],
  "medialane": {
    "service": "owner-minted-erc721",
    "schemaVersion": 1
  }
}
```

## Package Layout

| Path | Purpose |
|---|---|
| `src/IPCollection.cairo` | Main owner-minted ERC-721 contract |
| `src/interfaces/IIPCollection.cairo` | Public IP collection interface and SRC5 ID |
| `src/types.cairo` | `TokenData` and URI-prefix helper |
| `src/mock_contracts/` | Test receiver and mock account contracts |
| `src/tests/IPCollectionTest.cairo` | Contract tests |
| `Scarb.toml` | Cairo package manifest |
| `Scarb.lock` | Locked dependency versions |

## Development

```bash
cd contracts/IP-collection-ERC-721

SCARB_CACHE=/private/tmp/scarb-cache-ip-collection-erc721 \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-collection-erc721 \
  PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" \
  snforge test
```

## Verification

Latest local verification:

- `scarb fmt`: passed
- `scarb build`: passed
- `snforge test`: 35 passed, 0 failed
