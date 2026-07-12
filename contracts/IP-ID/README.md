# IP-ID Protocol

IP-ID is Mediolano's canonical work identity protocol.

It answers one narrow question:

> Are these chain-local assets representations of the same intellectual work?

The protocol is intentionally small, zero-fee, and append-only. It does not store mutable license policy, does not decide whether a work is commercially usable, and does not act as a profile or marketplace gate.

## Principles

- A work has one `ip_id`, and the `ip_id` is **content-derived**: `hash("IPID_WORK_V1", creator, metadata_hash, salt)`. Identity survives contract redeploy and chain re-anchoring — the registry state is a pure function of its event log, so replaying the log on a new anchor reconstructs the same works under the same IDs.
- Two claimants of one content hash hold **parallel claims with distinct IDs**, not a first-come race for one ID. The contract records claims; it never adjudicates. Dispute resolution is deliberately platform-layer.
- A work may have many chain-local representations.
- Authorship and license claims live in immutable, content-addressed metadata.
- New terms or metadata are represented by new works or new representations, not by mutating old claims. (The single exception: a sealed work's empty URI may be revealed once — the commitment hash never changes.)
- Lineage, representation links, and attestations are all **append-only claims**, not privileged protocol truth.
- Indexers and applications may project rich views from events, but the contract remains neutral.

## Core Model

### Work

A `Work` is the canonical IP-ID record:

- `creator`: the wallet that registered the work (part of the `ip_id` derivation).
- `controller`: the wallet allowed to link representations, assert relations, reveal, or rotate control.
- `metadata_uri`: immutable metadata pointer — empty for a sealed registration until revealed.
- `metadata_hash`: content hash for the metadata document; the commitment for sealed works.
- `representation_count` / `relation_count` / `attestation_count`: enumeration counters.

### Relation

A `Relation` is an append-only lineage claim asserted by the subject work's controller:

- `relation_key`: `hash("IPID_RELATION_V1", ip_id, related_ip_id, relation_type)` — derived by the contract, globally unique, duplicate assertions revert.
- `relation_type`: `VERSION`, `DERIVATIVE`, or another canonical relation interpreted by the SDK/indexer.
- Multi-parent by construction: a remix of N works is N relations. Self-relations are rejected; both works must exist.

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

**Representation links are claim-grade, not authoritative.** The contract cannot verify another chain. A link is the controller's claim; the asset's actual holder on the other chain can `CONFIRM` it (dual-consent, strong signal) or `DISPUTE` it via an attestation targeting the `representation_key`.

### Attestation

An `Attestation` is an append-only claim about a work or about one of its claims:

- `subject_key = 0`: the attestation is about the work itself.
- `subject_key = <representation_key | relation_key>`: the attestation targets that specific claim of the same work.

The contract records the claim; it does not make the claim universally authoritative.

Canonical attestation type names exported by the contract:

- `PROVENANCE`
- `CREATOR_SIGNATURE`
- `EXTERNAL_REGISTRY`
- `LEGAL_PROOF`
- `VERIFICATION`
- `CONFIRM` — agreement with the targeted claim (e.g. the other-chain holder consents to a representation link)
- `DISPUTE` — visible disagreement with the targeted claim
- `ANCHOR` — reserved: "this state/work was anchored on chain X at height N" (Bitcoin proof-of-existence; no contract logic reads it yet)

## Sealed registration (commit-then-reveal)

Registering with an empty `metadata_uri` is a first-class sealed registration: the `metadata_hash` is the commitment and `created_at` is the proof-of-existence timestamp — proof a work existed at time T without disclosing it (unpublished manuscripts, priority evidence, embargoed drops).

`reveal(ip_id, metadata_uri)` is controller-only and one-time (allowed only while the stored URI is empty). Verifying that the revealed content hashes to the commitment is an off-chain/SDK concern: the URI is a pointer; the chain proves the commitment and the reveal time.

## Interface

- `register_work(metadata_uri, metadata_hash, salt) -> ip_id`
- `reveal(ip_id, metadata_uri)`
- `link_representation(ip_id, chain_id, asset_locator, token_id, content_id, metadata_uri, metadata_hash, standard)`
- `relate(ip_id, related_ip_id, relation_type) -> relation_key`
- `attest(ip_id, subject_key, attestation_type, data_hash, uri) -> attestation_id`
- `transfer_controller(ip_id, new_controller)`
- `derive_ip_id(creator, metadata_hash, salt) -> ip_id`
- `derive_representation_key(chain_id, asset_locator, token_id, content_id, standard) -> representation_key`
- `derive_relation_key(ip_id, related_ip_id, relation_type) -> relation_key`
- `registered_count() -> count`
- read helpers for works, representations, relations, attestations, reverse lookups, and per-work key enumeration

## Reserved seams (documented, not built)

- **Signed registration** — creator signs, anyone submits, so authorship is not welded to the gas payer (gasless apps, agents registering on a creator's behalf). Deferred until a consuming app needs it.
- **Canonical locator hashing** — the rule deriving `asset_locator` / `content_id` from identifiers longer than a felt (Ordinals, Arweave) lives in the SDK as the single domain-tagged codec per chain, so two clients cannot derive different locators for one asset.

## What This Contract Does Not Do

- No ERC-721 identity carrier.
- No mutable `update_metadata` (reveal fills an empty URI once; it never rewrites one).
- No mutable `update_licensing`.
- No `can_use_commercially` or derivative permission gates.
- No admin verification flag.
- No owner portfolio indexing in contract storage.
- No dispute adjudication — the contract records `CONFIRM`/`DISPUTE`; interpretation is platform-layer.
- No Medialane fee or governance coupling.

Those belong in immutable metadata, optional service contracts, indexers, SDKs, or application policy.
