# IP Tickets

`IP-Tickets` is a Starknet ERC-721 ticket protocol. `IPTicketCollectionFactory`
deploys one `IPTicketCollection` per creator; inside their own collection, a
creator issues one or more ticket collections (e.g. per event or tier), and
buyers mint tickets from them.

Tickets are indexable and transferable ERC-721 assets. Access follows current
ownership until the ticket expires or is redeemed.

## Design

The contracts follow the Mediolano principles:

- **Ownerless factory, owned collections.** Anyone deploys their own
  `IPTicketCollection` via the factory; the factory itself has no admin, no
  upgrade path, and takes no fee. Inside a deployed collection, only its
  owner (the deployer) can create ticket collections or toggle them active —
  the same access model as every other Medialane per-creator NFT contract.
- **Creator sales switch.** `set_collection_active(collection_id, active)`
  (owner only) gates **minting only** — existing tickets keep their access,
  stay transferable, and stay redeemable. A creator can stop new money (e.g. a
  cancelled event), never confiscate sold assets.
- **Checks-effects-interactions.** Collection/token state is final before the
  payment transfer and `safe_mint`; a reentrant call runs under its own
  caller context against consistent storage.
- **Royalty discovery.** The ERC-2981 interface ID is registered via SRC5 and
  `royalty_info` is exposed in snake_case alongside the camelCase
  `royaltyInfo` alias.
- **Lean records.** Ticket collection existence derives from `creator != 0`;
  storage holds only what the contract enforces.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-tickets` |
| `asset_standard` | ERC721 |
| `asset_role` | Transferable ticket / redeemable access pass |
| `transferability` | Transferable |
| `access_semantics` | Current ownership of at least one unredeemed, unexpired ticket in a collection |
| `marketplace_visibility` | Display and list as ERC721 tickets |
| `metadata_uri_policy` | `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_TICKET_COLLECTION_ID` + `IERC2981_ID` (collection); `IIP_TICKET_COLLECTION_FACTORY_ID` (factory) |

## Features

- One deployed `IPTicketCollection` per creator, via the ownerless
  `IPTicketCollectionFactory` — same shape as every other Medialane
  per-creator NFT contract, so tickets are tradeable and indexable like any
  other asset.
- Owner-gated ticket collection creation inside each deployed collection.
- ERC-721 tickets.
- Transferable tickets where access moves with ownership.
- Ticket redemption.
- Expiration-based access.
- Free or ERC-20 paid ticket collections.
- Direct payment to the collection owner.
- `safe_mint` ticket issuance.
- Content-addressed ticket collection metadata.
- ERC-721 `token_uri` returns the ticket collection metadata.
- ERC-2981-style `royaltyInfo`.
- SRC5 service interface detection.

## Interface

`IPTicketCollectionFactory`:

```cairo
fn collection_class_hash() -> ClassHash;
fn version() -> ByteArray;
fn deploy_ticket_collection(name: ByteArray, symbol: ByteArray) -> ContractAddress;
```

`IPTicketCollection` (one per creator, deployed by the factory):

```cairo
fn create_ticket_collection(
    price: u256,
    max_supply: u256,
    expiration: u64,
    royalty_bps: u256,
    payment_token: Option<ContractAddress>,
    metadata_uri: ByteArray,
) -> u256; // owner only

fn set_collection_active(collection_id: u256, active: bool); // owner only
fn mint_ticket(collection_id: u256) -> u256;
fn redeem_ticket(token_id: u256);

fn has_valid_ticket(user: ContractAddress, collection_id: u256) -> bool;
fn get_ticket_collection(collection_id: u256) -> TicketCollection;
fn get_ticket_data(token_id: u256) -> TicketData;
fn get_ticket_collection_id(token_id: u256) -> u256;
fn get_active_ticket_balance(user: ContractAddress, collection_id: u256) -> u256;
fn get_last_collection_id() -> u256;
fn total_supply() -> u256;
fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
```

Custom SRC5 interface IDs:

```cairo
IIP_TICKET_COLLECTION_ID =
0x329801ec79f9a18a441f490a55694aadd00b57e11fc1f2fc561b9bebc68e3d9

IIP_TICKET_COLLECTION_FACTORY_ID =
0x27717c17c18e684321a4326345c6ee264d3a91a7b6f1b54e02de0332fb76f58
```

## Access Semantics

A user has valid access when:

```text
collection.creator != 0
&& get_block_timestamp() < collection.expiration
&& active_ticket_balance[(user, collection_id)] > 0
```

Transfers move active access for unredeemed tickets. **Redeemed or expired
tickets remain transferable ERC-721 assets but no longer grant access** —
marketplaces and buyers must check `get_ticket_data(token_id).valid` before
pricing a secondary sale. Deactivating a ticket collection blocks minting
only.

## Development

```bash
cd contracts/IP-Tickets
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

Pre-production until external security review and deployment rehearsal.
