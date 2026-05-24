# IP Syndication

`IPSyndication` is a Mediolano service contract for funding an IP asset and minting ERC-1155 syndication shares after the funding target is reached.

The contract is both the syndication registry and the ERC-1155 share asset. There is no separate unrestricted NFT minter.

## Service Declaration

| Field | Value |
| --- | --- |
| `service_id` | `ip-syndication` |
| `asset_standard` | ERC1155 |
| `asset_role` | Transferable syndication share and funded participation receipt |
| `transferability` | transferable |
| `access_semantics` | Current ERC-1155 balance represents visible share ownership; refund rights remain with the original participant record; proceeds rights remain with the IP owner |
| `marketplace_visibility` | list/display ERC-1155 shares after mint; route service state through indexed events |
| `metadata_uri_policy` | IP and token metadata URI must be `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_SYNDICATION_ID` |

## Lifecycle

1. The IP owner calls `register_ip` with a target amount, metadata, licensing terms, public or whitelist mode, and ERC-20 payment token.
2. The owner calls `activate_syndication`.
3. Participants call `deposit`.
4. The syndication becomes `Completed` when `total_raised == target_amount`.
5. Participants call `mint_asset` to mint their ERC-1155 share balance.
6. The IP owner calls `claim_proceeds` once.

The owner may call `cancel_syndication` only while the syndication is pending or active. After cancellation, participants claim refunds through `claim_refund`.

## Funding Semantics

Deposits are capped to the remaining target amount. A participant who submits more than the remaining amount only deposits the remaining amount.

The contract expects a standard ERC-20 token that returns `true` from `transfer_from` and `transfer`.

Deposits validate exact receipt by comparing the contract payment-token balance before and after `transfer_from`. A token that transfers less than the credited deposit amount is rejected.

## Share Semantics

The ERC-1155 token ID is the `ip_id`.

Each participant may mint once after completion. Minted share amount equals:

```text
amount_deposited - amount_refunded
```

ERC-1155 shares are transferable. Transfer moves the visible share asset only. It does not transfer:

- refund claim rights;
- creator proceeds rights;
- the original participant accounting record.

## Whitelist Mode

In `Mode::Whitelist`, only the IP owner may update the whitelist, and deposits require `is_whitelisted(ip_id, participant) == true`.

Whitelist updates are allowed while the syndication is pending or active.

## Discoverability

The contract registers `IIP_SYNDICATION_ID` through SRC5 and embeds OpenZeppelin ERC-1155 interfaces.

Participants can be read with either `get_all_participants(ip_id)` for small syndications or `get_participants(ip_id, start, limit)` for paginated indexer reads.

Indexers should use keyed events for service state:

- `IPRegistered`
- `SyndicationActivated`
- `ParticipantAdded`
- `DepositReceived`
- `SyndicationCompleted`
- `WhitelistUpdated`
- `SyndicationCancelled`
- `RefundClaimed`
- `ProceedsClaimed`
- `AssetMinted`

## Non-Goals

- No platform fee is charged.
- No admin, upgrade, pause, or owner override exists.
- No off-chain license enforcement is performed.
- Fee-on-transfer or rebasing ERC-20 tokens are rejected or unsupported unless a future adapter explicitly handles them.
- No private metadata is stored on-chain.

Custom SRC5 interface ID:

```cairo
pub const IIP_SYNDICATION_ID: felt252 =
    0x03d8a3fb2b0e94c537cf673b579ec4cb94e6916e1fc0f38ecf50cc13fb6a2fb5;
```
