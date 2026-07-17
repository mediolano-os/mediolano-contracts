# IP Commission Escrow

`IP-Commission-Escrow` is a Starknet escrow protocol for commissioning custom
creative work. A commissioner opens a commission — brief, payment token,
milestone schedule, deadline, and their own review SLA — and escrows the full
budget in the same transaction. A creator accepts (open or invited offers),
delivers milestone by milestone, and earns each one on approval. A
non-transferable ERC-721 offer record makes the commission visible.

## Design

The contract follows the Mediolano principles:

- **One shared contract, deliberately.** A commission is a two-party
  agreement initiated by a commissioner, not a creator-branded collection;
  its offer NFT is a non-transferable record, not a market asset. There is
  no factory, no admin, no owner — nobody controls the contract at all.
- **Symmetric exits.** Every party reaches a terminal state without the
  other's cooperation: the commissioner cancels before acceptance or after
  the deadline; the creator abandons at any time (unearned milestones become
  refundable, earned ones stay claimable); and a milestone left under review
  past the commissioner's own `review_period` becomes claimable by the
  creator.
- **Silence never wins.** Deliverables are public the moment they are
  submitted (content-addressed), so an unanswered submission must resolve:
  approve, request a bounded revision, or time out in the creator's favor.
  Cancel cannot reach past a milestone under review.
- **Escrow is enforced on-chain deliberately.** Selective on-chain
  enforcement is exactly what a commission needs — funds are custodied by
  the contract and leave only through earned claims and refunds, all
  pull-based.
- **Checks-effects-interactions.** State is final before every external
  call; a balance-delta check on the creation escrow rejects fee-on-transfer
  tokens.
- **The contract records decisions, not judgments.** Briefs, licenses (in
  the brief's metadata attributes), and deliverables are content-addressed
  pointers; the CID is the integrity — no separate hashes. The contract
  never interprets the work.
- **Lean records.** Commission existence derives from a non-zero
  commissioner; milestone existence from a non-zero amount; each party's
  unclaimed balance is a field, not a map; timestamps beyond the review
  window live in events.

## Service Asset Declaration

This service follows the shared doctrine in [`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-commission-escrow` |
| `asset_standard` | ERC721 |
| `asset_role` | Non-transferable commission offer / escrow record |
| `transferability` | Non-transferable |
| `access_semantics` | Commission state, milestone approval, claims, and refunds derive from escrow records, not from the ERC-721 |
| `marketplace_visibility` | Display/index as an offer asset; no listing or resale |
| `metadata_uri_policy` | Brief and deliverable URIs must be `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_COMMISSION_ESCROW_ID` |

## Commission lifecycle

```text
create_commission (escrows full budget, mints offer NFT) ──► Open
    Open ──► accept_commission (creator, before deadline) ──► InProgress
    Open ──► cancel_commission (commissioner) ──► Cancelled (full refund)

    InProgress, per milestone (strictly sequential):
        submit_milestone (creator, before deadline) ──► under review
        approve_milestone (commissioner) ──► earned
        request_revision (commissioner, bounded) ──► resubmit
        claim_overdue_milestone (creator, after review_period) ──► earned

    all milestones earned ──► Completed
    cancel_commission (commissioner, past deadline, nothing under review)
        ──► Cancelled (unreleased refund; earned stays claimable)
    abandon_commission (creator, any time) ──► Cancelled (same split)

claim_creator_funds / claim_commissioner_refund — pull payments, any time
their balance is positive.
```

## Interface

```cairo
fn create_commission(
    invited_creator: ContractAddress, // zero = open offer
    payment_token: ContractAddress,
    brief_uri: ByteArray,             // ipfs:// or ar:// — brief + license metadata
    revisions_allowed: u32,
    deadline: u64,
    review_period: u64,               // seconds; the commissioner's review SLA
    milestone_amounts: Array<u256>,   // budget = sum
) -> u256;

fn accept_commission(commission_id: u256);
fn submit_milestone(commission_id: u256, milestone_index: u32, deliverable_uri: ByteArray);
fn approve_milestone(commission_id: u256, milestone_index: u32);
fn request_revision(commission_id: u256, milestone_index: u32);
fn claim_overdue_milestone(commission_id: u256, milestone_index: u32);
fn cancel_commission(commission_id: u256);
fn abandon_commission(commission_id: u256);
fn claim_creator_funds(commission_id: u256) -> u256;
fn claim_commissioner_refund(commission_id: u256) -> u256;

fn get_commission(commission_id: u256) -> Commission;
fn get_milestone(commission_id: u256, milestone_index: u32) -> Milestone;
fn commission_count() -> u256;
fn version() -> ByteArray;
```

The offer record is a standard ERC-721 surface (`token_uri` = the brief) with
transfers blocked in the hook.

Custom SRC5 interface ID:

```cairo
// starknet_keccak("mediolano.ip-commission-escrow")
IIP_COMMISSION_ESCROW_ID =
0x2732dc59dcc9ee3a818c88669f513e3b1b4bdd3717ea03ccff5059991314b51
```

## Development

```bash
cd contracts/IP-Commission-Escrow
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
