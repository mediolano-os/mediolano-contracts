# MIP Collections — EVM

ERC-721 IP collection issuance for EVM chains (Ethereum, Base). Registry + clone
pattern: `MIPRegistry` deploys per-creator `MIPCollection` contracts. Permissionless,
zero-fee, ownerless registry; each collection is owned by its creator.

Same protocol semantics as the Starknet `MIP-Collections-ERC721` package, expressed
idiomatically for the EVM.

## Build & test

    forge build
    forge test
