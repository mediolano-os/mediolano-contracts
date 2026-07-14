# IP Tickets

`IP-Tickets` is a Starknet ERC-1155 tickets protocol. `IPTicketCollectionFactory`
deploys one `IPTicketCollection` per creator; inside their own collection, a
creator creates tickets — each ticket is one ERC-1155 token id with its own
supply, optional validity window, royalty, and metadata — and mints them to
holders.

Tickets are indexable and transferable ERC-1155 assets. Validity follows
current ownership inside the ticket's time window.

## Design

The contracts follow the Mediolano principles:

- **Ownerless factory, owned collections.** Anyone deploys their own
  `IPTicketCollection` via the factory; the factory itself has no admin, no
  upgrade path, and takes no fee. Inside a deployed collection, only its owner
  (the deployer) can create and mint tickets — the same access model as every
  other per-creator NFT contract in the catalog.
- **On-chain collection identity.** `deploy_collection(name, symbol, base_uri)`
  embeds the collection-level metadata URI in the deploy transaction;
  `name()`, `symbol()`, and `base_uri()` are readable on-chain. Per-ticket
  metadata lives on each token's `uri(token_id)`.
- **Minimal primitive.** The contract issues and validates tickets — nothing
  else. Sales happen on any marketplace that trades ERC-1155 (the tickets are
  ordinary, standards-compliant assets); door/check-in policy is an
  application concern built on the public `is_valid` read.
- **Checks-effects-interactions.** Ticket state is final before
  `mint_with_acceptance_check`'s external receiver call; a reentrant call runs
  against consistent storage and cannot pass the supply cap.
- **Royalty discovery.** The ERC-2981 interface ID is registered via SRC5 and
  `royalty_info` is exposed in snake_case alongside the camelCase
  `royaltyInfo` alias. The receiver is the collection owner.
- **Lean records.** Ticket existence derives from `max_supply != 0`
  (`create_ticket` rejects a zero supply); storage holds only what the
  contract enforces.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-tickets` |
| `asset_standard` | ERC1155 |
| `asset_role` | Transferable ticket / verifiable access pass |
| `transferability` | Transferable |
| `access_semantics` | Current balance of the ticket id inside its validity window |
| `marketplace_visibility` | Display and list as ERC1155 tickets |
| `metadata_uri_policy` | `ipfs://` or `ar://` (per ticket); collection `base_uri` free-form |
| `src5_interface_id` | `IIP_TICKET_COLLECTION_ID` + `IERC2981_ID` + `IERC1155_METADATA_URI_ID` (collection); `IIP_TICKET_COLLECTION_FACTORY_ID` (factory) |

## Features

- One deployed `IPTicketCollection` per creator, via the ownerless
  `IPTicketCollectionFactory` — the same shape as every other per-creator NFT
  contract, so tickets are tradeable and indexable like any other asset.
- Owner-gated ticket creation and minting inside each deployed collection.
- ERC-1155 tickets — one token id per ticket, sequential from 1, each with its
  own supply cap.
- Optional validity window per ticket (`start_time` / `end_time`, both
  optional); minting and validity respect it.
- `is_valid(token_id, holder)` — the on-chain door check: balance > 0 and
  inside the window.
- Content-addressed per-ticket metadata; `uri(token_id)` returns it.
- Collection identity on-chain: `name()`, `symbol()`, `base_uri()`.
- ERC-2981-style royalties per ticket, paid to the collection owner.
- SRC5 service interface detection.

## Interface

`IPTicketCollectionFactory`:

```cairo
fn collection_class_hash() -> ClassHash;
fn version() -> ByteArray;
fn deploy_collection(name: ByteArray, symbol: ByteArray, base_uri: ByteArray) -> ContractAddress;
```

`IPTicketCollection` (one per creator, deployed by the factory), on top of
standard ERC-1155 + SRC5 + Ownable:

```cairo
fn create_ticket(
    max_supply: u256,
    start_time: Option<u64>,
    end_time: Option<u64>,
    royalty_bps: u16,
    metadata_uri: ByteArray,
) -> u256; // owner only — returns the new ticket's token id

fn mint(to: ContractAddress, token_id: u256, amount: u256); // owner only

fn is_valid(token_id: u256, holder: ContractAddress) -> bool;
fn get_ticket(token_id: u256) -> Ticket;

fn name() -> ByteArray;
fn symbol() -> ByteArray;
fn base_uri() -> ByteArray;

fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn version() -> ByteArray;
```

Custom SRC5 interface IDs:

```cairo
// starknet_keccak("mediolano.ip-ticket-collection")
IIP_TICKET_COLLECTION_ID =
0x3fa3bcc658b1652be19ff630d5e6f577335cf31baa2c520c0dd8694a64f5711

// starknet_keccak("mediolano.ip-ticket-collection-factory")
IIP_TICKET_COLLECTION_FACTORY_ID =
0x6d61010de9cb760487aa7a674953e17e9bcb4e1e5a1db1cc54177420f14a22
```

## Access Semantics

A holder has a valid ticket when:

```text
ticket.max_supply != 0
&& balance_of(holder, token_id) > 0
&& (ticket.start_time is None || now >= start_time)
&& (ticket.end_time is None   || now <  end_time)
```

Transfers move validity with ownership. A ticket with no window is always
valid while held. Applications decide what presenting a valid ticket unlocks —
the contract provides the verifiable primitive.

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

Deployed to Starknet mainnet 2026-07-14 (on-chain `version()` == "4.0.0").
`IPTicketCollectionFactory`:
`0x059802639b41e9c6449c3d557703e610ef639a91866dc1dd44216f9f37111ac5`,
`IPTicketCollection` class hash:
`0x047bd108881457c4f4db6c64671c1dd402f4d8c79fd9182f03a2dd841335a34b`.
