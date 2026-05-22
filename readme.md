# Programmable IP for the Integrity Web

Cairo smart contracts for Mediolano, the intellectual property provider of the integrity web, powered on Starknet.


Quick links:
<br>
<a href="https://ip.mediolano.app">Mediolano IP Creator</a>
<br>
<a href="https://t.me/integrityweb">Telegram</a> | <a href="https://x.com/mediolanoapp">X / Twitter</a>
<br>



## Mediolano

Mediolano empowers creators, artists and organizations to make money from their content, without requiring them to know anything about crypto.

With permissionless services for Programmable Intellectual Property (IP), leveraging Starknet’s high-speed, low-cost transactions and zero-knowledge proofs, Mediolano provides a comprehensive suite of solutions to tokenize and monetize assets efficiently, transparently and with sovereignty.

With zero fees, Mediolano’s open-source protocol and dapp ensures immediate tokenization and protection under the Berne Convention for the Protection of Literary and Artistic Works (1886), covering 181 countries. This framework guarantees global recognition of authorship, providing verifiable proof of ownership for 50 to 70 years, depending on jurisdiction.

The platform also introduces advanced monetization, enabling diverse approaches to licensing, royalties, and financing creators economies. These tools are designed to offer integrations with various ecosystems, including communities, games, and AI agents, unlocking the true power of Programmable IP for the Integrity Web.

## Protocol Design

The collections protocols prioritize security, performance, and simplicity. Shared invariants are kept small: immutable deployments, owner-gated minting, immutable metadata/provenance records, protocol-neutral metadata URIs, bounded input lengths, and explicit constructor validation.

Feature parity is intentional where it protects the same invariant across standards. It is not used to copy every feature between ERC-721 and ERC-1155: ERC-721 keeps unique IP asset behavior and archive support, while ERC-1155 keeps edition-style token types and ERC-2981 royalty signaling.


## Roadmap

- [x] Starknet Ignition **24.9**

- [x] MIP Protocol @ Starknet Sepolia **24.11**

- [x] Mediolano Dapp @ Starknet Sepolia **24.11**

- [x] Programmable IP Contracts **25.02**

- [x] MIP Dapp @ Starknet Sepolia **25.06**

- [X] MIP Protocol @ Starknet Mainnet **25.07**

- [X] MIP Collections Protocol @ Starknet Sepolia **25.07**

- [X] MIP Dapp @ Starknet Mainnet **25.08**

- [X] MIP Collections Protocol @ Starknet Mainnet **25.08**

- [X] MIP Mobile @ Android Google Play **25.09**

- [X] MIP Mobile @ iPhone iOS App Store **25.12**

- [X] Mediolano IP Creator Dapp @ Starknet Mainnet **26.01**

- [X] Security Audit and Review: IP Collections erc-721 Protocol +  IP Collections erc-1155 Protocol **26.04**

- [X] Immutable Architecture Refactor: MIP Collections ERC-721 Protocol **26.05**

- [X] Immutable MIP Collections ERC-721 Deployment @ Starknet Mainnet **26.05**


## MIP Collections ERC-721

`contracts/MIP-Collections-ERC721` contains the immutable ERC-721 collection registry for Mediolano IP. The design separates permanent provenance from operational stewardship:

- `IPCollection` is an immutable registry and factory.
- Each collection deploys its own immutable `IPNft` ERC-721 contract.
- There is no global admin owner, upgrade function, mutable NFT class hash, or collection pause switch.
- The registry constructor rejects a zero `IPNft` class hash.
- Collection ownership can be transferred atomically by the current collection owner.
- Ownership transfer only changes future mint authority; already minted token records remain unchanged.
- Token legal records store immutable `metadata_uri`, `original_creator`, and `registered_at` fields.
- The collection owner who mints is recorded as the immutable creator/author; the recipient only receives custody.
- Token archive preserves the on-chain legal record instead of burning it.
- Active ERC-721 tokens keep standard direct transfer behavior for wallet and marketplace composability.
- Transfers routed through `IPCollection` additionally update protocol transfer stats and emit protocol transfer events.
- `CollectionStats.total_transfers` counts only transfers routed through `IPCollection`; indexers should also read native `IPNft` ERC-721 `Transfer` events for complete transfer history.
- Token metadata uses immutable per-token, protocol-neutral URIs. URIs must be non-empty and no longer than 2048 bytes; collection `base_uri` is informational and is not concatenated with token IDs.

This architecture is designed for creator sovereignty and social-login wallet handoff flows. For example, a creator can initialize a collection through an embedded wallet and later transfer collection stewardship to a regular wallet without changing historical authorship records.

### Mainnet Deployment

| Component | Class hash | Address |
|---|---|---|
| `IPNft` immutable ERC-721 class | `0x02d50b7e6d1a14f17a8fdc2df24d6e493bae6fae579656d81959b8c92de4b13f` | Collection instances are deployed by `IPCollection` |
| `IPCollection` immutable registry/factory class | `0x00203f0e03a472cb6e058327ca22147c75e574cc2876f4981e99bcbcbe716a29` | `0x07c2207d200a1dce1cc82a117d8ba91dabfe3d1cc5072d9e4cdd9654fbb0ff10` |

| Action | Transaction | Actual fee |
|---|---|---|
| Declare `IPNft` | `0x0602f832d8bf6590780bb592c18e98aae9a0df9ad86245f94a92e1467ddbe2b8` | `24.308705 STRK` |
| Declare `IPCollection` | `0x04c89525842cf5e9f95e23942017bbd7caac40ab1f193a4603a52799ddf59194` | `29.224179 STRK` |
| Deploy `IPCollection` | `0x0543d8fe9e00c8981f6dd7d4148ad94cba8b9e6dfed69f1d4583c6034f71435f` | `0.036002 STRK` |

Build the contract:

```bash
cd contracts/MIP-Collections-ERC721
scarb build
```

Run tests:

```bash
cd contracts/MIP-Collections-ERC721
scarb test
```

Mainnet deployment flow:

```bash
cd contracts/MIP-Collections-ERC721

# Build Sierra/CASM artifacts
scarb build

# Declare IPNft first
sncast --profile medialane-mainnet --wait declare --contract-name IPNft

# Declare IPCollection
sncast --profile medialane-mainnet --wait declare --contract-name IPCollection

# Deploy IPCollection with the declared IPNft class hash as constructor calldata
sncast --profile medialane-mainnet --wait deploy \
  --class-hash <IPCollection_CLASS_HASH> \
  --constructor-calldata <IPNFT_CLASS_HASH>
```

See `contracts/MIP-Collections-ERC721/README.md` for the full contract-specific interface, storage, events, and deployment notes.

## IP Programmable ERC-1155 Collections

`contracts/IP-Programmable-ERC1155-Collections` contains immutable ERC-1155 collection contracts for edition-style IP assets.

- `IPCollectionFactory` is a permissionless factory for standalone `IPCollection` deployments.
- Each `IPCollection` is immutable and uses owner-gated minting.
- Token type provenance stores immutable metadata URI, original creator, and registration timestamp on first mint.
- The minter/collection owner is recorded as the immutable creator; the `to` address receives the minted balance.
- Token URIs are protocol-neutral, non-empty, no longer than 2048 bytes, and written once per token type.
- Factory and collection constructors reject zero owner/class-hash inputs.
- ERC-2981 royalty signaling is available and defaults to 0%.

See `contracts/IP-Programmable-ERC1155-Collections/README.md` for the full contract-specific interface, storage, events, and deployment notes.


## Getting Started

### Prerequisites

Before you begin, ensure you have the following requirements:

* **Git** for cloning and contributing.
* **Scarb** for Cairo package management and builds.
* **Starknet Foundry** for local Cairo/Starknet testing, declaration, deployment, and calls through `snforge` and `sncast`.
* **Node.js** only for contracts or utilities that include JavaScript/TypeScript tooling.

### System Requirements

- **Git**
- **Scarb**
- **Starknet Foundry**
- **Operating System**: macOS, Windows (including WSL), and Linux are supported

### Installation

1. **Clone the repository** to your local machine:

```bash
git clone https://github.com/mediolano-app/mediolano-contracts.git
cd mediolano-contracts
```

2. **Install dependencies**:

```bash
# Install Scarb (Cairo package manager)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
```

3. **Build contracts**:

```bash
# Build a specific contract package
cd contracts/MIP-Collections-ERC721
scarb build
```

4. **Run tests**:

```bash
# Run tests for a specific contract package
cd contracts/MIP-Collections-ERC721
scarb test
```

## Development

### Project Structure

```
mediolano-contracts/
├── contracts/
│   ├── MIP-Collections-ERC721/      # Immutable ERC-721 IP collections
│   ├── IP-Programmable-ERC1155-Collections/
│   ├── IP-Marketplace/             # Marketplace contracts
│   ├── IP-Marketplace-Auction/      # Auction marketplace
│   ├── IP-Club/                    # Community management
│   ├── IP-Revenue-Share/           # Revenue distribution
│   ├── IP-License-Agreement/       # Licensing contracts
│   ├── IP-Collective-Agreement/    # Multi-party agreements
│   ├── User-Achievements/          # Gamification system
│   └── ...                         # Additional contracts
├── readme.md
├── LICENSE
└── CLAUDE.md
```

### Building and Testing

Each contract directory contains its own `Scarb.toml` configuration file. You can build and test contracts individually:

```bash
# Navigate to specific contract
cd contracts/MIP-Collections-ERC721

# Build the contract
scarb build

# Run contract tests
scarb test

# Format code
scarb fmt
```

### Deployment

Each contract package has its own constructor and declaration order. Always check the contract-specific README before mainnet deployment.

Generic `sncast` flow:

```bash
# Declare a compiled contract class
sncast --profile <profile> --wait declare --contract-name <CONTRACT_NAME>

# Deploy with constructor calldata
sncast --profile <profile> --wait deploy \
  --class-hash <CLASS_HASH> \
  --constructor-calldata <CONSTRUCTOR_ARGS...>
```

For the current MIP Collections ERC-721 mainnet flow, see `contracts/MIP-Collections-ERC721/README.md`.

## Security

### Security Measures

- **Contract-Specific Authorization**: Permissions are scoped per contract; MIP Collections ERC-721 uses immutable registry and collection-owner checks instead of a global admin.
- **Immutable IP Collections**: MIP Collections ERC-721 and IP Programmable ERC-1155 Collections are immutable contract systems without collection upgrade entrypoints.
- **Permanent Provenance**: IP collection tokens preserve immutable metadata URI, original creator, and registration timestamp.
- **Protocol-Neutral Metadata**: Collection metadata pointers are validated for presence and a 2048-byte maximum length on-chain; storage scheme validation stays in SDKs, frontends, and indexers.
- **Transferable Stewardship**: Collection ownership can move atomically to another wallet for future mint authority without changing historical token records.
- **Composable ERC-721 Transfers**: Active MIP collection tokens support direct ERC-721 transfers; the registry transfer path remains available for protocol stats/events.
- **Reentrancy Protection**: Guards against reentrancy attacks
- **Input Validation**: Comprehensive validation of all user inputs
- **Overflow Protection**: Safe math operations throughout

## 🤝 Contributing

We are building open-source Integrity Web with the amazing **OnlyDust** platform. Check our [website](https://app.onlydust.com/p/mediolano) for more information.

We also have a [Telegram](https://t.me/mediolanoapp) group focused to support development.

Contributions are **greatly appreciated**. If you have a feature or suggestion that would make our platform better, please fork the repo and create a pull request with the tag "enhancement".

### How to Contribute

1. **Fork the Project**
2. **Create your Feature Branch** (`git checkout -b feature/Feature`)
3. **Commit your Changes** (`git commit -m 'Add some Feature'`)
4. **Push to the Branch** (`git push origin feature/YourFeature`)
5. **Open a Pull Request**

### Development Guidelines

- Follow Cairo best practices and coding standards
- Write comprehensive tests for new features
- Update documentation for any API changes
- Ensure all tests pass before submitting a pull request
- Use descriptive commit messages

### Issue Reporting

When reporting issues, please include:

- **Environment details** (OS, Cairo version, Scarb version)
- **Steps to reproduce** the issue
- **Expected vs actual behavior**
- **Error messages or logs**
- **Minimal code example** if applicable

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Acknowledgments

- **Starknet Foundation** for the amazing ZK-rollup technology
- **OpenZeppelin** for secure smart contract components
- **OnlyDust** for supporting open-source development
- **Community Contributors** who make this project possible

## 📞 Support

- **Documentation**: Check individual contract READMEs for specific guidance
- **Community**: Join our [Telegram](https://t.me/mediolanoapp) for discussions
- **Issues**: Report bugs and feature requests on GitHub

---

**Built with ❤️ for the Integrity Web on Starknet**
