# IP Club

`IP-Club` is a permissionless Starknet protocol for NFT-gated IP communities.
Anyone can create a club, and each club receives its own immutable ERC-721
membership contract.

The protocol is designed as a public-good primitive:

- Permissionless club creation.
- One ERC-721 membership collection per club.
- Optional ERC-20 entry fee paid directly to the club creator.
- Creator-chosen transferability: a membership card is transferable once a
  per-club vesting period (set immutably at club creation) has elapsed since
  its mint — or permanently non-transferable if the creator sets no vesting.
- EIP-2981 royalty to the club creator on card resales (basis points set
  immutably at club creation).
- No per-wallet limits: a wallet may join any number of times, paying the
  entry fee each time, and may hold any number of cards.
- Content-addressed club metadata only: `ipfs://` or `ar://`.
- `safe_mint` membership issuance to prevent locked NFTs.
- No upgrade path in the manager contract.

## Design

- **Members can leave.** `leave_club(club_id, token_id)` burns the caller's
  own membership NFT and frees the seat. Exit is always allowed — open or
  closed club — and the entry fee is not refunded (it flowed to the creator
  at join time). Nobody is kept on a public on-chain roster against their
  will.
- **Closure is reversible.** `set_club_open(club_id, open)` — creator-only,
  gating **new joins only**. Existing memberships and the right to leave are
  never affected.
- **Checks-effects-interactions.** Club state is final before the fee
  transfer and the membership mint; a reentrant payment token runs under its
  own caller context and the transaction reverts atomically (tested with a
  single-reentry mock).
- **Lean records.** The club's NFT contract is the source of truth for asset
  metadata; the registry record holds only what it enforces (existence ⇔
  `creator != 0`; `open: bool` is the only switch).
- **Indexer-complete events.** `NewClubCreated` carries the deployed
  `club_nft` address; `ClubStatusUpdated` and `MemberLeft` cover the full
  lifecycle.

## Service Asset Declaration

This service follows the shared doctrine in
[`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-club` |
| `asset_standard` | ERC721 |
| `asset_role` | Club membership badge/access pass |
| `transferability` | Creator-chosen: transferable after the club's vesting lock, or never if none is set |
| `access_semantics` | Current ownership of the `IPClubNFT` |
| `marketplace_visibility` | Display and index; no default marketplace listing |
| `metadata_uri_policy` | `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_CLUB_ID`, `IIP_CLUB_NFT_ID` |

The membership NFT exists for visibility, indexing, and access checks.
`num_members` counts cards outstanding (joins minus leaves); transfers move
membership without changing the count.

## Contracts

| Contract | Role |
| --- | --- |
| `IPClub` | Registry and club factory. Deploys per-club membership NFTs, stores club records, processes joins, and exposes membership checks. |
| `IPClubNFT` | Per-club ERC-721 membership pass. Only its `IPClub` manager can mint or burn. Transfers are gated by the club's vesting lock; burns (leaving) are always allowed. |

## Club Lifecycle

1. Deploy `IPClub` with the declared `IPClubNFT` class hash.
2. A creator calls `create_club`.
3. `IPClub` deploys a dedicated `IPClubNFT`.
4. Members call `join_club`.
5. If configured, the ERC-20 entry fee is transferred to the creator.
6. `IPClubNFT.safe_mint` issues the membership NFT.
7. The creator can call `set_club_open(club_id, false)` to stop new joins
   (reversible; never affects existing members or the right to leave).

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
    transfer_lock: Option<u64>,   // seconds from mint until a card is transferable; None = never
    royalty_bps: u256,            // EIP-2981 royalty to the creator on card resales
) -> u256;

fn set_club_open(club_id: u256, open: bool);
fn join_club(club_id: u256);
fn leave_club(club_id: u256, token_id: u256);
fn get_club_record(club_id: u256) -> ClubRecord;
fn is_member(club_id: u256, user: ContractAddress) -> bool;
fn get_last_club_id() -> u256;
fn version() -> ByteArray;
```

Custom SRC5 interface ID:

```cairo
// starknet_keccak("mediolano.ip-club.v2")
IIP_CLUB_ID =
0x027db28e39a9c175613ead4d5f54645106b22d41799a23649c05efbee3ebab61
```

### `IPClubNFT`

```cairo
fn mint(recipient: ContractAddress);                 // manager (registry) only
fn burn(member: ContractAddress, token_id: u256);    // manager (registry) only — the leave path
fn has_nft(user: ContractAddress) -> bool;
fn get_nft_creator() -> ContractAddress;
fn get_ip_club_manager() -> ContractAddress;
fn get_associated_club_id() -> u256;
fn get_last_minted_id() -> u256;
fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn version() -> ByteArray;
```

Custom SRC5 interface IDs (the NFT also registers `IERC2981_ID` and the
`ILICENSED_COLLECTION_ID` programmable-license discovery marker):

```cairo
// starknet_keccak("mediolano.ip-club-nft.v2")
IIP_CLUB_NFT_ID =
0x03ec0e4175cbdefdf73fd14b4d6cfe3ada3a099f0e85bc971bba220a62caffbd
```

## Security Posture

- `join_club` follows checks-effects-interactions: club state is final before
  the fee transfer and the mint; a revert rolls the whole transaction back.
- `IPClubNFT` uses `safe_mint`.
- `IPClubNFT`'s transfer hook enforces the club's vesting lock; mints and
  burns are never gated.
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

Deployed to Starknet mainnet 2026-07-02. Registry:
`0x00e189c619b6bb07d78973a149641c59c37eb0716f8584d7520bce12d303eede`,
`IPClubNFT` class hash:
`0x02bc9b20cca21b04245e9215bf7121f4d7295b195890e449b472b573017fb889`.
