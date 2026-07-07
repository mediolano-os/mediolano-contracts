# MIP Collections — Stellar (Soroban)

IP collection issuance for Stellar. A permissionless, zero-fee, ownerless
registry deploys creator-owned NFT collection contracts from an uploaded WASM
hash. Collections carry owner-gated sequential minting with complete per-token
metadata URIs and the OpenZeppelin Stellar royalties interface
(`royalty_info(token_id, sale_price) -> (Address, i128)`), creator-set and
owner-adjustable. The registry holds no rights over created collections.

Same protocol semantics as the Starknet `MIP-Collections-ERC721` package,
expressed idiomatically for Soroban.

## Build & test

    cargo test
    cargo build --target wasm32v1-none --release
