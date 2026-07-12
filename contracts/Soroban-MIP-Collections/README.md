# MIP Collections — Stellar (Soroban)

IP collection issuance for Stellar. A permissionless, zero-fee, ownerless
registry deploys creator-owned NFT collection contracts from an uploaded WASM
hash. Collections carry owner-gated sequential minting; each token records an
immutable registration record (complete metadata URI, original creator,
ledger timestamp) and an immutable per-token royalty set at mint with the
minting creator as receiver, served through the OpenZeppelin Stellar royalties
interface (`royalty_info(token_id, sale_price) -> (Address, i128)`). A token's
holder can archive it — permanently freezing it in place while preserving the
record. The registry holds no rights over created collections.

Same protocol semantics as the Starknet `MIP-Collections-ERC721` package,
expressed idiomatically for Soroban.

## Build & test

    cargo test
    cargo build --target wasm32v1-none --release
