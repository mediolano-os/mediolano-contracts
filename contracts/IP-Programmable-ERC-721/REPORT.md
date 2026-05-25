# IP-Programmable-ERC-721 — Audit, Refactor & Deployment Report

**Date:** 2026-04-13
**Review Addendum:** 2026-05-25
**Auditor/Developer:** Claude Sonnet 4.6 (Anthropic) + Medialane team
**Network:** Starknet Mainnet

---

## Overview

`IP-Programmable-ERC-721` is a standalone, permissionless, immutable ERC-721 provenance contract for the Mediolano platform. Any user can deploy their own collection instance and any address can mint into it with their own IPFS/Arweave metadata. No address holds privileged power after deployment.

Architecture note from the 2026-05-25 review: this package should be treated as the standalone `ip-erc721` genesis/shared service. The folder keeps its historical `IP-Programmable-ERC-721` name, but the current contract is intentionally narrow: immutable ERC-721 minting plus IP provenance. It is not the primary template for new Medialane collection protocols, which should align with `MIP-Collections-ERC721` and the newer collaborative collection architecture.

---

## 2026-05-25 Review Addendum

### Findings Addressed
| Severity | Finding | Resolution |
|---|---|---|
| High | `mint_item(recipient, token_uri)` allowed caller A to mint to recipient B while recording B as `original_creator`, creating false authorship records. | `original_creator` now records `get_caller_address()` and keeps `recipient` as the token owner/custody address. |
| Medium | The custom IP helper surface was not discoverable through SRC5. | Added `IIP_COLLECTION_ID` and registered it in the constructor. |
| Medium | `snforge_std = "0.58.0"` was incompatible with the current local snforge runner. | Updated dev dependency to `snforge_std = "0.59.0"`. |
| Low | Docs implied this standalone contract was equivalent to the newer collection architecture. | README and report now clarify that new collection protocols should use the MIP/collaborative collection design. |
| Low | Constructor parameter was named `owner`, implying admin authority where none exists. | Renamed the parameter to `collection_creator` and clarified that it is informational only. |

### Additional Tests Added
| Test | Purpose |
|---|---|
| `test_mint_records_caller_as_creator_when_recipient_differs` | Verifies creator provenance follows the mint caller, not the recipient. |
| `test_supports_interface_ip_collection` | Verifies SRC5 discovery for `IIP_COLLECTION_ID`. |

---

## Refactor Summary

The contract was fully rewritten from a legacy, overcomplicated state to a minimal, production-grade implementation. Key changes:

### Removed
| Item | Reason |
|---|---|
| `AccessControlComponent` | No purpose — contract is permissionless by design |
| `UpgradeableComponent` | Upgradeability is a legal and security risk for immutable IP records |
| `OwnableComponent` | No admin functions exist; removed to eliminate misleading surface area |
| `base_uri` constructor param | Dead data — per-token URIs are stored in full; concatenation never used |
| `MIP.cairo`, `MIPL.cairo` | Redundant legacy files |
| `src/components/Counter.cairo` | Replaced by internal `next_token_id` storage slot |
| `src/components/ERC721Enumerable.cairo` | Replaced by OZ v0.20.0 `ERC721EnumerableComponent` |
| `src/dev/` (4 files) | Development scratch files, not production code |
| `src/test/MIPTest.cairo` | Replaced by comprehensive `src/tests/IPCollectionTest.cairo` |

### Added / Changed
| Item | Detail |
|---|---|
| OpenZeppelin upgrade | v0.17.0 → v0.20.0 (bundle-style imports) |
| snforge_std upgrade | 0.31.0 → 0.59.0 |
| Starknet version | Pinned to 2.12.0 |
| `safe_mint` | Replaces `mint` — reverts if recipient contract doesn't implement IERC721Receiver or ISRC6, preventing token lockup |
| IP provenance storage | `token_creators: Map<u256, ContractAddress>` and `token_registered_at: Map<u256, u64>` — written once at mint, never modified |
| `IPMinted` event | Emitted on every mint with `token_id`, `recipient`, `uri`, caller `creator`, `registered_at` |
| `get_token_data()` | Returns all provenance fields in one call (avoids multiple cross-contract calls) |
| `collection_creator` | Informational-only slot recording the declared collection creator (no admin power) |
| `IIP_COLLECTION_ID` | SRC5 interface ID for the IP collection helper ABI |
| `MockAccount.cairo` | Test helper that registers `ISRC6_ID` via SRC5, simulating a real Starknet user wallet for `safe_mint` tests |
| `Receiver.cairo` | Simplified to use OZ `ERC721ReceiverImpl` directly |
| Edition `2024_07` | Updated Cairo edition |

### Dependency Versions (final)
```toml
starknet = "2.12.0"
openzeppelin = { git = "...", tag = "v0.20.0" }
snforge_std = "0.59.0"  # [dev-dependency]
assert_macros = "2.12.0"  # [dev-dependency]
```

---

## Security Review

### Trust Model
- **No owner, no admin, no upgradeability.** The contract is fully trust-minimized.
- `collection_creator` is a read-only informational slot — it has zero on-chain power.
- The constructor accepts `collection_creator` explicitly instead of deriving it from `get_caller_address()`, preserving delegated and factory deployment flows.
- Token ID counter (`next_token_id`) is internal and never externally exposed.

### Safe Mint
`safe_mint` is used instead of `mint`. On Starknet (account abstraction), every user is a deployed contract. `_check_on_erc721_received` in OZ v0.20.0 checks:
1. `IERC721_RECEIVER_ID` — ERC721Receiver contracts
2. `ISRC6_ID` — Starknet account wallets

This prevents tokens being permanently locked in contracts that can never transfer them.

### IP Provenance (Berne Convention)
`token_creators` and `token_registered_at` are written once at mint and are structurally immutable — no setter exists. `token_creators` records the caller of `mint_item`, not the recipient, so delegation/custody mints cannot falsely assign authorship to the receiving address. This satisfies the Berne Convention authorship record requirement for 181-country IP protection.

### URI Validation
The contract validates that `token_uri` starts with `ipfs://` or `ar://`. This ensures all on-chain IP records point to content-addressed, censorship-resistant storage. The frontend normalizes bare IPFS CIDs (e.g. `Qm...`) to the `ipfs://` scheme before calling `mint_item`.

### No Identified Critical Issues
- No reentrancy vectors (Cairo's single-threaded execution model)
- No integer overflow (Cairo 2 native bounds checking)
- No access control bypass (none exists to bypass)
- No token lockup risk (safe_mint guards against this)

---

## Test Results

**42 tests, 42 passed, 0 failed**

```
snforge test — ip_programmable_erc_721
```

### Test Coverage
| Category | Tests |
|---|---|
| Deployment | `test_deploy_succeeds`, `test_name_and_symbol`, `test_initial_total_supply_is_zero` |
| Collection creator | `test_collection_creator_is_set` |
| Mint — happy path | `test_mint_ipfs_uri_returns_token_id_one`, `test_mint_ar_uri_returns_token_id_one`, `test_mint_sequential_ids`, `test_mint_owner_of`, `test_mint_balance_increments` |
| Mint — URI validation | `test_mint_http_uri_rejected`, `test_mint_empty_uri_rejected`, `test_mint_partial_ipfs_prefix_rejected` |
| Mint — zero address | `test_mint_zero_recipient_panics` |
| Mint — safe_mint | `test_mint_to_mock_account_succeeds`, `test_mint_to_erc721_receiver_succeeds`, `test_mint_to_non_receiver_contract_rejected` |
| IP provenance | `test_mint_records_caller_as_creator`, `test_mint_records_caller_as_creator_when_recipient_differs`, `test_mint_registered_at_matches_block_timestamp`, `test_get_token_data_all_fields_correct` |
| Token URI | `test_mint_token_uri_exact_no_concatenation`, `test_mint_token_uri_camel_matches_snake` |
| Enumerable | `test_mint_enumerable_total_supply`, `test_mint_enumerable_token_by_index`, `test_mint_enumerable_token_of_owner_by_index`, `test_transfer_enumerable_updates` |
| Transfer | `test_transfer_updates_owner`, `test_transfer_updates_balances`, `test_transfer_preserves_creator`, `test_transfer_preserves_uri` |
| Interfaces | `test_supports_interface_erc721`, `test_supports_interface_erc721_enumerable`, `test_supports_interface_ip_collection` |
| Error paths | `test_token_uri_nonexistent_panics`, `test_get_token_creator_nonexistent_panics`, `test_get_token_registered_at_nonexistent_panics`, `test_get_token_data_nonexistent_panics` |
| Types unit tests | `test_bytearray_starts_with_ipfs`, `test_bytearray_starts_with_ar`, `test_bytearray_starts_with_http_fails`, `test_bytearray_starts_with_shorter_than_needle` |

---

## Deployments

### Class (shared by all instances)

| Field | Value |
|---|---|
| Class Hash | `0x1bd7e39c5135b32b664e34cbbb4eafbd707a0fbc3ec2ef28657f52577d277d7` |
| Declare Tx | `0x1eb4c9e35be6b90158b867b1b3ebdbe90da9e698f3a3d2132aba1cecf1671bf` |
| Declared by | `mediolano-deployer` (`0x2200854036a91e6aad4764ace3feec9b2e2408925ae426563f273e1854ce80c`) |
| Explorer | https://voyager.online/class/0x01bd7e39c5135b32b664e34cbbb4eafbd707a0fbc3ec2ef28657f52577d277d7 |

### Instance 1 — MIP (Medialane Genesis)

| Field | Value |
|---|---|
| Contract Address | `0x06ed61abba98a44d45bed2c4b1a456df15053c3321cfd6e007afb33b7226c9f0` |
| Name | `MIP` |
| Symbol | `MIP` |
| Collection Creator | `0x2200854036a91e6aad4764ace3feec9b2e2408925ae426563f273e1854ce80c` |
| Deploy Tx | `0x059fc619e70ea3658c29616bb652523be1ff721c7f6df0d246a40dae12523299` |
| First Token Minted | Token #1 — `ipfs://bafkreiag6wzov7migmxwx3wrtudvbx4ajrlbjopqw7uni7nn2nsxv4eykm` |
| Explorer | https://voyager.online/contract/0x06ed61abba98a44d45bed2c4b1a456df15053c3321cfd6e007afb33b7226c9f0 |
| Used by | `medialane-io` genesis mint — `NEXT_PUBLIC_LAUNCH_MINT_CONTRACT` |

### Instance 2 — GMBR (Genesis Mint BR)

| Field | Value |
|---|---|
| Contract Address | `0x01f8b92e3b9e963b8eacb075207e2cc89d4614ff2ac6c2702c7ae10ad19a9db8` |
| Name | `Genesis Mint BR` |
| Symbol | `GMBR` |
| Collection Creator | `0x2200854036a91e6aad4764ace3feec9b2e2408925ae426563f273e1854ce80c` |
| Deploy Tx | `0x039bfa0d5edd4054cc201a8d22acb7e887771acad068a4d8de82ef25709e5d14` |
| First Token Minted | Token #1 — `ipfs://QmSNU3sXwV7168T9Pmtf9gEr2Ri2Q8mypH4n3gbr2EW4YG` |
| Explorer | https://voyager.online/contract/0x01f8b92e3b9e963b8eacb075207e2cc89d4614ff2ac6c2702c7ae10ad19a9db8 |
| Used by | `medialane-io` BR event mint — `NEXT_PUBLIC_BR_MINT_CONTRACT` |

### Deploying Additional Collections

The declared class can be reused indefinitely — no redeclaration needed:

```bash
cd contracts/IP-Programmable-ERC-721
sncast deploy \
  --class-hash 0x1bd7e39c5135b32b664e34cbbb4eafbd707a0fbc3ec2ef28657f52577d277d7 \
  --arguments '"Collection Name","SYMBOL",0x<collection_creator_address>'
```

---

## Frontend Integration

The contract is integrated into `medialane-io`. Key notes:

- Entrypoint: `mint_item(recipient: ContractAddress, token_uri: ByteArray) -> u256`
- Calldata: `[recipient_address, ...bytearray_encoded_uri]`
- The frontend normalizes bare IPFS CIDs to `ipfs://` scheme before encoding
- Gas is sponsored via Chipi (Starknet session keys)
- The `NEXT_PUBLIC_GENESIS_NFT_URI` and `NEXT_PUBLIC_BR_NFT_URI` env vars accept both bare CIDs and full `ipfs://` URIs
