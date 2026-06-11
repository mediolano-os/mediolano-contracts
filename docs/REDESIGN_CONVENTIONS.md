# Service Redesign Conventions

**Status:** Working conventions for the one-by-one redesign of the contract
catalog. Established across the first three redesigns: IP-Subscription (#137),
IP-Tickets (#138), IP-Time-Capsule (#139).

Most contracts in this repository were written before the Mediolano
architecture principles existed. Each is being redesigned **one at a time**,
audit-first, against those principles. This document is the checklist so each
redesign doesn't re-derive the doctrine — and so review can diff a PR against
a known standard.

## Process

1. **Audit before redesign.** Read the existing implementation against the
   principles (`mediolano-core/docs/architecture/01-principles.md`). Record
   findings in a severity table at the top of the contract's
   `AUDIT_REPORT.md` (prepend a dated section; keep prior reports below for
   history). Every finding gets a resolution — including "documented,
   unchanged" with the reason.
2. **One contract per branch/PR.** Branch `redesign/<name>-v2` from `main`.
   Never bundle two contracts; never touch files outside the contract's
   directory (plus repo-level docs/CI when that is the explicit task).
3. **Verify before claiming.** `scarb fmt && scarb build && snforge test`
   green locally; CI re-runs the same for every changed contract directory.
4. **README carries the design — and is written AS PART OF the redesign.**
   Each redesign delivers a `README.md` in the contract directory: what the
   service is, a Service Asset Declaration table (per
   `docs/SERVICE_ASSET_DOCTRINE.md`), the interface, rules/semantics, a
   "Design (v2, dated)" section stating what changed and why, and build/test
   instructions. **Do not pre-write READMEs for contracts that have not been
   audited and redesigned yet** — documentation lands with the review that
   makes it trustworthy, one contract at a time.

## Contract checklist

### Authority
- [ ] **No contract owner, no admin, no upgrade path, no pause switch.** One
      shared immutable deployment serves all creators.
- [ ] **Creation is permissionless**; the creating caller is recorded on the
      record (`creator`) and is the only address with management rights over
      *that record*.
- [ ] **Management = sales switch only.** An `active` flag may gate *new
      payments* (subscribe/renew/mint). It must never affect what buyers
      already paid for: access, transfer, and redemption of existing assets
      survive deactivation.
- [ ] **Sold value is inviolable.** No code path — including the creator's —
      may shorten a paid period, revoke a sold asset, or reduce an
      `expires_at`/entitlement. If a function's only effect is forfeiting
      paid value (v1 `unsubscribe`), remove it.
- [ ] **Economic terms are immutable.** Price, duration, supply, royalty,
      token, recipient never change after creation; new terms = new record.

### Money
- [ ] **Zero fee in the contract.** Payments flow payer → record's
      recipient/creator directly via `transfer_from`; check the bool result.
- [ ] Free records: `price == 0` ⇔ `payment_token` is `None`. Paid records
      carry a non-zero token, validated at creation, so settlement may unwrap
      under that invariant (with a comment naming it).

### Safety
- [ ] **Checks-effects-interactions, no manual locks.** All storage writes
      precede every external call (`transfer_from`, `safe_mint`/receiver
      callbacks). Reentrant calls run under their own caller context against
      consistent state. Prove it with a test (malicious payment token, or a
      probing receiver that reads state inside the mint callback).
- [ ] **felt252 short-string asserts only** — no `panic!` ByteArray errors.
      Tests pin exact panic strings wherever the revert is deterministic.

### Data minimization
- [ ] **Derive, don't store.** Existence ⇔ `creator != 0` (creation rejects a
      zero caller). Revealed/active states derive from timestamps
      (`revealed_at != 0`, `expires_at >= now`). No `exists`/`status` flags,
      no record storing its own map key.
- [ ] **No on-chain enumeration structures** (rosters, per-user ID vectors,
      ERC721Enumerable). Indexers rebuild views from keyed events; data not
      held cannot be compelled.
- [ ] **Events carry history; storage carries the minimum present.** Values
      with no post-hoc on-chain utility (e.g. a verified commitment salt)
      live in events only.

### Interop & discovery
- [ ] Standard token interfaces; metadata URIs must be content-addressed
      (`ipfs://` or `ar://`).
- [ ] **SRC5 ID**: `starknet_keccak("mediolano.<service>.v2")`, derivation
      commented at the constant. New surface ⇒ new ID.
- [ ] Register every supported standard's interface ID (e.g. `IERC2981_ID`
      when royalties exist) and expose snake_case entry points (keep existing
      camelCase twins for compatibility; don't add new ones).
- [ ] Assets remain transferable by default; service-specific
      non-transferability must be justified by the service itself. If an
      asset can outlive its utility (redeemed ticket), say so loudly in the
      README and expose a validity getter for integrators.

### Boundaries & semantics
- [ ] Time boundaries are explicit and tested at the exact second (inclusive
      expiry for subscriptions, exclusive expiration for ticket series — keep
      each contract internally consistent and documented).
- [ ] Verbs are disjoint: one function starts, another extends; no function
      does both depending on hidden state.

### Toolchain
- [ ] `.tool-versions` pins `scarb` and `starknet-foundry` in the contract
      directory (CI reads it; baseline scarb 2.17.0 / snforge 0.59.0).
- [ ] OZ 0.20 empty hooks: `use openzeppelin::token::erc721::ERC721HooksEmptyImpl;`
      (import the impl — an alias `impl X = ...` fails to satisfy the trait).

## Deliberate non-goals

- **No shared helper package.** Each contract is a standalone Scarb project
  (independent audit scope, independent deploys). Duplicated 30-line helpers
  (`bytearray_starts_with`) are cheaper than coupling audit units.
- **No optimization without measurement.** Correctness redesigns don't carry
  eyeballed gas changes; storage-layout optimizations need before/after
  numbers from `snforge` gas reports in the PR.
- **No privacy cryptography in the substrate.** Commitments and timed reveals
  are in scope (IP-Time-Capsule); ZK entitlement proofs, viewing keys, and
  confidential amounts are commercial-layer concerns built *on top of* these
  primitives, never inside them.
