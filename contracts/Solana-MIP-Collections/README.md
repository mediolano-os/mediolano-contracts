# MIP Collections — Solana

IP collection issuance for Solana. A permissionless, zero-fee, ownerless
registry + CPI wrapper over Metaplex Core: `create_collection` creates a Core
collection owned by its creator (with the Core Royalties plugin) and records it
under a sequential id; `mint_asset` mints Core assets into a collection, with
authority enforced by Core itself. The program holds no rights over created
collections.

Same protocol semantics as the Starknet `MIP-Collections-ERC721` package,
expressed idiomatically for Solana.

## Build & test

    anchor build
    cargo test
