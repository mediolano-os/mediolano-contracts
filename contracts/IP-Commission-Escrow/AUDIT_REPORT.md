# IP Commission Escrow Audit And Remediation Report

**Date:** 2026-05-24
**Package:** `contracts/IP-Commission-Escrow`
**Scope:** `IPCommissionEscrow.cairo`, interfaces, types, mock token, tests, manifest, and Mediolano first-principles service-asset design.
**Status:** First-principles audit completed; redesign implemented in the current working tree.

## Executive Summary

`IP-Commission-Escrow` has been rebuilt as a marketplace-native commission-offer escrow protocol.

The legacy contract supported a single paid order with one supplier and two `felt252` metadata fields. It did not model open versus exclusive offers, milestone payments, revision cycles, license pointers, marketplace offer assets, pull claims, or service discoverability.

The redesigned implementation now supports:

- non-transferable ERC-721 commission offer assets;
- open offers and exclusive invited-creator offers;
- full escrow funding before acceptance;
- deadline enforcement for creation, acceptance, and delivery submission;
- milestone schedules whose amounts must sum to the commission total;
- creator milestone submission with content-addressed deliverable pointers;
- commissioner revision requests up to a declared revision limit;
- commissioner milestone approval;
- pull-based creator claims for approved milestones;
- pull-based commissioner refunds for pre-acceptance cancellation;
- missed-deadline cancellation that refunds only unreleased escrow;
- content-addressed brief, license, and deliverable metadata;
- custom SRC5 service detection;
- keyed lifecycle events for indexers.

## Service Asset Declaration

| Field | Value |
| --- | --- |
| `service_id` | `ip-commission-escrow` |
| `asset_standard` | ERC721 |
| `asset_role` | Non-transferable commission offer / escrow record |
| `transferability` | non-transferable |
| `access_semantics` | Commission state, milestone approval, creator claims, and commissioner refunds derive from escrow records, not from transfer of the ERC-721 |
| `marketplace_visibility` | display/index as an offer asset; no default listing or resale |
| `metadata_uri_policy` | brief, license, and deliverable URIs must be `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_COMMISSION_ESCROW_ID` |

The offer is assetized for discovery and marketplace display, but non-transferable because a commission intent should not become an accidentally tradable object.

## Architecture Compliance

| Principle | Current Result |
| --- | --- |
| Smart contract is the protocol truth | Pass: funding, acceptance, milestones, revisions, approvals, claims, and refunds are contract state. |
| Asset-backed service visibility | Pass: each commission mints a non-transferable ERC-721 offer asset. |
| Transferability is explicit | Pass: the offer asset is non-transferable. |
| Protocol/app split | Pass: briefs, license terms, and deliverables are content-addressed pointers; creative review remains off-chain. |
| Agent/indexer readiness | Pass: custom SRC5 ID plus keyed lifecycle events. |
| No hidden authority | Pass: no admin, upgrade, pause, or arbitrary dispute resolver. |
| Marketplace semantics | Pass: display/index only; no default resale/listing surface. |

## Remediated Findings

### Critical: No Marketplace Offer Asset

**Legacy issue:** The old escrow created storage records only. Marketplace/indexer discovery depended entirely on custom events and did not produce an asset for the commission offer.

**Resolution:** `create_commission` mints a non-transferable ERC-721 offer asset to the commissioner. Token ID equals `commission_id`, and `token_uri` resolves to the content-addressed brief URI.

**Coverage:** `test_create_open_commission_mints_offer_asset`, `test_token_uri_and_src5`, `test_offer_asset_is_non_transferable`.

### High: No Milestone Model

**Legacy issue:** The old contract had a single amount and one completion action.

**Resolution:** Commission creation now requires milestone amounts that sum exactly to `total_amount`. The creator submits milestones in order, and the commissioner approves each milestone independently.

**Coverage:** `test_completion_after_all_milestones_approved`, `test_submit_requires_previous_milestone_approved`, `test_create_rejects_milestone_sum_mismatch`.

### High: No Revision Loop

**Legacy issue:** Creative commission workflows commonly include allowed revisions, but the old contract had no revision state.

**Resolution:** `request_revision` moves a submitted milestone back to `RevisionRequested` and increments `revision_count`, bounded by `revisions_allowed`.

**Coverage:** `test_revision_flow`, `test_revision_limit_enforced`.

### High: No Exclusive Offer Semantics

**Legacy issue:** The old supplier field was fixed at order creation and did not distinguish a general marketplace offer from an offer directed to one account.

**Resolution:** `invited_creator == 0` creates an open offer. A non-zero invited creator creates an exclusive offer accepted only by that account.

**Coverage:** `test_exclusive_commission_accepts_invited_creator`, `test_exclusive_commission_rejects_other_creator`.

### High: Push Payment On Completion

**Legacy issue:** Completion immediately pushed funds to the supplier.

**Resolution:** Approved milestone amounts become pull claims for the creator. This keeps approval/accounting separate from the external ERC-20 transfer.

**Coverage:** `test_open_commission_accept_submit_approve_and_claim`.

### High: Cancellation Needed Pull Refunds

**Legacy issue:** Cancellation existed only before payment and did not model escrowed refunds.

**Resolution:** A commissioner can cancel while `Open` or `Funded`. Funded cancellation creates a pull refund claim. Post-acceptance unilateral cancellation is allowed only after the declared deadline, and only unreleased escrow is refundable.

**Coverage:** `test_cancel_funded_commission_and_claim_refund`, `test_cannot_cancel_in_progress_commission`, `test_expired_in_progress_cancellation_refunds_unreleased_amount`.

### Medium: Metadata Was Too Weak

**Legacy issue:** Brief and license data were `felt252` values with no URI policy.

**Resolution:** Brief, license, and deliverable URIs must be `ipfs://` or `ar://`, and each pointer has a non-zero hash commitment.

**Coverage:** `test_create_rejects_http_brief_uri`.

### Medium: ERC-20 Receipt Was Not Validated

**Legacy issue:** The old payment flow checked balance and ERC-20 return value but did not validate exact receipt.

**Resolution:** `fund_commission` compares the escrow contract's token balance before and after `transfer_from` and requires the exact delta to equal `total_amount`.

**Coverage:** `test_fund_commission_exact_escrow`, `test_fund_commission_rejects_short_erc20_receipt`.

### Medium: Deadline Had To Become Protocol-Bearing

**Legacy issue:** The legacy escrow did not model a meaningful creative-work timeline.

**Resolution:** Creation requires a future deadline. Acceptance and milestone submission must occur before that deadline. If an in-progress commission misses the deadline, the commissioner can cancel and recover unreleased funds while approved creator claims remain intact.

**Coverage:** `test_create_rejects_expired_deadline`, `test_accept_rejects_expired_offer`, `test_submit_rejects_after_deadline`, `test_expired_in_progress_cancellation_refunds_unreleased_amount`.

### Medium: External Token Calls Needed Adversarial Coverage

**Legacy issue:** Payment and refund paths were not tested against callback-style token behavior.

**Resolution:** Added a malicious ERC-20 mock that can short receipts and attempt reentrant claim/refund callbacks. The service-wide reentrancy guard blocks the tested callback paths.

**Coverage:** `test_claim_creator_funds_blocks_reentrant_token_callback`, `test_claim_commissioner_refund_blocks_reentrant_token_callback`.

### Medium: No Custom Interface Discoverability

**Legacy issue:** The old contract did not register a custom SRC5 interface.

**Resolution:** The constructor registers `IIP_COMMISSION_ESCROW_ID`.

**Coverage:** `test_token_uri_and_src5`.

### Medium: Old Toolchain And Package Identity

**Legacy issue:** The package was named `ip_smart_transaction`, used older dependencies, and pinned older tooling.

**Resolution:** The package is now `ip_commission_escrow` and uses:

- `starknet = "2.12.0"`
- `openzeppelin_introspection = "0.20.0"`
- `openzeppelin_token = "0.20.0"`
- `snforge_std = "0.59.0"`
- `assert_macros = "2.12.0"`

## Current Semantics

Commission creation:

```text
commission_id = last_commission_id + 1
token_id = commission_id
status = Open
```

Funding:

```text
caller == commissioner
status == Open
escrow receipt == total_amount
status = Funded
```

Acceptance:

```text
status == Funded
get_block_timestamp() <= deadline
open offer: caller != commissioner
exclusive offer: caller == invited_creator
status = InProgress
```

Milestone submission:

```text
caller == creator
status == InProgress
get_block_timestamp() <= deadline
previous milestone approved, if any
milestone status is Pending or RevisionRequested
```

Milestone approval:

```text
caller == commissioner
milestone status == Submitted
creator claimable += milestone amount
```

Completion:

```text
approved_milestone_count == milestone_count
status = Completed
```

Missed-deadline cancellation:

```text
caller == commissioner
status == InProgress
get_block_timestamp() > deadline
commissioner refund = escrowed_amount - released_amount - refunded_amount
approved creator claims remain claimable
```

## Verification

Commands run from `contracts/IP-Commission-Escrow`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-commission-escrow \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-commission-escrow \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-commission-escrow \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb test
```

Result:

```text
scarb build: passed
snforge test: 23 passed, 0 failed
```

## Remaining Notes

This contract intentionally does not include dispute arbitration. A future version could add mutually agreed cancellation, third-party arbitration, or DAO/provider mediation, but those should be explicit protocol roles rather than hidden admin powers.

Copyright transfer is not inferred from payment. The license pointer declares usage rights for off-chain legal/workflow interpretation.
