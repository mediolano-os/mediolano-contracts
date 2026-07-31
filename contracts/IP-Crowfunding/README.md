# IP Crowdfunding

`IP-Crowfunding` is a Starknet crowdfunding (patronage) protocol.
`IPCrowdfundingCollectionFactory` deploys one `IPCrowdfundingCollection` per
creator; inside their own collection, a creator opens deadline-bound
campaigns — each campaign is one ERC-1155 token id with its own goal, payment
token, and metadata. Backers contribute until `end_time`; if the goal is met
the creator claims the raise and each backer mints a **soulbound supporter
receipt** (balance = amount backed); if not, every backer reclaims their
contribution.

This is deliberately a different product from `IP-Syndication`: syndication
is target-bound funding with *transferable shares* and no clock; crowdfunding
is *patronage* — deadline-bound, overfunding welcome, and the receipt is
proof of backing, never a tradable share.

## Design

The contracts follow the Mediolano principles:

- **Ownerless factory, owned collections.** Anyone deploys their own
  `IPCrowdfundingCollection` via the factory; the factory itself has no
  admin, no upgrade path, and takes no fee. Inside a deployed collection,
  only its owner creates and manages campaigns.
- **Outcomes are arithmetic, not administration.** Success and failure are
  never stored: at `end_time` a campaign has succeeded iff
  `total_raised >= goal_amount`. No one flips the outcome; the only stored
  flags are `cancelled` (owner, while live) and `proceeds_claimed`
  (one-shot).
- **No one but the backer controls the backer's exit.** While a campaign is
  live, `withdraw` returns any part of a contribution, unconditionally.
  After failure or cancellation, refunds are pull-based and unconditional.
- **Receipts are proof, not product.** Supporter receipts mint only after
  success, only to backers, balance = amount backed — and they are soulbound
  (transfers blocked in the ERC-1155 hook). Visibility without
  financialization, per the service-asset doctrine.
- **Checks-effects-interactions.** State is final before every external
  call; a balance-delta check on contribute rejects fee-on-transfer tokens.
- **Lean records.** Campaign existence derives from `goal_amount != 0`; one
  `Position` per backer is the entire ledger; the roster lives in events —
  discovery is the indexer's job.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-crowdfunding` |
| `asset_standard` | ERC1155 |
| `asset_role` | Soulbound supporter receipt of a successful campaign |
| `transferability` | Non-transferable |
| `access_semantics` | Receipt balance = amount backed; escrow, proceeds, and refunds derive from positions and arithmetic outcomes |
| `marketplace_visibility` | Display on profiles/creator pages; no listing |
| `metadata_uri_policy` | `ipfs://` or `ar://` (per campaign); collection `base_uri` free-form |
| `src5_interface_id` | `IIP_CROWDFUNDING_COLLECTION_ID` + `IERC1155_METADATA_URI_ID` (collection); `IIP_CROWDFUNDING_COLLECTION_FACTORY_ID` (factory) |

## Campaign lifecycle

```text
create_campaign ──► Active ──── contribute / withdraw
                      │
     now >= end_time ─┼── owner cancels (while live)
          ▼           ▼                    ▼
   raised >= goal   raised < goal      Cancelled
     Succeeded         Failed          claim_refund
     claim_proceeds    claim_refund
     (owner, once)
     mint_receipt
     (backers, soulbound)
```

Overfunding is allowed — contributions are accepted until `end_time`
regardless of the goal. Status is a derived view (`campaign_status`), never
stored.

## Interface

`IPCrowdfundingCollectionFactory`:

```cairo
fn collection_class_hash() -> ClassHash;
fn version() -> ByteArray;
fn deploy_collection(name: ByteArray, symbol: ByteArray, base_uri: ByteArray) -> ContractAddress;
```

`IPCrowdfundingCollection` (one per creator, deployed by the factory), on top
of standard ERC-1155 + SRC5 + Ownable:

```cairo
fn create_campaign(
    goal_amount: u256,
    payment_token: ContractAddress,
    end_time: u64,
    metadata_uri: ByteArray,
) -> u256; // owner only — returns the new campaign's token id

fn contribute(token_id: u256, amount: u256) -> u256; // while live; overfunding ok
fn withdraw(token_id: u256, amount: u256);           // while live
fn cancel_campaign(token_id: u256);                  // owner only, while live
fn claim_proceeds(token_id: u256) -> u256;           // owner only, once, after success
fn claim_refund(token_id: u256) -> u256;             // after failure or cancellation
fn mint_receipt(token_id: u256);                     // backers, after success, once

fn campaign_status(token_id: u256) -> CampaignStatus; // Active|Succeeded|Failed|Cancelled
fn get_campaign(token_id: u256) -> Campaign;
fn get_position(token_id: u256, backer: ContractAddress) -> Position;
fn campaign_count() -> u256;

fn name() -> ByteArray;
fn symbol() -> ByteArray;
fn base_uri() -> ByteArray;
fn version() -> ByteArray;
```

Custom SRC5 interface IDs:

```cairo
// starknet_keccak("mediolano.ip-crowdfunding-collection")
IIP_CROWDFUNDING_COLLECTION_ID =
0x1ca39f27ea66535fc3ceda4034bf407bfba9d0e57f91ce57ee08e67564e4b06

// starknet_keccak("mediolano.ip-crowdfunding-collection-factory")
IIP_CROWDFUNDING_COLLECTION_FACTORY_ID =
0xb6cbd8e29167b4fca59079072e0125d765efbb8a5fe0318bc426043ddb79b9
```

## Development

```bash
cd contracts/IP-Crowfunding
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
