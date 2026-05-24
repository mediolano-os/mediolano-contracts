# IP Negotiation Escrow Audit And Remediation Report

**Date:** 2026-05-24
**Package:** `contracts/IP-Negotiation-Escrow`
**Scope:** `IPNegotiationEscrow.cairo`, interfaces, types, mock tokens, tests, manifest, and Mediolano first-principles service-asset design.
**Status:** First-principles audit completed; redesign implemented in the current working tree.

## Executive Summary

`IP-Negotiation-Escrow` has been rebuilt as a marketplace-native negotiation escrow protocol for existing IP assets.

The legacy contract was a thin order sketch. It created a seller order with a price and token ID, but did not store the buyer, did not distinguish funded from fulfilled state, did not provide a refund path, did not validate exact ERC-20 receipt, did not model deadlines, did not create a marketplace-visible service asset, and did not expose a custom SRC5 interface.

The redesigned implementation now supports:

- non-transferable ERC-721 negotiation listing assets;
- explicit references to an existing IP asset contract and token ID;
- one active negotiation per referenced IP asset;
- full buyer escrow funding before fulfillment;
- exact ERC-20 receipt validation;
- seller fulfillment proof submission through content-addressed metadata;
- buyer approval before seller payout;
- pull-based seller claims;
- pull-based buyer refunds for expired funded listings;
- content-addressed listing, terms, and fulfillment metadata;
- custom SRC5 service detection;
- keyed lifecycle events for indexers;
- adversarial ERC-20 coverage for short receipt and reentrant callback attempts.

## Service Asset Declaration

| Field | Value |
| --- | --- |
| `service_id` | `ip-negotiation-escrow` |
| `asset_standard` | ERC721 |
| `asset_role` | Non-transferable negotiation listing / escrow record for an existing IP asset |
| `transferability` | non-transferable |
| `access_semantics` | Listing state, buyer approval, seller claims, and buyer refunds derive from escrow records, not from transfer of the ERC-721 |
| `marketplace_visibility` | display/index as a negotiation listing asset; no default resale |
| `metadata_uri_policy` | listing, terms, and fulfillment URIs must be `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_NEGOTIATION_ESCROW_ID` |

The listing is assetized for discovery and marketplace display, but non-transferable because negotiation intent and escrow state should not become accidentally tradable inventory.

## Architecture Compliance

| Principle | Current Result |
| --- | --- |
| Smart contract is the protocol truth | Pass: listing, funding, fulfillment submission, approval, claims, refunds, and cancellation are contract state. |
| Asset-backed service visibility | Pass: each negotiation mints a non-transferable ERC-721 listing asset. |
| Transferability is explicit | Pass: the listing asset is non-transferable. |
| Protocol/app split | Pass: listing, terms, and fulfillment are content-addressed pointers; off-chain legal interpretation remains off-chain. |
| Agent/indexer readiness | Pass: custom SRC5 ID plus keyed lifecycle events. |
| No hidden authority | Pass: no admin, upgrade, pause, or arbitrary dispute resolver. |
| Marketplace semantics | Pass: display/index only; no default resale/listing surface for the service asset. |

## Remediated Findings

### Critical: No Marketplace Listing Asset

**Legacy issue:** The old escrow created storage records only. Marketplace/indexer discovery depended entirely on custom events and did not produce a service asset.

**Resolution:** `create_listing` mints a non-transferable ERC-721 listing asset to the seller. Token ID equals `negotiation_id`, and `token_uri` resolves to the content-addressed listing URI.

**Coverage:** `test_create_listing_mints_non_transferable_listing_asset`, `test_token_uri_and_src5`, `test_listing_asset_is_non_transferable`.

### Critical: Funding Did Not Create A Buyer-Bound Escrow State

**Legacy issue:** The old flow did not store the buyer or clearly separate open, funded, fulfilled, and cancelled states.

**Resolution:** `fund_listing` stores the buyer, records the exact escrowed amount, and moves the negotiation to `Funded`.

**Coverage:** `test_fund_listing_exact_escrow`, `test_seller_cannot_fund_own_listing`.

### High: No Buyer Approval Before Seller Payout

**Legacy issue:** Fulfillment and payment release were not modeled as a buyer-approved workflow.

**Resolution:** The seller submits a fulfillment pointer with `submit_fulfillment`, then the buyer must call `approve_fulfillment`. Only approval creates a seller claim.

**Coverage:** `test_submit_approve_and_seller_claim`, `test_only_seller_can_submit_fulfillment`, `test_only_buyer_can_approve_fulfillment`.

### High: No Refund Path

**Legacy issue:** Cancellation did not handle already-escrowed funds.

**Resolution:** A buyer can cancel an expired funded listing before fulfillment is submitted. Cancellation creates a pull refund claim through `claim_buyer_refund`.

**Coverage:** `test_expired_funded_listing_cancellation_refunds_buyer`, `test_cannot_cancel_after_fulfillment_submitted`.

### High: No Exact ERC-20 Receipt Validation

**Legacy issue:** Fee-on-transfer or malicious ERC-20 behavior could underfund the escrow while returning success.

**Resolution:** `fund_listing` compares the escrow contract's token balance before and after `transfer_from` and requires the exact delta to equal `price`.

**Coverage:** `test_fund_listing_exact_escrow`, `test_fund_rejects_short_erc20_receipt`.

### Medium: Duplicate Active Asset Listings Were Not Prevented

**Legacy issue:** Multiple active orders could reference the same IP asset without an explicit rule.

**Resolution:** `asset_to_negotiation` prevents a new listing for the same `(ip_asset_contract, ip_token_id)` while the existing negotiation is `Open`, `Funded`, or `FulfillmentSubmitted`.

**Coverage:** `test_create_rejects_duplicate_active_listing_for_asset`, `test_seller_can_cancel_open_listing_and_relist_asset`.

### Medium: Metadata Was Too Weak

**Legacy issue:** The old contract had no URI policy or hash commitments for listing terms and fulfillment proof.

**Resolution:** Listing, terms, and fulfillment URIs must be `ipfs://` or `ar://`, and each pointer has a non-zero hash commitment.

**Coverage:** `test_create_rejects_http_listing_uri`.

### Medium: Deadline Was Not Protocol-Bearing

**Legacy issue:** The old escrow had no meaningful expiration or late-cancellation behavior.

**Resolution:** Creation requires a future deadline. Funding and fulfillment submission must happen before the deadline. After an expired funded listing, the buyer can cancel and claim a refund if fulfillment has not been submitted.

**Coverage:** `test_create_rejects_expired_deadline`, `test_fund_rejects_expired_listing`, `test_submit_rejects_after_deadline`, `test_expired_funded_listing_cancellation_refunds_buyer`.

### Medium: External Token Calls Needed Adversarial Coverage

**Legacy issue:** Payment, claim, and refund paths were not tested against hostile ERC-20 behavior.

**Resolution:** Added a malicious ERC-20 mock that can short receipts and attempt reentrant claim/refund callbacks. The service-wide reentrancy guard blocks the tested callback paths.

**Coverage:** `test_claim_seller_funds_blocks_reentrant_token_callback`, `test_claim_buyer_refund_blocks_reentrant_token_callback`.

### Medium: No Custom Interface Discoverability

**Legacy issue:** The old contract did not register a custom SRC5 interface.

**Resolution:** The constructor registers `IIP_NEGOTIATION_ESCROW_ID`.

**Coverage:** `test_token_uri_and_src5`.

### Medium: Old Toolchain And Package Shape

**Legacy issue:** The package used stale dependency patterns and smoke tests that did not exercise protocol behavior.

**Resolution:** The package now uses:

- `starknet = "2.12.0"`
- `openzeppelin_introspection = "0.20.0"`
- `openzeppelin_token = "0.20.0"`
- `snforge_std = "0.59.0"`
- `assert_macros = "2.12.0"`

The stale smoke tests were replaced with 20 integration tests.

## Current Semantics

Listing creation:

```text
negotiation_id = last_negotiation_id + 1
token_id = negotiation_id
status = Open
```

Funding:

```text
caller != seller
status == Open
get_block_timestamp() <= deadline
escrow receipt == price
status = Funded
buyer = caller
```

Fulfillment submission:

```text
caller == seller
status == Funded
get_block_timestamp() <= deadline
fulfillment_uri is content-addressed
status = FulfillmentSubmitted
```

Approval:

```text
caller == buyer
status == FulfillmentSubmitted
seller claimable += price
status = Completed
```

Expired funded cancellation:

```text
caller == buyer
status == Funded
get_block_timestamp() > deadline
buyer refund = escrowed_amount - refunded_amount
status = Cancelled
```

## Verification

Commands run from `contracts/IP-Negotiation-Escrow`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-negotiation-escrow \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-negotiation-escrow \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-negotiation-escrow \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb test
```

Result:

```text
scarb build: passed
snforge test: 20 passed, 0 failed
```

## Remaining Notes

This contract intentionally does not transfer the referenced external IP asset. It anchors negotiation state and escrow settlement around that asset reference. Atomic external-asset settlement should be introduced through an explicit adapter or specialized version once the supported asset standards and license-transfer rules are defined.

Dispute arbitration is also intentionally absent. A future version could add mutually agreed cancellation, escrow mediation, or designated arbitration, but those roles should be explicit protocol actors rather than hidden admin powers.
