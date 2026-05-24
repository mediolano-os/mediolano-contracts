# Mediolano OS

Programmable intellectual property primitives for the Integrity Web.

Mediolano is a public-good protocol for tokenizing, protecting, licensing, and composing intellectual property powered on Starknet. This repository contains Cairo smart contracts for IP registration, collections, editions, licensing, access, revenue sharing, marketplace routing, and service assets.

The core idea is simple: creators should be able to create immutable, censorship-resistant, zero-fee records of authorship and ownership through permissionless smart contracts they fully control.

Mediolano is built for Berne Convention-aligned protection of literary and artistic works: assets created with Mediolano protocols carry durable authorship, provenance, metadata, and licensing records that can be verified independently of any single application, marketplace, gateway, or database.

## Quick Links

- Mediolano IP Creator: <https://ip.mediolano.app>
- Community: <https://t.me/integrityweb>
- X: <https://x.com/mediolanoapp>

## Mediolano

Mediolano provides programmable IP tokenization primitives:

- Immutable authorship and provenance records.
- ERC-721 and ERC-1155 IP collection contracts.
- Content-addressed metadata pointers for durable ownership and license claims.
- Programmable licensing surfaces that remain readable by wallets, marketplaces, SDKs, indexers, and agents.
- Service contracts for access, tickets, subscriptions, clubs, revenue sharing, escrow, assignment, licensing, drops, airdrops, and marketplace flows.
- A neutral foundation that applications can index, render, and extend without becoming the source of truth.

Mediolano contracts are designed as public infrastructure. The protocol should remain useful even if any one frontend, indexer, gateway, or commercial venue disappears.

## Public-Good Principles

### 1. Contracts Are The Source Of Truth

Ownership, balances, mint authority, provenance, order state, service records, and emitted events belong on-chain. Indexers, SDKs, and apps may cache and present that state, but they do not authorize it.

### 2. Zero-Fee Protocol Layer

Mediolano tokenization and protection primitives are zero-fee at the contract layer. Fee policy does not belong inside immutable public-good primitives.

Applications may build their own models around the protocol, while the Mediolano substrate itself stays neutral.

### 3. Interoperability Over Lock-In

Mediolano assets use standard token interfaces and standard metadata envelopes wherever possible. Metadata should follow the OpenSea-compatible ERC-721 / ERC-1155 baseline:

- `name`
- `description`
- `image`
- `animation_url` when useful
- `external_url` when useful
- `attributes`

Protocol-specific information should extend this baseline instead of replacing it. A Mediolano asset should remain understandable outside a Mediolano-specific interface.

### 4. Durable Authorship And Licensing

Authorship, ownership, and license claims should live in immutable, content-addressed metadata such as IPFS or Arweave documents referenced from the token.

This supports Berne Convention-aligned authorship records across jurisdictions while avoiding brittle on-chain legal logic. Licensing is metadata-first and soft-enforced by default. Contracts enforce only the specific rules they explicitly implement, such as escrow, royalty splits, time locks, or access checks.

### 5. Visibility Is Not The Same As Tradability

Service contracts should emit or mint indexable assets when doing so improves discovery, ownership visibility, access display, or marketplace routing.

Tradability is a separate choice. A membership badge, subscription receipt, ticket, proof, or access pass may be visible and composable without being transferable by default. See [SERVICE_ASSET_DOCTRINE.md](docs/SERVICE_ASSET_DOCTRINE.md) for the service declaration model.

### 6. Agents And Integrators Are First-Class Users

The protocol should be legible to software, not only to humans. Services should expose stable identifiers, standard interfaces, clear events, and machine-readable metadata so wallets, SDKs, indexers, and autonomous agents can discover what exists and what actions are available.

## Repository Map

Each contract package is self-contained and has its own `Scarb.toml`. Some packages are deployed and production-oriented; others are prototypes or pre-production service experiments. Treat each package README as the authority for its current status.

### Core IP Issuance

| Package | Purpose |
| --- | --- |
| `contracts/MIP-Collections-ERC721` | Immutable ERC-721 collection registry and factory. Deploys a dedicated `IPNft` contract per collection and preserves token provenance. |
| `contracts/IP-Programmable-ERC1155-Collections` | Immutable ERC-1155 collection factory for edition-style IP assets. |
| `contracts/IP-Programmable-ERC-721` | Standalone permissionless ERC-721 IP collection contract. |
| `contracts/IP-collection-ERC-721` | Owner-minted ERC-721 collection for canonical issuer-controlled IP assets. |
| `contracts/IP-Programmable-ERC-1155` | Legacy/prototype ERC-1155 IP contract. Use the collection-based ERC-1155 package for production-oriented work. |
| `contracts/MIP-IP-Factory-ERC721` | Factory-oriented ERC-721 IP issuance package. |
| `contracts/MIP-Openedition-ERC721a` | Open-edition ERC-721 issuance package. |
| `contracts/IP-Bulk-Tokenization` | Batch IP tokenization flow for multiple ERC-721 mints. |
| `contracts/IP-Colab-Collections` | Collaborative collection prototype. |

### Identity, Provenance, And Discovery

| Package | Purpose |
| --- | --- |
| `contracts/IP-ID` | Append-only work identifier protocol for linking works, representations, and attestations. |
| `contracts/IP-Assets-Visibility` | Asset visibility and discovery prototype. |
| `contracts/User-Public-Profile` | Public profile records. |
| `contracts/User-Settings` | User settings contract. |
| `contracts/User-Achievements` | Achievement and reputation-oriented records. |
| `contracts/Partner-Certification` | Partner certification records. |

### Licensing, Rights, And Agreements

| Package | Purpose |
| --- | --- |
| `contracts/IP-License-Agreement` | Proof-of-IP licensing agreement signatures and agreement records. |
| `contracts/IP-Offer-Licensing` | Licensing offer flow. |
| `contracts/IP-Assignment` | Programmable IP rights assignment and royalty accounting. |
| `contracts/IP-Collective-Agreement` | Multi-owner ERC-1155 IP agreement with governance and royalty distribution. |
| `contracts/IP-Collective-Agreement-Leasing` | Collective agreement variant with leasing-oriented updates. |
| `contracts/IP-Leasing` | IP leasing primitives. |
| `contracts/IP-Leasing-AF` | Alternate IP leasing package. |
| `contracts/IP-Revenue-Share` | Revenue sharing and distribution primitives. |
| `contracts/IP-Franchise-Monetization` | Franchise-oriented IP monetization flow. |
| `contracts/IP-Syndication` | IP syndication package. |

### Access, Community, And Launch Services

| Package | Purpose |
| --- | --- |
| `contracts/IP-Club` | Club manager that deploys non-transferable ERC-721 membership passes. |
| `contracts/IP-Subscription` | Time-bound subscription plans and access records. |
| `contracts/IP-Tickets` | Ticketing and redemption-oriented access assets. |
| `contracts/IP-Drop` | Drop and claim flow. |
| `contracts/IP-Airdrop` | Merkle-based airdrop flow. |
| `contracts/IP-Launchpad` | Launchpad service primitives. |
| `contracts/IP-Crowfunding` | Crowdfunding package. |
| `contracts/IP-Sponsorhip` | Sponsorship package. |
| `contracts/IP-Time-Capsule` | Time-locked IP capsule package. |
| `contracts/IP-Story` | Story and narrative IP package. |

### Marketplace And Transaction Services

| Package | Purpose |
| --- | --- |
| `contracts/IP-Marketplace` | Marketplace contract package. |
| `contracts/IP-Marketplace-Auction` | Auction marketplace package. |
| `contracts/IP-Marketplace-Bulk-Order` | Bulk order marketplace flow. |
| `contracts/IP-Marketplace-Listing` | Listing-oriented marketplace package. |
| `contracts/IP-Marketplace-Public-Profile` | Marketplace profile records. |
| `contracts/IP-Negotiation-Escrow` | Escrow flow for negotiated IP transactions. |
| `contracts/IP-Commission-Escrow` | Commission escrow package. |
| `contracts/IP-Smart-Transaction` | Smart transaction package. |

## Current Production Anchors

The most current production-oriented packages are:

- `contracts/MIP-Collections-ERC721`
- `contracts/IP-Programmable-ERC1155-Collections`
- `contracts/IP-Programmable-ERC-721`
- `contracts/IP-collection-ERC-721`

Several service packages are pre-production or prototypes and say so in their local README files. Before deployment, read the package README, review constructor requirements, check test coverage, and run a deployment rehearsal.

## Contract Design Rules

New and redesigned packages should follow these rules:

- Keep protocol authority on-chain.
- Keep tokenization and protection primitives zero-fee.
- Prefer immutable deployments for core provenance contracts.
- Store immutable metadata pointers; do not make authorship records mutable.
- Separate creator/authorship provenance from token custody.
- Use standard ERC-721, ERC-1155, ERC-20, SRC5, and metadata conventions where appropriate.
- Encode license terms as standard metadata attributes.
- Make stricter license or access enforcement explicit in the service contract.
- Declare service assets and transferability semantics clearly.
- Keep events indexable and stable.
- Do not make an asset tradable only to gain visibility.

## Service Asset Declaration

Every service README should explain the asset it creates or the reason it does not create one.

Recommended declaration fields:

| Field | Meaning |
| --- | --- |
| `service_id` | Stable kebab-case behavior identifier. |
| `asset_standard` | ERC721, ERC1155, ERC20, or none. |
| `asset_role` | Membership, subscription, receipt, edition, proof, ticket, license, or another clear role. |
| `transferability` | Transferable, non-transferable, restricted, or not-applicable. |
| `access_semantics` | What grants access: ownership, balance, expiry, redemption, payment, or another rule. |
| `marketplace_visibility` | Listed, displayed only, hidden, or routed through a custom market. |
| `metadata_uri_policy` | Content-addressed metadata requirements. |
| `src5_interface_id` | Custom interface ID for SDK and agent detection when applicable. |

## Metadata And Licensing

Mediolano metadata should be portable first and expressive second.

Minimal ERC-721 / ERC-1155 metadata:

```json
{
  "name": "Composition No. 7",
  "description": "Original score, 2026.",
  "image": "ipfs://bafy.../cover.png",
  "animation_url": "ipfs://bafy.../audio.mp3",
  "external_url": "https://ip.mediolano.app/asset/0x.../7",
  "attributes": [
    { "trait_type": "Medium", "value": "Audio" },
    { "trait_type": "License", "value": "CC BY-SA" },
    { "trait_type": "Commercial Use", "value": "Allowed" },
    { "trait_type": "Derivatives", "value": "Share-alike" },
    { "trait_type": "Attribution", "value": "Required" },
    { "trait_type": "Territory", "value": "Worldwide" },
    { "trait_type": "AI Policy", "value": "Training allowed with attribution" },
    { "trait_type": "Royalty", "value": "5%" }
  ]
}
```

Licensing rules:

- `CC BY-SA` is the recommended default for remix-friendly public culture.
- License traits are declarations in immutable metadata.
- Royalty traits are display and intent signals unless a contract explicitly enforces payout logic.
- A new license or changed metadata should be represented by a new work version or representation, not by mutating the old claim.
- Jurisdiction-specific interpretation belongs in apps, partners, and legal workflows, not in default token contracts.

## Getting Started

### Requirements

- Git
- Scarb
- Starknet Foundry (`snforge` and `sncast`)
- Node.js only for packages that include JavaScript or TypeScript utilities

Check the repository toolchain:

```bash
cat .tool-versions
```

Clone the repository:

```bash
git clone https://github.com/mediolano-app/mediolano-contracts.git
cd mediolano-contracts
```

Build a package:

```bash
cd contracts/MIP-Collections-ERC721
scarb build
```

Run package tests:

```bash
cd contracts/MIP-Collections-ERC721
scarb test
```

Some packages use `snforge test` through their Scarb scripts:

```bash
cd contracts/IP-Club
snforge test
```

Format a package:

```bash
cd contracts/MIP-Collections-ERC721
scarb fmt
```

## Deployment Guidance

Each package has its own constructor arguments, declaration order, class names, and deployment state. Always use the package README as the deployment source.

Generic Starknet flow:

```bash
cd contracts/<PACKAGE>

scarb build

sncast --profile <profile> --wait declare --contract-name <CONTRACT_NAME>

sncast --profile <profile> --wait deploy \
  --class-hash <CLASS_HASH> \
  --constructor-calldata <CONSTRUCTOR_ARGS...>
```

Before mainnet deployment:

- Confirm the package is production-ready.
- Read the local README and any audit or report files.
- Run the test suite.
- Validate constructor calldata.
- Rehearse on testnet or a local fork.
- Record class hashes, deployed addresses, and transactions in the package README.

## Security Posture

Mediolano contracts favor small, inspectable invariants:

- Immutable provenance records.
- Explicit constructor validation.
- Owner-gated minting where a collection has an issuer.
- Permissionless deployment where the service is meant to be neutral.
- Content-addressed metadata policies for service assets.
- Standard transfer behavior for transferable assets.
- Non-transferable or restricted behavior only when the service semantics require it.
- No hidden platform authority inside protocol contracts.

Security status varies by package. Some packages are audited or have deployment reports; others are prototypes without complete tests. Do not infer production readiness from the repository root.

## Contributing

Contributions are welcome when they strengthen Mediolano as public infrastructure.

Good contributions usually do one of the following:

- Make a contract simpler or safer.
- Add focused tests for a protocol invariant.
- Improve package-level documentation.
- Clarify service asset declarations.
- Improve metadata, interface, or event interoperability.
- Remove platform assumptions from protocol code.

Before opening a pull request:

1. Fork the repository.
2. Create a feature branch.
3. Make the smallest coherent change.
4. Run the relevant package tests.
5. Update the package README when behavior changes.
6. Open a pull request with a clear description of the invariant or workflow affected.

Issue reports should include:

- Package name.
- Scarb and Starknet Foundry versions.
- Steps to reproduce.
- Expected behavior.
- Actual behavior.
- Logs, transaction hashes, or minimal examples when available.

## License

This repository is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE).

## Acknowledgments

Mediolano is built for creators, builders, public-good maintainers, and the wider Integrity Web community.

Thanks to Salvador, Rodrigo, Starknet Foundation and ecosystem, Cairo developers and maintainers, OnlyDust contributors, ai agents and everyone dreaming.
