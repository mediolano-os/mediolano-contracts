# IP Colab Collections

`IP-Colab-Collections` is a Starknet ERC-721 collaborative collection
protocol. `IPCollabCollectionFactory` deploys one `IPCollabCollection` per
creator; inside their own collection, a creator opens contribution types (a
round, a brief, a category), contributors submit content-addressed work, the
creator or their appointed verifiers approve or reject it, and each approved
contributor mints their own piece — an ordinary transferable ERC-721 with the
contributor as immutable royalty receiver and an on-chain registration
timestamp.

## Design

The contracts follow the Mediolano principles:

- **Ownerless factory, owned collections.** Anyone deploys their own
  `IPCollabCollection` via the factory; the factory itself has no admin, no
  upgrade path, and takes no fee. Inside a deployed collection, only its
  owner creates contribution types and manages verifiers — the same access
  model as every other per-creator contract in the catalog.
- **The contract records decisions, not opinions.** The on-chain review
  outcome is approve or reject; editorial context (scores, notes, briefs)
  lives in content-addressed metadata and events, never in immutable
  protocol storage.
- **Contributors own their work.** Only the approved contributor can mint
  their piece, the mint goes to them, and the EIP-2981 royalty receiver is
  the piece's contributor — immutable, surviving every transfer.
- **Deadlines gate submission only.** A contribution type may set an
  optional submission deadline; review and minting of already-submitted work
  stay open. No deadline means submissions stay open indefinitely.
- **Provenance on-chain.** Each minted token carries its registration
  timestamp, written in the mint transaction. Holders can permanently
  archive their token — freezing it in place; transfers are blocked in the
  ERC-721 transfer hook.
- **Minimal primitive.** No payment surface: primary and secondary sales are
  the marketplace's job. Delegated verifiers are the one collaboration
  affordance — shared curation over the creator's own collection, not a
  platform gate.
- **Lean records.** Type existence derives from `max_supply != 0`;
  contribution existence from a non-zero contributor; rosters and timestamps
  live in events — discovery is the indexer's job.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-colab` |
| `asset_standard` | ERC721 |
| `asset_role` | Approved contribution / collaborative collection piece |
| `transferability` | Transferable (holder can permanently archive) |
| `access_semantics` | Approval gates minting; ownership is standard ERC-721 |
| `marketplace_visibility` | Display and list as ERC721 assets |
| `metadata_uri_policy` | `ipfs://` or `ar://` (per contribution and per type); collection `base_uri` free-form |
| `src5_interface_id` | `IIP_COLAB_COLLECTION_ID` + `IERC2981_ID` (collection); `IIP_COLAB_COLLECTION_FACTORY_ID` (factory) |

## Contribution lifecycle

```text
create_contribution_type (owner) ──► submissions open
submit_contribution (anyone, inside optional deadline) ──► Pending
    Pending ──► approve_contribution (owner/verifier, consumes supply) ──► Approved
    Pending ──► reject_contribution  (owner/verifier; contributor may resubmit) ──► Rejected
    Approved ──► mint_contribution (contributor only) ──► Minted (ERC-721 to contributor)
    token holder ──► archive(token_id) ──► transfers blocked forever
```

Supply is enforced at approval (`approved_count < max_supply`); minting can
only trail approvals.

## Interface

`IPCollabCollectionFactory`:

```cairo
fn collection_class_hash() -> ClassHash;
fn version() -> ByteArray;
fn deploy_collection(name: ByteArray, symbol: ByteArray, base_uri: ByteArray) -> ContractAddress;
```

`IPCollabCollection` (one per creator, deployed by the factory), on top of
standard ERC-721 + SRC5 + Ownable:

```cairo
fn create_contribution_type(
    max_supply: u256,
    submission_deadline: Option<u64>,
    metadata_uri: ByteArray,
) -> u256; // owner only — returns the new type id

fn submit_contribution(type_id: u256, token_uri: ByteArray, royalty_bps: u16) -> u256;
fn approve_contribution(contribution_id: u256); // owner or verifier
fn reject_contribution(contribution_id: u256);  // owner or verifier
fn mint_contribution(contribution_id: u256) -> u256; // contributor only
fn archive(token_id: u256);                     // token owner only, permanent

fn add_verifier(verifier: ContractAddress);     // owner only
fn remove_verifier(verifier: ContractAddress);  // owner only
fn is_verifier(verifier: ContractAddress) -> bool;

fn is_archived(token_id: u256) -> bool;
fn get_contribution(contribution_id: u256) -> Contribution;
fn get_contribution_type(type_id: u256) -> ContributionType;
fn contribution_count() -> u256;
fn type_count() -> u256;
fn get_token_contribution(token_id: u256) -> u256;
fn token_registered_at(token_id: u256) -> u64;

fn base_uri() -> ByteArray;
fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn version() -> ByteArray;
```

Custom SRC5 interface IDs:

```cairo
// starknet_keccak("mediolano.ip-colab-collection")
IIP_COLAB_COLLECTION_ID =
0x3c588807d244faed9fe997f1b4af0df7b35b3390a833fedcaf4f9c44adb3408

// starknet_keccak("mediolano.ip-colab-collection-factory")
IIP_COLAB_COLLECTION_FACTORY_ID =
0x35c3bb8e927cb0ab50c70e5c6c99357be5ff4dc05ee574a2620063f08cd555d
```

## Development

```bash
cd contracts/IP-Colab-Collections
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
