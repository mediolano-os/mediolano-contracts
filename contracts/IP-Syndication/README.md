# IP Syndication

`IP-Syndication` is a Starknet ERC-1155 syndication protocol.
`IPSyndicationCollectionFactory` deploys one `IPSyndicationCollection` per
creator; inside their own collection, a creator opens syndication campaigns —
each campaign is one ERC-1155 token id with its own funding target, payment
token, and metadata. Participants escrow deposits toward the target; when it
is reached, the creator claims the raise and each participant mints their
shares — transferable ERC-1155 balances proportional to what they put in.

## Design

The contracts follow the Mediolano principles:

- **Ownerless factory, owned collections.** Anyone deploys their own
  `IPSyndicationCollection` via the factory; the factory itself has no admin,
  no upgrade path, and takes no fee. Inside a deployed collection, only its
  owner (the deployer) can create and manage campaigns — the same access
  model as every other per-creator contract in the catalog.
- **No one but the participant controls the participant's exit.** While a
  campaign is active, `withdraw` returns any part of a deposit,
  unconditionally. Reaching the target is the single point where deposits
  become the creator's proceeds and shares become the participant's asset.
  Cancellation refunds; it is not the only exit.
- **Escrow is enforced on-chain deliberately.** Selective on-chain
  enforcement is exactly what an escrowed raise needs — the payment surface
  is the service. Deposits are held by the collection contract and leave it
  only through withdraw, refund, or the one-shot proceeds claim.
- **Checks-effects-interactions.** State is final before every external call
  (ERC-20 transfers, the share mint's receiver check); a reentrant call runs
  against consistent storage. A balance-delta check on deposit rejects
  fee-on-transfer payment tokens, keeping escrow accounting exact.
- **On-chain collection identity.** `deploy_collection(name, symbol,
  base_uri)` embeds the collection-level metadata URI in the deploy
  transaction; `name()`, `symbol()`, and `base_uri()` are readable on-chain.
  Per-campaign metadata lives on each token's `uri(token_id)`.
- **Lean records.** Campaign existence derives from `target_amount != 0`; a
  participant's `Position.deposited` is the single live escrow balance —
  deposits raise it, withdrawals and refunds lower it, and after completion
  it is the exact share count. The roster and descriptive fields live in
  events and metadata; discovery is the indexer's job.
- **Royalty discovery.** The ERC-2981 interface ID is registered via SRC5 and
  `royalty_info` is exposed in snake_case alongside the camelCase
  `royaltyInfo` alias. The receiver is the collection owner.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-syndication` |
| `asset_standard` | ERC1155 |
| `asset_role` | Transferable syndication share / funded participation |
| `transferability` | Transferable |
| `access_semantics` | Shares mint from completed funding participation; escrow derives from positions |
| `marketplace_visibility` | Display and list as ERC1155 syndication shares |
| `metadata_uri_policy` | `ipfs://` or `ar://` (per campaign); collection `base_uri` free-form |
| `src5_interface_id` | `IIP_SYNDICATION_COLLECTION_ID` + `IERC2981_ID` + `IERC1155_METADATA_URI_ID` (collection); `IIP_SYNDICATION_COLLECTION_FACTORY_ID` (factory) |

## Campaign lifecycle

```text
create_syndication ──► Active ──── deposit / withdraw / set_whitelist
                         │
        target reached ──┼── owner cancels
                         ▼             ▼
                     Completed      Cancelled
                     claim_proceeds (owner, once)
                     mint_shares    claim_refund
                     (participants) (participants)
```

- Deposits clamp to the amount still needed; the deposit that reaches the
  target completes the campaign in the same call.
- Completion and cancellation are final and mutually exclusive.
- Shares minted across all participants always sum to `total_raised`.

## Interface

`IPSyndicationCollectionFactory`:

```cairo
fn collection_class_hash() -> ClassHash;
fn version() -> ByteArray;
fn deploy_collection(name: ByteArray, symbol: ByteArray, base_uri: ByteArray) -> ContractAddress;
```

`IPSyndicationCollection` (one per creator, deployed by the factory), on top
of standard ERC-1155 + SRC5 + Ownable:

```cairo
fn create_syndication(
    target_amount: u256,
    payment_token: ContractAddress,
    whitelist: bool,
    royalty_bps: u16,
    metadata_uri: ByteArray,
) -> u256; // owner only — returns the new campaign's token id

fn deposit(token_id: u256, amount: u256) -> u256; // clamped; returns actual
fn withdraw(token_id: u256, amount: u256);        // while active
fn cancel_syndication(token_id: u256);            // owner only, while active
fn claim_refund(token_id: u256) -> u256;          // after cancellation
fn claim_proceeds(token_id: u256) -> u256;        // owner only, once
fn mint_shares(token_id: u256);                   // after completion, once
fn set_whitelist(token_id: u256, account: ContractAddress, allowed: bool); // owner only

fn is_whitelisted(token_id: u256, account: ContractAddress) -> bool;
fn get_syndication(token_id: u256) -> Syndication;
fn get_position(token_id: u256, participant: ContractAddress) -> Position;
fn syndication_count() -> u256;

fn name() -> ByteArray;
fn symbol() -> ByteArray;
fn base_uri() -> ByteArray;

fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn version() -> ByteArray;
```

Custom SRC5 interface IDs:

```cairo
// starknet_keccak("mediolano.ip-syndication-collection")
IIP_SYNDICATION_COLLECTION_ID =
0x81a59cb693f1445e616eee7c588bb5df2fb944bd06f5596f7eef06f20fadf0

// starknet_keccak("mediolano.ip-syndication-collection-factory")
IIP_SYNDICATION_COLLECTION_FACTORY_ID =
0x3159ddd4f8ff760d907ca2163bff029ecc782536835307398c21e237106b0e9
```

## Development

```bash
cd contracts/IP-Syndication
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

Not deployed. Declare + deploy are a deliberate post-review action.
