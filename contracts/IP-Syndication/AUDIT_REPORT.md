# IP Syndication Audit And Remediation Report

**Date:** 2026-05-24
**Package:** `contracts/IP-Syndication`
**Scope:** `IPSyndication.cairo`, interfaces, types, mocks, tests, manifest, and Mediolano first-principles service-asset design.
**Status:** First-principles audit completed; redesign implemented in the current working tree.

## Executive Summary

`IP-Syndication` has been rebuilt as a single ERC-1155-backed Mediolano service contract.

The legacy package split syndication logic from an external `AssetNFT` contract, but the external asset minter was not permissioned to the syndication manager. That meant any caller could mint arbitrary syndication shares. The legacy deposit/refund path also ignored ERC-20 return values, used push refunds over an unbounded participant list, and did not expose a creator proceeds claim path.

The redesigned implementation now makes the asset and service semantics explicit:

- `IPSyndication` embeds OpenZeppelin ERC-1155 directly.
- Token ID equals `ip_id`.
- Each participant can mint its funded share once after completion.
- Shares are transferable ERC-1155 assets for marketplace visibility.
- Refund rights stay with the original participant record.
- Creator proceeds are claimable once by the IP owner.
- Cancellation uses pull refunds.
- A single service-wide reentrancy guard covers token transfers and ERC-1155 receiver hooks.
- Deposits validate exact ERC-20 receipt by comparing before/after contract balances.
- Participant reads support pagination for indexers.
- IP metadata must be content-addressed with `ipfs://` or `ar://`.
- A custom SRC5 interface is registered for SDK and agent detection.
- Lifecycle events are keyed for indexers.
- The package uses the current Cairo/OpenZeppelin/SnForge baseline used by the remediated services.

## Service Asset Declaration

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

This follows the service-asset doctrine: the asset is indexable and tradable because syndication shares are intentionally market-facing. The contract still separates asset transfer from internal accounting rights.

## Architecture Compliance

| Principle | Current Result |
| --- | --- |
| Smart contract is the only protocol truth | Pass: syndication status, deposits, refunds, proceeds, and share minting are contract state. |
| Asset-backed service visibility | Pass: completed participation can mint ERC-1155 shares under the same contract. |
| Transferability is explicit | Pass: ERC-1155 shares transfer, while refund/proceeds claims remain record-bound. |
| Protocol/app split | Pass: metadata is a content-addressed pointer; no off-chain license enforcement or private data is embedded. |
| Agent/indexer readiness | Pass: custom SRC5 ID plus keyed lifecycle events. |
| No hidden authority | Pass: no admin, upgrade, pause, force-cancel, or privileged mint path. |
| Marketplace semantics | Pass: shares are intentionally transferable and visible after mint. |

## Remediated Findings

### Critical: Unrestricted Asset Minting

**Legacy issue:** `AssetNFT.mint` was publicly callable and not restricted to the syndication manager. Any address could mint arbitrary shares for any token ID.

**Resolution:** The separate asset contract was removed. `IPSyndication` embeds ERC-1155 and exposes only `mint_asset(ip_id)`, which requires:

- syndication status is `Completed`;
- caller is an original participant;
- caller has not minted before;
- minted amount equals the caller's funded share.

**Coverage:** `test_mint_asset_after_completion`, `test_mint_asset_only_once`, `test_mint_asset_to_receiver_contract`.

### High: ERC-20 Transfer Results Were Ignored

**Legacy issue:** Deposit and refund flows called ERC-20 transfers without asserting the returned success value.

**Resolution:** `deposit`, `claim_refund`, and `claim_proceeds` assert `true` return values from ERC-20 transfer calls and revert on failure.

**Coverage:** Core deposit, refund, and proceeds tests exercise successful transfer accounting.

### High: Short ERC-20 Receipts Could Overcredit Participants

**Legacy issue:** A non-standard ERC-20 could return success while delivering fewer tokens than the credited deposit amount.

**Resolution:** `deposit` now records the syndication contract's payment-token balance before and after `transfer_from` and requires the exact delta to equal the credited deposit amount.

**Coverage:** `test_deposit_rejects_short_transfer_from_receipt`.

### High: Cross-Function Reentrancy Needed One Mental Model

**Legacy issue:** Separate operation-specific guards made the reentrancy surface harder to audit across ERC-20 calls and ERC-1155 receiver hooks.

**Resolution:** `deposit`, `claim_refund`, `claim_proceeds`, and `mint_asset` now use one service-wide reentrancy guard.

**Coverage:** `test_deposit_blocks_reentrant_token_callback`, `test_claim_refund_blocks_reentrant_token_callback`, `test_claim_proceeds_blocks_reentrant_token_callback`, `test_mint_asset_blocks_reentrant_receiver_callback`.

### High: Push Refunds Could Revert Or Run Out Of Gas

**Legacy issue:** Cancellation iterated over all participants and pushed refunds. A large participant set or a failing receiver/token path could block cancellation.

**Resolution:** `cancel_syndication` only changes status to `Cancelled`. Each participant independently calls `claim_refund`.

**Coverage:** `test_cancel_and_pull_refund`, `test_cancel_rejects_completed_syndication`.

### High: Creator Proceeds Had No Claim Path

**Legacy issue:** Completed fundraising left funds in the contract without a clear owner withdrawal path.

**Resolution:** `claim_proceeds` lets the IP owner withdraw the completed total exactly once.

**Coverage:** `test_claim_proceeds_after_completion`, `test_claim_proceeds_only_once`.

### High: Asset Semantics Were Ambiguous

**Legacy issue:** Syndication records and ERC-1155 shares were split across contracts, with no explicit statement about what a transferred share controls.

**Resolution:** The README and implementation define the ERC-1155 token as a transferable visible share asset. Refunds and proceeds remain bound to internal records.

**Coverage:** `test_erc1155_share_is_transferable`.

### Medium: Metadata URI Accepted Arbitrary Strings

**Legacy issue:** Metadata strings could be non-content-addressed HTTP URLs or mutable pointers.

**Resolution:** `register_ip` accepts only `ipfs://` or `ar://` metadata URIs. The same pointer is exposed as the ERC-1155 token URI for `ip_id`.

**Coverage:** `test_register_accepts_ar_uri`, `test_register_rejects_http_uri`, `test_token_uri_and_src5`.

### Medium: No Custom Interface Discoverability

**Legacy issue:** The contract did not expose a custom SRC5 interface ID for service discovery.

**Resolution:** The constructor registers `IIP_SYNDICATION_ID`.

**Coverage:** `test_token_uri_and_src5`.

### Medium: Old Toolchain And Dependencies

**Legacy issue:** The package pinned an older toolchain and depended on legacy OpenZeppelin git packages that no longer built cleanly in this environment.

**Resolution:** The package now uses:

- `starknet = "2.12.0"`
- `openzeppelin_introspection = "0.20.0"`
- `openzeppelin_token = "0.20.0"`
- `snforge_std = "0.59.0"`
- `assert_macros = "2.12.0"`

### Medium: Whitelist Rules Needed A Narrow State Model

**Legacy issue:** Whitelist behavior was mixed into the old lifecycle without a crisp service declaration.

**Resolution:** Whitelist mode is explicit. Only the IP owner can update whitelist entries, only while pending or active, and deposits in whitelist mode require an active whitelist entry.

**Coverage:** `test_whitelist_mode_deposit`, `test_whitelist_mode_rejects_non_whitelisted_deposit`.

### Low: Participant Enumeration Needed Pagination

**Legacy issue:** `get_all_participants` is useful for small syndications but not ideal for larger indexer reads.

**Resolution:** Added `get_participants(ip_id, start, limit)` while keeping `get_all_participants(ip_id)` as a convenience wrapper.

**Coverage:** `test_get_participants_paginates_results`.

## Current Semantics

Registering an IP creates:

```text
ip_id = last_ip_id + 1
token_id = ip_id
status = Pending
```

Deposits are allowed only while:

```text
status == Active
```

Completion occurs when:

```text
total_raised == target_amount
```

Mintable share amount is:

```text
amount_deposited - amount_refunded
```

Refunds are claimable only when:

```text
status == Cancelled
```

Creator proceeds are claimable only when:

```text
status == Completed
proceeds_claimed == false
caller == ip_owner
```

## Verification

Commands run from `contracts/IP-Syndication`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-ip-syndication \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-ip-syndication \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-ip-syndication \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb test
```

Result:

```text
scarb build: passed
snforge test: 28 passed, 0 failed
```

## Remaining Notes

The current implementation rejects short ERC-20 receipts and blocks tested callback reentrancy paths. Rebasing or otherwise unusual payment tokens should still be disallowed by deployment policy or handled by a future token adapter.

ERC-1155 shares are intentionally transferable. A future service that wants transferable proceeds rights should model those rights explicitly instead of inferring them from the share balance.
