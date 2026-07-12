# MIP Collections — Solana

IP collection issuance for Solana. A permissionless, zero-fee, ownerless
registry + CPI wrapper over Metaplex Core: `create_collection` creates a Core
collection owned by its creator and records it under a sequential id;
`mint_asset` mints Core assets into a collection, with authority enforced by
Core itself. The program holds no rights over created collections.

Same protocol semantics as the Starknet `MIP-Collections-ERC721` package,
expressed idiomatically for Solana:

- **Royalties are per-asset and immutable** — written at mint as a Core
  Royalties plugin with authority `None` (no one can ever update it) and the
  minting creator as sole beneficiary. The plugin is attached even at zero
  royalty, so every asset carries its creator's authorship record on-chain.
  The registration timestamp is the mint transaction's block time.
- **Archive is native Core** — an asset owner permanently freezes their asset
  by adding a FreezeDelegate plugin (`frozen: true`) with authority `None`
  directly on Core. That is the holder's right, exactly as on Starknet, and
  needs no program support.

## Build & test

    anchor build
    cargo test
