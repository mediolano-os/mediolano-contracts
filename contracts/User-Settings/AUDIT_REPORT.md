# User Settings Audit And Remediation Report

**Date:** 2026-05-24
**Package:** `contracts/User-Settings`
**Scope:** `UserSettingsRegistry.cairo`, interfaces, structs, tests, manifest, and Mediolano first-principles protocol design.
**Status:** First-principles audit completed; redesign implemented in the current working tree.

## Executive Summary

`User-Settings` has been rebuilt as a narrow on-chain public declarations registry for Mediolano.

The legacy `EncryptedPreferencesRegistry` attempted to store account profile fields, email, password hashes, API keys, notification preferences, network preferences, IP preferences, and self-asserted social verification data on-chain. That conflicted with a clean protocol/app split: profile and app credentials are platform-layer state, not protocol authority, and private values are never private once written to chain storage.

The redesigned implementation now keeps the protocol surface intentionally small:

- Any wallet can update its own public settings.
- No owner allowlist, app allowlist, or upgrade authority is present.
- No email, password, API key, social handle, notification preference, or network preference is stored.
- The only stored settings are public IP defaults plus an optional content-addressed pointer and hash commitment for an off-chain encrypted preferences blob.
- Settings are keyed by the caller wallet.
- Revisions are monotonic per wallet.
- Relayed writes are supported through an explicit signed path with nonce and deadline.
- Events are keyed for indexers.
- A custom SRC5 interface is registered for SDK and agent detection.
- A README now declares the service semantics and non-goals.

## Service Asset Declaration

| Field | Value |
| --- | --- |
| `service_id` | `user-settings` |
| `asset_standard` | none |
| `asset_role` | Public account settings/declarations record |
| `transferability` | not-applicable |
| `access_semantics` | Caller wallet controls its own record; relayed writes require account-contract signature validation; no private app preference grants protocol access |
| `marketplace_visibility` | hidden; index events for settings sync only |
| `metadata_uri_policy` | optional encrypted preferences pointer must be `ipfs://` or `ar://`, or empty with zero hash |
| `src5_interface_id` | `IUSER_SETTINGS_REGISTRY_ID` |

No ERC-721 or ERC-1155 asset is minted. User settings are not a market object, and assetizing them would violate the service-asset doctrine's separation between visibility and tradability.

## Architecture Compliance

| Principle | Current Result |
| --- | --- |
| Smart contract is the only truth | Pass: only intentional public declarations live on-chain; app/profile credentials stay off-chain. |
| Permissionless user control | Pass: any wallet can update its own record without owner/app allowlists; relayers can submit signed account intents. |
| Protocol/app split | Pass: email, passwords, API keys, notifications, and social handles were removed from protocol storage. |
| Identity model | Pass: wallet caller is the signer/owner; profile remains off-chain and non-authoritative. |
| Agent/indexer readiness | Pass: SRC5 interface registration and keyed lifecycle events. |
| Privacy posture | Pass: no secrets are stored; optional encrypted preferences are represented only by a content-addressed pointer and hash commitment. |
| Service-asset doctrine | Pass: `asset_standard: none`, event/index visibility only. |

## Remediated Findings

### Critical: Package Did Not Compile

**Legacy issue:** The old contract failed `scarb build` because OpenZeppelin component initialization did not match the package versions and the constructor assigned directly to storage fields.

**Resolution:** The package now uses the same baseline as the remediated services:

- `starknet = "2.12.0"`
- `openzeppelin_introspection = "0.20.0"`
- `snforge_std = "0.59.0"`
- `assert_macros = "2.12.0"`

The obsolete Ownable and Upgradeable components were removed.

### Critical: Users Could Not Update Their Own Settings

**Legacy issue:** Every write function required `authorized_apps[caller]`, and storage was keyed by `caller`. Only constructor-authorized addresses such as the owner or Mediolano app could write, and those writes updated the authorized caller's record rather than an end user's record.

**Resolution:** Writes now use `get_caller_address()` directly as the settings owner. Any wallet can call:

- `set_settings`
- `update_ip_defaults`
- `update_preferences_pointer`
- `clear_preferences_pointer`
- `delete_settings`

**Coverage:** `test_any_wallet_can_set_own_settings`, `test_settings_are_keyed_to_caller`, `test_zero_caller_rejected`.

### High: Relayed Writes Needed Explicit Account Authorization

**Legacy issue:** The old commented-out signature fields suggested relay support, but there was no user parameter, nonce, deadline, typed message hash, or account signature validation.

**Resolution:** `set_settings_for` is now the only relayed write path. It verifies:

- non-zero `user`;
- `deadline >= get_block_timestamp()`;
- supplied `nonce == nonces[user]`;
- `user.is_valid_signature(hash_settings_update(...), signature)` returns `VALID` or `1`;
- nonce increments before the relayed settings record becomes reusable.
- direct writes also increment `nonces[user]`, letting users invalidate pending relayed payloads.

**Coverage:** `test_relayer_can_set_settings_with_account_signature`, `test_relayer_rejects_replayed_nonce`, `test_direct_write_invalidates_pending_relay_signature`, `test_relayer_rejects_expired_signature`, `test_relayer_rejects_invalid_signature_hash`.

### Critical: Sensitive Data Was Publicly Stored

**Legacy issue:** The old contract stored email, password hash, API key, and social handles in public storage and exposed getters for them.

**Resolution:** Those fields and APIs were removed. The only optional off-chain data hook is `encrypted_preferences_uri` plus `encrypted_preferences_hash`; the URI must be content-addressed and the hash is a public commitment, not a secret.

**Coverage:** The new type surface contains no sensitive fields. Pointer validation is covered by `test_rejects_http_preferences_uri`, `test_empty_uri_requires_zero_hash`, and `test_non_empty_uri_requires_hash`.

### High: API Keys Were Deterministic And Public

**Legacy issue:** `regenerate_api_key` derived a key from public chain data and returned/stored it on-chain.

**Resolution:** API-key storage and regeneration were removed. API keys are app infrastructure and must stay off-chain.

### High: Social Verification Was Self-Asserted

**Legacy issue:** `store_X_verification` accepted a boolean but stored `is_verified: true` unconditionally, with no oracle, verifier, signed attestation, or challenge flow.

**Resolution:** Social verification was removed from this contract. If social attestations are needed later, that should be a separate signed-attestation or verifier-backed service.

### High: App/Profile State Was Stored As Protocol State

**Legacy issue:** Notification settings, username/email fields, network preferences, security fields, and app credentials were all written to chain storage.

**Resolution:** The new contract stores only public IP defaults and an optional encrypted settings pointer. App/profile state remains off-chain and non-authoritative.

### Medium: Timestamp Checks Had No Replay Protection

**Legacy issue:** `verify_settings_update` accepted timestamps within a five-minute window but did not use the recorded `users_last_updated` value to enforce monotonic updates.

**Resolution:** Direct caller-owned writes no longer accept timestamps. Each write increments a per-user revision stored in `revisions[user]`. Relayed writes use explicit `nonces[user]` and `deadline`.

**Coverage:** `test_update_ip_defaults_preserves_pointer`, `test_update_preferences_pointer`, `test_clear_preferences_pointer`, and `test_delete_settings_marks_record_inactive`.

### Medium: Password Hashing Was Inconsistent

**Legacy issue:** Store and update paths used different hash inputs for the password field.

**Resolution:** Password handling was removed from protocol scope.

### Medium: No Custom Interface Discoverability

**Legacy issue:** The old contract did not register a custom SRC5 interface.

**Resolution:** `UserSettingsRegistry` registers `IUSER_SETTINGS_REGISTRY_ID`.

**Coverage:** `test_supports_user_settings_interface`.

### Medium: Upgradeability Had No Governance Model

**Legacy issue:** The old contract embedded owner-controlled upgradeability without an explicit governance model.

**Resolution:** Upgradeability was removed. The registry is a simple immutable public-good primitive.

## Current Semantics

Settings exist when:

```text
settings[user].exists == true
```

The settings owner is always:

```text
get_caller_address()
```

for direct writes. Relayed writes use:

```text
set_settings_for(user, ..., nonce, deadline, signature)
```

and require:

```text
nonce == nonces[user]
get_block_timestamp() <= deadline
user.is_valid_signature(hash_settings_update(...), signature) == VALID || 1
```

Every successful direct write also increments `nonces[user]`, invalidating pending relayed payloads for that wallet.

An encrypted preferences pointer is valid only when:

```text
uri == "" && hash == 0
```

or:

```text
(uri starts with "ipfs://" || uri starts with "ar://") && hash != 0
```

No stored field should be interpreted as private, secret, or as authorization for protocol-bearing access.

## Verification

Commands run from `contracts/User-Settings`:

```bash
SCARB_CACHE=/private/tmp/scarb-cache-user-settings \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb fmt

SCARB_CACHE=/private/tmp/scarb-cache-user-settings \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb build

SCARB_CACHE=/private/tmp/scarb-cache-user-settings \
  /Users/kalamaha/.asdf/installs/scarb/2.17.0/bin/scarb test
```

Result:

```text
scarb build: passed
snforge test: 20 passed, 0 failed
```

## Remaining Notes

The `encrypted_preferences_uri` is only a pointer to off-chain encrypted data. The encryption key exchange, access policy, and app synchronization model must stay outside this contract unless a future protocol feature explicitly requires a public commitment.

The package/folder remains `User-Settings` for repository continuity, but the deployed contract and README use the more precise `UserSettingsRegistry` name.

## Production Recommendation

The redesigned implementation now matches the intended Mediolano first-principles architecture for this contract: no asset, no secrets, no profile authority, no app allowlist, and no upgrade hook. Before mainnet deployment, it should still receive external security review and integration review.
