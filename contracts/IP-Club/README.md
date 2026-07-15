# IP Club

`IP-Club` is a Starknet ERC-721 membership protocol. `IPClubFactory` deploys
one `IPClubCollection` per creator; anyone can mint a membership card from a
deployed collection, optionally paying an ERC-20 entry fee straight to the
collection owner.

Membership cards are ordinary, indexable, transferable ERC-721 tokens — sales
happen on any marketplace that trades ERC-721.

## Design

The contracts follow the Mediolano principles:

- **Ownerless factory, owned collections.** Anyone deploys their own
  `IPClubCollection` via the factory; the factory itself has no admin, no
  upgrade path, and takes no fee. Only the collection's owner (the deployer)
  can gate new joins (`set_open`) — the same access model as every other
  per-creator NFT contract in the catalog.
- **On-chain collection identity.** `deploy_club(name, symbol, base_uri, …)`
  embeds the collection-level metadata URI in the deploy transaction;
  `name()`, `symbol()`, and `base_uri()` are readable on-chain. Per-token
  metadata is standard OZ ERC-721: `token_uri(token_id) = base_uri + token_id`.
- **Public, fee-gated mint.** Anyone may call `mint`; if the club has an entry
  fee, it settles payer → owner in the same call. There is no owner-only mint
  gate — `is_open` controls whether minting is possible at all, not who may
  call it.
- **Checks-effects-interactions.** Token id assignment and the supply-cap
  check are final before the fee transfer and the mint call; a reentrant
  payment token runs under its own caller context and the transaction reverts
  atomically (tested with a single-reentry mock).
- **Royalty discovery.** The ERC-2981 interface ID is registered via SRC5 and
  `royalty_info` is exposed in snake_case alongside the camelCase
  `royaltyInfo` alias. The receiver is the collection owner.
- **Lean records.** `total_minted` derives from the sequential token-id
  counter; storage holds only what the contract enforces (`max_supply`,
  `entry_fee`, `payment_token`, `royalty_bps`, `is_open`).

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-club` |
| `asset_standard` | ERC721 |
| `asset_role` | Club membership card |
| `transferability` | Transferable |
| `access_semantics` | Current ownership of the membership token id |
| `marketplace_visibility` | Display and list as ERC721 membership cards |
| `metadata_uri_policy` | `ipfs://` or `ar://`, must end with `/` |
| `src5_interface_id` | `IIP_CLUB_COLLECTION_ID` + `IERC2981_ID` (collection); `IIP_CLUB_FACTORY_ID` (factory) |

## Features

- One deployed `IPClubCollection` per creator, via the ownerless
  `IPClubFactory` — the same shape as every other per-creator NFT contract, so
  memberships are tradeable and indexable like any other asset.
- Public mint, gated only by `is_open` and an optional per-club `max_supply`.
- Optional ERC-20 entry fee, paid directly payer → collection owner.
- `set_open(bool)` — owner-only, reversible pause on new mints; never affects
  existing members.
- Content-addressed collection metadata (`ipfs://` or `ar://`, must end with
  `/`); standard OZ `token_uri`/`tokenURI` per token.
- ERC-2981-style royalties per card, paid to the collection owner.
- SRC5 service interface detection.

## Interface

`IPClubFactory`:

```cairo
fn collection_class_hash() -> ClassHash;
fn version() -> ByteArray;
fn deploy_club(
    name: ByteArray,
    symbol: ByteArray,
    base_uri: ByteArray,
    max_supply: u256,
    entry_fee: u256,
    payment_token: Option<ContractAddress>,
    royalty_bps: u256,
) -> ContractAddress;
```

`IPClubCollection` (one per creator, deployed by the factory), on top of
standard ERC-721 + SRC5 + Ownable:

```cairo
fn mint(to: ContractAddress) -> u256; // public — pulls entry_fee if set

fn set_open(open: bool); // owner only

fn base_uri() -> ByteArray;
fn entry_fee() -> u256;
fn payment_token() -> Option<ContractAddress>;
fn max_supply() -> u256;
fn total_minted() -> u256;
fn is_open() -> bool;

fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn version() -> ByteArray;
```

Custom SRC5 interface IDs:

```cairo
// starknet_keccak("mediolano.ip-club-collection.v3")
IIP_CLUB_COLLECTION_ID =
0x4b7aad07052a830d89731d485a019e4035c06a1699b800a0e74f732e8158ad

// starknet_keccak("mediolano.ip-club-factory.v1")
IIP_CLUB_FACTORY_ID =
0x228cd17a62a26bc1bbc9f07724633fa45b6326759b4f6b44e856ade9ff59db1
```

## Access Semantics

A wallet holds a valid membership when:

```text
balance_of(wallet) > 0
```

Transfers move membership with ownership. Anyone may join any number of times
(paying the entry fee each time) and hold any number of cards.

## Development

```bash
cd contracts/IP-Club
scarb build
snforge test
```

Tested baseline:

| Package | Version |
| --- | --- |
| `starknet` | `2.12.0` |
| `openzeppelin_*` | `0.20.0` |
| `snforge_std` | `0.59.0` |

## Status

Deployed to Starknet mainnet 2026-07-15 (on-chain `IPClubCollection.version()`
== "3.0.0"). `IPClubFactory`:
`0x05519705345ce225db666253a21cf89d1c675658f16cc6ae4320cefd1a1219a3`,
`IPClubCollection` class hash:
`0x35b8836a2269523ae9176077ec525451cce1053b2acd9fae3b05354aa4eded3`.

Note: `IPClubFactory.version()` itself still reports `"1.0.0"` — the factory's
own logic is unchanged since its original 2026-07-12 deploy (this redeploy
only fixed `IPClubCollection`'s per-token metadata), so it reused its
already-declared class hash rather than getting a fresh one.

Superseded: the original registry contract
(`0x00e189c619b6bb07d78973a149641c59c37eb0716f8584d7520bce12d303eede`,
2026-07-02) and the first factory
(`0x010726346c264d1832a7303afaf5692dbd2b05446fecc6da30d958d0227c36d0`,
2026-07-12) remain valid on-chain for their existing clubs but are not
tracked here.
