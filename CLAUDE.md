# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Cairo smart contracts for **Mediolano**, a Programmable IP (Intellectual Property) protocol on Starknet. The protocol enables tokenization, licensing, and monetization of intellectual property assets using ERC-721 and ERC-1155 standards.

## Commands

Each contract is an independent Scarb project. All commands must be run from within a specific contract directory (e.g., `cd contracts/MIP-Collections-ERC721`).

```bash
# Build a contract
scarb build

# Run all tests for a contract
scarb test

# Run a single test by name
snforge test test_function_name

# Run tests matching a pattern
snforge test test_create

# Format code
scarb fmt
```

After writing any Cairo code, run `scarb build` immediately to verify it compiles before continuing.

## Architecture

### Repository Structure

Each subdirectory under `contracts/` is a **standalone Cairo project** with its own `Scarb.toml`, `snfoundry.toml`, `src/`, and `tests/` directory. There is no monorepo build — you must `cd` into each contract to build/test it.

### Core Protocol Contracts (production-grade, on Sepolia + Mainnet)

| Contract | Role |
|---|---|
| `MIP-IP-Factory-ERC721/` | Core MIP Protocol — ERC-721 IP tokenization factory |
| `MIP-Collections-ERC721/` | Collection management — deploys per-collection `IPNft` contracts via `deploy_syscall` |
| `MIP-Openedition-ERC721a/` | Open edition NFT minting for IP assets |
| `Medialane-Protocol/` | Marketplace core — order creation, fulfillment, cancellation with SNIP-12 signatures |

### IP Utility Contracts

Specialized contracts in `IP-*/` directories each address a specific IP use case:
- **Monetization**: `IP-Revenue-Share`, `IP-Launchpad`, `IP-Crowfunding`, `IP-Subscription`, `IP-Sponsorhip`
- **Licensing**: `IP-License-Agreement`, `IP-Leasing`, `IP-Offer-Licensing`, `IP-Programmable-ERC-721`, `IP-Programmable-ERC-1155`
- **Marketplace**: `IP-Marketplace`, `IP-Marketplace-Listing`, `IP-Marketplace-Auction`, `IP-Marketplace-Bulk-Order`
- **Community**: `IP-Club`, `IP-Story`, `IP-Collective-Agreement`, `IP-Commission-Escrow`, `IP-Negotiation-Escrow`
- **Distribution**: `IP-Airdrop`, `IP-Drop`, `IP-Tickets`, `IP-Bulk-Tokenization`

### Key Architectural Patterns

**Component composition**: All contracts use OpenZeppelin Cairo components (`OwnableComponent`, `ERC721Component`, `UpgradeableComponent`, `AccessControlComponent`, etc.) embedded via `component!()` macro. Internal implementations are separated from exposed `#[abi(embed_v0)]` implementations.

**Factory pattern** (`MIP-Collections-ERC721`): `IPCollection` deploys individual immutable `IPNft` ERC-721 contracts per collection using `deploy_syscall`. It stores the constructor-set `ip_nft_class_hash` and maps `user_collections: Map<(ContractAddress, u256), u256>`.

**Upgradeability**: Check each contract before assuming upgradeability. `MIP-Collections-ERC721` is intentionally immutable: no `UpgradeableComponent`, no global admin owner, no mutable NFT class hash, and no pause switch.

**Module layout** within a contract follows this convention:
```
src/
  lib.cairo          # mod declarations
  ContractName.cairo # main #[starknet::contract] module
  types.cairo        # structs (Collection, TokenData, OrderDetails, …)
  interfaces/        # trait definitions (IContractName)
  components/        # reusable Cairo components
```

**Testing pattern**: Tests use `snforge_std` — `declare`, `ContractClassTrait`, `deploy`, `cheat_caller_address`/`start_cheat_caller_address`. Test constants are plain functions returning `ContractAddress` (e.g., `fn OWNER() -> ContractAddress { 0x123.try_into().unwrap() }`).

### Dependency Versions

Different contracts use different OpenZeppelin and `snforge_std` versions. Check the specific contract's `Scarb.toml`:
- MIP-Collections-ERC721: `openzeppelin = { git = ..., tag = "v0.20.0" }`, `snforge_std = "0.59.0"`, `starknet = "2.12.0"`
- Older contracts (IP-Programmable-ERC-721): `openzeppelin tag = "v0.17.0"`, `snforge_std` via git tag

### Deployment

`snfoundry.toml` in each contract configures `sncast` profiles. Deploy flow: `scarb build` → `sncast --profile <profile> --wait declare` → `sncast --profile <profile> --wait deploy`.

Current `MIP-Collections-ERC721` deployment — **chain: Starknet** (v0.4.0, on-chain `version()` == "0.4.0"):
- `IPNft` class hash: `0x040551f0d009a6d665ddff980a375dfccc71a8928c8bfcc9ab56244bc4464fab`
- `IPCollection` class hash: `0x063d4ac4ae317fd155216bf1b8a4d3a63172ff72965b9ac48dd5add0c2d32b70`
- `IPCollection` registry address: `0x0558c9b6ea4d403df6d765fb77be55702c572f0a811f037c6c4209fe1e5aeef2`
- Adds per-token EIP-2981 royalties (receiver = creator, immutable), `version()` views, `(collection_id, token_id)` token args, `protocol_routed_transfers` stat. Prior immutable deploys remain valid on-chain but are not tracked here.

## Cairo Coding Conventions

- `snake_case` for functions and variables; `PascalCase` for structs and modules
- Separate interface traits (`IContractName`) from implementation
- Use `pub mod` in `lib.cairo` to expose modules; keep internal helpers private
- Error strings must be `felt252` short strings (≤31 chars) for `assert!` messages
- Import storage traits explicitly: `StorageMapReadAccess`, `StoragePointerReadAccess`, etc.

### EVM-MIP-Collections (`contracts/EVM-MIP-Collections/`) — Ethereum + Base (Solidity)

ERC-721 IP collection issuance for EVM chains. Registry + clone pattern mirroring
`MIP-Collections-ERC721` (Cairo): `MIPRegistry` (ownerless, permissionless, zero-fee)
deploys per-creator `MIPCollection` clones (OZ v5 upgradeable-style initializers, ERC-2981,
archive semantics). One codebase deploys to both Ethereum and Base.

- **Stack**: Solidity 0.8.28 + OpenZeppelin v5.4.0 + Foundry
- **Status**: built and tested; NOT deployed (deploys are Phase 4, separately authorized)

Build & test:

    cd contracts/EVM-MIP-Collections
    forge build
    forge test

### EVM-MIP-Editions (`contracts/EVM-MIP-Editions/`) — Ethereum + Base (Solidity)

ERC-1155 edition issuance for EVM chains. Registry + clone pattern mirroring
`IP-Programmable-ERC1155-Collections` (Cairo): `MIPEditionsRegistry` (ownerless,
permissionless, zero-fee) deploys per-creator `MIPEditionCollection` clones
(sequential edition ids with per-edition URI + supply, addSupply for existing
editions, ERC-2981). One codebase deploys to both Ethereum and Base.

- **Stack**: Solidity 0.8.28 + OpenZeppelin v5.4.0 + Foundry
- **Status**: built and tested; NOT deployed (deploys are Phase 4, separately authorized)

Build & test:

    cd contracts/EVM-MIP-Editions
    forge build
    forge test
