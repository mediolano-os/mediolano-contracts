# IP-Time-Capsule

Permissionless ERC-721 service for time-locked IP disclosure on Starknet.

An IP Time Capsule lets a creator mint an NFT now while keeping the revealed IP metadata unavailable until a future `reveal_at` timestamp. The contract records a content-addressed encrypted payload pointer and a content commitment at mint time. After the unlock time, the creator or current token owner can reveal the final content-addressed metadata URI.

This service follows the Medialane architecture principles: the contract is the source of truth, minting is permissionless, assets remain standard ERC-721 NFTs, and the time-lock is explicit service-level enforcement.

---

## Architecture

- **Permissionless mint.** Any caller can mint a capsule to any non-zero recipient.
- **Immutable service.** No owner, no admin, no upgradeability, no fee logic.
- **Safe mint.** Uses OpenZeppelin `safe_mint` to avoid locking NFTs in non-receiver contracts.
- **Hidden token URI.** `token_uri` returns a shared hidden metadata URI until the capsule is revealed.
- **Commitment-first privacy.** The contract stores only `encrypted_uri` and a salted `content_commitment` before reveal. It does not store plaintext reveal metadata early.
- **Authorized reveal.** After `reveal_at`, only the original creator or current token owner can reveal.
- **Content-addressed URIs.** Hidden, encrypted, and revealed URIs must use `ipfs://` or `ar://`.
- **Enumerable ERC-721.** Uses OpenZeppelin `ERC721EnumerableComponent`.
- **SRC5 discovery.** Registers `IIP_TIME_CAPSULE_ID`.

## Privacy Model

Cairo contracts cannot encrypt data or hide values written to chain storage. Anything stored before the unlock time is publicly readable by chain infrastructure.

For that reason, this contract never stores the plaintext reveal URI before reveal. The intended flow is:

1. Creator prepares the final IP metadata off-chain.
2. Creator computes `content_hash` for the final metadata or payload.
3. Creator chooses an unpredictable `content_salt`.
4. Creator computes `content_commitment = Poseidon(content_hash, content_salt)`.
5. Creator stores an encrypted payload or sealed descriptor on IPFS/Arweave.
6. Creator mints a capsule with `encrypted_uri`, `content_commitment`, and `reveal_at`.
7. Until reveal, marketplaces see `hidden_uri` from `token_uri`.
8. After `reveal_at`, creator or current owner calls `reveal_capsule`.
9. `token_uri` returns the revealed content-addressed URI.

The contract checks `Poseidon(content_hash, content_salt) == content_commitment`. Indexers and clients should verify off-chain that the content at `revealed_uri` hashes to the supplied `content_hash`.

## Interface

```cairo
fn mint_capsule(
    recipient: ContractAddress,
    encrypted_uri: ByteArray,
    content_commitment: felt252,
    reveal_at: u64,
) -> u256

fn reveal_capsule(
    token_id: u256,
    revealed_uri: ByteArray,
    content_hash: felt252,
    content_salt: felt252,
)

fn get_capsule_data(token_id: u256) -> TimeCapsuleData
fn get_encrypted_uri(token_id: u256) -> ByteArray
fn get_revealed_uri(token_id: u256) -> ByteArray
fn get_token_creator(token_id: u256) -> ContractAddress
fn get_token_reveal_at(token_id: u256) -> u64
fn is_unlocked(token_id: u256) -> bool
fn is_revealed(token_id: u256) -> bool
fn get_hidden_uri() -> ByteArray
fn get_max_lock_duration() -> u64
fn compute_content_commitment(content_hash: felt252, content_salt: felt252) -> felt252
fn get_commitment_scheme() -> felt252
```

### SRC5 Interface

```cairo
pub const IIP_TIME_CAPSULE_ID: felt252 =
    0x03874654ec5283a05a5b634b5fd6ce5c4acdc942c788acaa5982991a3f7663d1;
```

### Commitment Scheme

```cairo
pub const COMMITMENT_SCHEME_POSEIDON_HASH_SALT: felt252 = 'POSEIDON_HASH_SALT';

pub fn compute_content_commitment(content_hash: felt252, content_salt: felt252) -> felt252 {
    Poseidon(content_hash, content_salt)
}
```

## Data Model

```cairo
pub struct TimeCapsuleData {
    token_id: u256,
    owner: ContractAddress,
    creator: ContractAddress,
    encrypted_uri: ByteArray,
    content_commitment: felt252,
    reveal_at: u64,
    revealed_uri: ByteArray,
    revealed_at: u64,
    content_hash: felt252,
    content_salt: felt252,
    status: u8,
}
```

Status values:

| Constant | Value | Meaning |
|---|---:|---|
| `STATUS_SEALED` | `0` | Minted, not revealed |
| `STATUS_REVEALED` | `1` | Revealed URI is active |

## Constructor

```cairo
fn constructor(
    name: ByteArray,
    symbol: ByteArray,
    hidden_uri: ByteArray,
    max_lock_duration: u64,
)
```

`hidden_uri` is the OpenSea-compatible placeholder metadata returned by `token_uri` before reveal. `max_lock_duration` caps the maximum delay from mint time to `reveal_at`, preventing accidentally unreachable capsules.

## Development

```bash
scarb build
snforge test
scarb fmt
```

Current verification:

```text
Tests: 30 passed, 0 failed
```

## Dependencies

```toml
starknet = "2.12.0"
openzeppelin = { git = "https://github.com/OpenZeppelin/cairo-contracts.git", tag = "v0.20.0" }
snforge_std = "0.59.0"
assert_macros = "2.12.0"
```
