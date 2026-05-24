# IP Club

`IP-Club` is a permissionless Starknet protocol for NFT-gated IP communities.
Anyone can create a club, and each club receives its own immutable ERC-721
membership contract.

The protocol is designed as a public-good primitive:

- Permissionless club creation.
- One ERC-721 membership collection per club.
- Optional ERC-20 entry fee paid directly to the club creator.
- Non-transferable membership NFTs, so membership state cannot drift from NFT
  ownership.
- Content-addressed club metadata only: `ipfs://` or `ar://`.
- `safe_mint` membership issuance to prevent locked NFTs.
- No upgrade path in the manager contract.

## Service Asset Declaration

This service follows the shared doctrine in
[`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-club` |
| `asset_standard` | ERC721 |
| `asset_role` | Club membership badge/access pass |
| `transferability` | Non-transferable |
| `access_semantics` | Current ownership of the non-transferable `IPClubNFT` |
| `marketplace_visibility` | Display and index; no default marketplace listing |
| `metadata_uri_policy` | `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_CLUB_ID`, `IIP_CLUB_NFT_ID` |

The membership NFT exists for visibility, indexing, and access checks. It is
not tradable by default because transferability would make membership state and
membership count harder to reason about.

## Contracts

| Contract | Role |
| --- | --- |
| `IPClub` | Registry and club factory. Deploys per-club membership NFTs, stores club records, processes joins, and exposes membership checks. |
| `IPClubNFT` | Per-club ERC-721 membership pass. Only its `IPClub` manager can mint. Membership passes are non-transferable. |

## Club Lifecycle

1. Deploy `IPClub` with the declared `IPClubNFT` class hash.
2. A creator calls `create_club`.
3. `IPClub` deploys a dedicated `IPClubNFT`.
4. Members call `join_club`.
5. If configured, the ERC-20 entry fee is transferred to the creator.
6. `IPClubNFT.safe_mint` issues the membership NFT.
7. The creator can call `close_club` to stop new joins.

## Metadata

`metadata_uri` must be content-addressed:

```text
ipfs://bafy...
ar://...
```

HTTP URLs are intentionally rejected.

## Interface

### `IPClub`

```cairo
fn create_club(
    name: ByteArray,
    symbol: ByteArray,
    metadata_uri: ByteArray,
    max_members: Option<u32>,
    entry_fee: Option<u256>,
    payment_token: Option<ContractAddress>,
) -> u256;

fn close_club(club_id: u256);
fn join_club(club_id: u256);
fn get_club_record(club_id: u256) -> ClubRecord;
fn is_member(club_id: u256, user: ContractAddress) -> bool;
fn get_last_club_id() -> u256;
```

Custom SRC5 interface ID:

```cairo
IIP_CLUB_ID =
0x03b5aa442badd81e46ab69f8de85a01dd131401c146133b0a1a9a112270e9c7b
```

### `IPClubNFT`

```cairo
fn mint(recipient: ContractAddress);
fn has_nft(user: ContractAddress) -> bool;
fn get_nft_creator() -> ContractAddress;
fn get_ip_club_manager() -> ContractAddress;
fn get_associated_club_id() -> u256;
fn get_last_minted_id() -> u256;
```

Custom SRC5 interface ID:

```cairo
IIP_CLUB_NFT_ID =
0x02ad826916536b2ddefafc363444005820a6fc6fd5eb34b4f4131b02a8a3cdf4
```

## Security Posture

- `join_club` uses a reentrancy lock.
- Membership count is reserved before external ERC-20 and ERC-721 receiver
  calls; a revert rolls the whole transaction back.
- `IPClubNFT` uses `safe_mint`.
- `IPClubNFT` blocks normal ERC-721 transfers, preserving membership semantics.
- Missing clubs revert explicitly with `Club does not exist`.
- Events key `club_id`, creator/member, and token identifiers for indexers.

## Development

```bash
cd contracts/IP-Club
scarb build
snforge test
```

Current tested dependency baseline:

| Package | Version |
| --- | --- |
| `starknet` | `2.12.0` |
| `openzeppelin_*` | `0.20.0` |
| `snforge_std` | `0.59.0` |

## Status

This folder has been redesigned from the legacy implementation according to
the audit in `AUDIT_REPORT.md`. It is still pre-production until it receives an
external security review and deployment rehearsal.
