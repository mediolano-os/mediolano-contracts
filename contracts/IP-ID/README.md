# IP-ID Protocol

IP-ID is Mediolano's canonical work identity protocol.

It answers one narrow question:

> Are these chain-local assets representations of the same intellectual work?

The protocol is intentionally small, zero-fee, and append-only. It does not store mutable license policy, does not decide whether a work is commercially usable, and does not act as a profile or marketplace gate.

## Principles

- A work has one `ip_id`.
- A work may have many chain-local representations.
- Authorship and license claims live in immutable, content-addressed metadata.
- New terms or metadata are represented by new work versions or new representations, not by mutating old claims.
- Attestations are append-only claims, not privileged protocol truth.
- Indexers and applications may project rich views from events, but the contract remains neutral.

## Core Model

### Work

A `Work` is the canonical IP-ID record:

- `creator`: the wallet that registered the work.
- `controller`: the wallet allowed to link representations or rotate control.
- `metadata_uri`: immutable metadata pointer.
- `metadata_hash`: content hash for the metadata document.
- `parent_ip_id`: optional parent work for remix/version lineage.
- `parent_relation`: `VERSION`, `DERIVATIVE`, or another canonical relation used by the SDK/indexer.
- `representation_count`: number of linked chain-local representations.
- `attestation_count`: number of append-only attestations.

### Representation

A `Representation` links one chain-local asset or content locator to an IP-ID:

- `chain_id`: a normalized chain namespace such as `starknet`, `ethereum`, or `bitcoin`.
- `representation_key`: a globally unique locator hash derived by the contract.
- `asset_locator`: normalized chain-local contract, collection, or address hash. Use zero when the representation is not contract-like.
- `token_id`: token id when relevant, otherwise zero.
- `content_id`: non-contract locator hash for Ordinals, Arweave, IPFS, or external chains.
- `metadata_uri` and `metadata_hash`: representation-specific immutable metadata.
- `standard`: `ERC721`, `ERC1155`, `ORDINAL`, `ARWEAVE`, etc.

The contract derives `representation_key` from the normalized tuple:

```text
hash("IPID_REPRESENTATION_V1", chain_id, asset_locator, token_id, content_id, standard)
```

This prevents two clients from linking the same representation under different keys.

### Attestation

An `Attestation` is an append-only claim about a work:

- provenance proof
- creator signature proof
- external registry proof
- verification proof
- legal/documentation proof

The contract records the claim; it does not make the claim universally authoritative.

Canonical attestation type names exported by the contract:

- `PROVENANCE`
- `CREATOR_SIGNATURE`
- `EXTERNAL_REGISTRY`
- `LEGAL_PROOF`
- `VERIFICATION`

## Interface

- `register_work(metadata_uri, metadata_hash, parent_ip_id, parent_relation) -> ip_id`
- `link_representation(ip_id, chain_id, asset_locator, token_id, content_id, metadata_uri, metadata_hash, standard)`
- `transfer_controller(ip_id, new_controller)`
- `attest(ip_id, attestation_type, data_hash, uri) -> attestation_id`
- `derive_representation_key(chain_id, asset_locator, token_id, content_id, standard) -> representation_key`
- read helpers for works, representations, reverse lookup, representation keys, and attestations

## What This Contract Does Not Do

- No ERC-721 identity carrier.
- No mutable `update_metadata`.
- No mutable `update_licensing`.
- No `can_use_commercially` or derivative permission gates.
- No admin verification flag.
- No owner portfolio indexing in contract storage.
- No Medialane fee or governance coupling.

Those belong in immutable metadata, optional service contracts, indexers, SDKs, or application policy.
