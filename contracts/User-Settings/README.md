# User Settings Registry

`UserSettingsRegistry` is a minimal public declarations contract for Mediolano account settings.

It is not a profile database, password store, API-key store, social-verification oracle, or marketplace asset contract.

## Service Declaration

| Field | Value |
| --- | --- |
| `service_id` | `user-settings` |
| `asset_standard` | none |
| `asset_role` | Public account settings/declarations record |
| `transferability` | not-applicable |
| `access_semantics` | Caller wallet controls its own record; relayed writes require the account contract to validate a signature |
| `marketplace_visibility` | hidden; index events for settings sync only |
| `metadata_uri_policy` | optional encrypted preferences pointer must be `ipfs://` or `ar://`, or empty with zero hash |
| `src5_interface_id` | `IUSER_SETTINGS_REGISTRY_ID` |

## Stored State

The contract stores only:

- default IP protection level;
- automatic IP registration preference;
- optional encrypted preferences URI;
- optional encrypted preferences hash commitment;
- per-wallet revision;
- per-wallet relay nonce.

The URI and hash are public. The URI may point to encrypted off-chain data, but the contract does not encrypt, decrypt, authorize, or hide that data.

## Write Paths

`set_settings`, `update_ip_defaults`, `update_preferences_pointer`, `clear_preferences_pointer`, and `delete_settings` are direct wallet writes. The caller is always the settings owner.

`set_settings_for` is the explicit relayed write path. It requires:

- target `user`;
- current `nonce`;
- `deadline`;
- account-contract signature over `hash_settings_update(...)`;
- `user.is_valid_signature(hash, signature)` returning `VALID` or `1`.

Every direct write also increments the relay nonce. This lets a wallet invalidate pending signed relay payloads by submitting any fresh direct update.

## Non-Goals

- No ERC-721/ERC-1155 asset is minted.
- No profile, email, notification, API-key, password, or social-verification data is stored.
- No setting in this contract grants protocol-bearing access by itself.
- No owner, admin, allowlist, or upgrade hook exists.

Custom SRC5 interface ID:

```cairo
pub const IUSER_SETTINGS_REGISTRY_ID: felt252 =
    0x0204179c15f947088fc3173f05d6f0f8db3fd935f248d535a669f2cbe3c68f6d;
```
