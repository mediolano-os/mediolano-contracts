# MIP Editions — EVM

ERC-1155 edition issuance for EVM chains (Ethereum, Base). Registry + clone
pattern: `MIPEditionsRegistry` deploys per-creator `MIPEditionCollection`
contracts. Permissionless, zero-fee, ownerless registry; each collection is
owned by its creator. Editions are sequential ids with per-edition URI and
supply; the owner can mint further supply of an existing edition.

Same protocol semantics as the Starknet `IP-Programmable-ERC1155-Collections`
package, expressed idiomatically for the EVM.

## Build & test

    forge build
    forge test
