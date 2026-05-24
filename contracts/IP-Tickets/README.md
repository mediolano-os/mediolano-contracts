# IP Tickets

`IP-Tickets` is a Starknet ERC-721 ticket service for creator-defined ticket series.

Tickets are indexable and transferable ERC-721 assets. Access follows current ownership until the ticket expires or is redeemed.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-tickets` |
| `asset_standard` | ERC721 |
| `asset_role` | Transferable ticket / redeemable access pass |
| `transferability` | Transferable |
| `access_semantics` | Current ownership of at least one unredeemed, unexpired ticket in a series |
| `marketplace_visibility` | Display and list as ERC721 tickets |
| `metadata_uri_policy` | `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_TICKET_SERVICE_ID` |

## Features

- Permissionless ticket series creation.
- ERC-721 tickets.
- Transferable tickets where access moves with ownership.
- Ticket redemption.
- Expiration-based access.
- Free or ERC-20 paid ticket series.
- Direct payment to the series creator.
- `safe_mint` ticket issuance.
- Content-addressed series metadata.
- ERC-721 `token_uri` returns the series metadata.
- ERC-2981-style `royaltyInfo`.
- SRC5 service interface detection.

## Interface

```cairo
fn create_ticket_series(
    price: u256,
    max_supply: u256,
    expiration: u64,
    royalty_bps: u256,
    payment_token: Option<ContractAddress>,
    metadata_uri: ByteArray,
) -> u256;

fn mint_ticket(series_id: u256) -> u256;
fn redeem_ticket(token_id: u256);

fn has_valid_ticket(user: ContractAddress, series_id: u256) -> bool;
fn get_ticket_series(series_id: u256) -> TicketSeries;
fn get_ticket_data(token_id: u256) -> TicketData;
fn get_ticket_series_id(token_id: u256) -> u256;
fn get_active_ticket_balance(user: ContractAddress, series_id: u256) -> u256;
fn get_last_series_id() -> u256;
fn total_supply() -> u256;
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
```

Custom SRC5 interface ID:

```cairo
IIP_TICKET_SERVICE_ID =
0x0064383abff0b2487b1c4acd681d761b39c91cc025a43bf0f7a355641b7c644f
```

## Access Semantics

A user has valid access when:

```text
series.exists
&& get_block_timestamp() < series.expiration
&& active_ticket_balance[(user, series_id)] > 0
```

Transfers move active access for unredeemed tickets. Redeemed tickets remain ERC-721 assets but no longer grant access.

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

This package has been redesigned from the legacy prototype. It is still pre-production until it receives external security review and deployment rehearsal.
