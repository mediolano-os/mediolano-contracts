# IP Sponsorship

`IP-Sponsorship` is a permissionless Starknet contract for negotiating
time-bound sponsorship licenses on ERC-721 IP assets. Either side can
initiate: an IP owner opens an offer on an asset they hold and sponsors bid
on it, or a sponsor proposes terms directly and the owner accepts or rejects.
On acceptance, payment settles sponsor → author directly and the license
mints atomically — as a standard ERC-721 token **of this same contract**.
There is no separate license contract: one contract is both the
offer/bid/proposal registry and the license collection, so minting only ever
happens from inside `accept_bid`/`accept_proposal`, with no cross-contract
permission to hand out and nothing else declared or deployed alongside it.

## Design

- **The asset layer is the registry.** There is no internal IP registry: an
  offer or proposal references `(nft_contract, token_id)` and the contract
  verifies `owner_of` at creation **and again at acceptance** — an offer does
  not survive the sale of the underlying asset, and a proposal binds to the
  asset (whoever owns it at acceptance time is paid and issues the license).
  Any ERC-721 IP (MIP collection, external) can be sponsored.
- **Allowance-based settlement, no escrow.** A bid or proposal is a signal
  plus an ERC-20 allowance the counterparty holds open. The contract never
  holds funds. On acceptance, the amount transfers sponsor → author directly;
  losing bidders were never charged. Retracting a bid or withdrawing a
  proposal is advisory against an acceptance in flight in the same block —
  revoking the ERC-20 allowance is the guaranteed cancel, since acceptance
  settles against that allowance.
- **One contract, no second declare/deploy.** The issued license is a real,
  standard, freely transferable ERC-721 — but it's minted internally by
  `accept_bid`/`accept_proposal`, not by a separate `IPSponsorshipLicense`
  contract with its own bootstrap handshake. Only what a real, atomic
  mechanism needs lives on-chain per license: the EIP-2981 royalty receiver
  and rate (enforced at marketplace trade time) and the token's own metadata
  URI. Everything else about the deal — the licensed asset, its expiry, its
  transferable intent — is declarative: carried in that URI's metadata and in
  the `LicenseMinted` event, never contract-enforced state. Licensing is soft
  by default per the Mediolano principles; a transferable license moves
  through ordinary `transfer_from`, regardless of declared expiry or intent.
- **Licenses are inviolable.** No revocation path exists for anyone.
- **No owner, no admin, no fee.** Offer and proposal terms are immutable (new
  terms = a new offer/proposal); `set_offer_open` is the author's only lever
  on an offer and gates new bids/acceptance, reversibly.
- **Minimal storage.** One standing bid per `(offer, sponsor)` in a map —
  rebids overwrite, history lives in keyed events. No enumerable bid, proposal,
  or active-offer lists on-chain.

## Service Asset Declaration

This service follows the shared doctrine in
[`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-sponsorship` |
| `asset_standard` | ERC721 (this same contract issues the license) |
| `asset_role` | Time-bound sponsorship license over an external ERC-721 IP; the token holder is the current licensee |
| `transferability` | Transferable — declared intent lives in metadata only, never contract-enforced |
| `access_semantics` | Current ownership of the license token id |
| `marketplace_visibility` | Standard ERC-721 — listable anywhere; EIP-2981 royalty to the IP author |
| `metadata_uri_policy` | `ipfs://` or `ar://` for license terms (the token URI is the terms document) |
| `src5_interface_id` | `IIP_SPONSORSHIP_ID` + `IERC2981_ID` + `ILICENSED_COLLECTION_ID` |

## Interface

```cairo
fn create_offer(
    nft_contract: ContractAddress,
    token_id: u256,
    min_amount: u256,
    duration: u64,
    payment_token: ContractAddress,
    license_terms_uri: ByteArray,
    transferable: bool,
    royalty_bps: u256,                           // EIP-2981 royalty to the author on license resale
    specific_sponsor: Option<ContractAddress>,
) -> u256;                                       // caller must own the IP

fn set_offer_open(offer_id: u256, open: bool);   // offer author only
fn place_bid(offer_id: u256, amount: u256);      // >= min_amount; rebid overwrites
fn retract_bid(offer_id: u256);
fn accept_bid(offer_id: u256, sponsor: ContractAddress) -> u256; // author only; settles + mints the license

// A sponsor proposes terms on an asset with no open offer yet — the
// symmetric counterpart to create_offer. Any caller may propose; only the
// asset's current owner may accept or reject. valid_until is an acceptance
// deadline (unix seconds; 0 = no deadline).
fn propose_sponsorship(
    nft_contract: ContractAddress,
    token_id: u256,
    amount: u256,
    duration: u64,
    valid_until: u64,
    payment_token: ContractAddress,
    license_terms_uri: ByteArray,
    transferable: bool,
    royalty_bps: u256,
) -> u256;
fn withdraw_proposal(proposal_id: u256);         // proposer only
fn accept_proposal(proposal_id: u256) -> u256;   // asset owner only; settles + mints the license
fn reject_proposal(proposal_id: u256);           // asset owner only

fn get_offer(offer_id: u256) -> SponsorshipOffer;
fn get_bid(offer_id: u256, sponsor: ContractAddress) -> u256;
fn get_proposal(proposal_id: u256) -> SponsorshipProposal;
fn get_last_offer_id() -> u256;
fn get_last_proposal_id() -> u256;
fn get_last_license_id() -> u256;
fn royalty_info(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn royaltyInfo(token_id: u256, sale_price: u256) -> (ContractAddress, u256);
fn version() -> ByteArray;
```

Plus standard ERC-721 (`name`/`symbol`/`token_uri`/`balance_of`/`owner_of`/
`transfer_from`/`approve`/…) and SRC5 discovery — this contract embeds the
license collection directly, so a transferable license moves through the
standard `transfer_from`/`safe_transfer_from`; there is no bespoke transfer
entrypoint and no second contract address to look up.

Custom SRC5 interface ID:

```cairo
// starknet_keccak("mediolano.ip-sponsorship.v3")
IIP_SPONSORSHIP_ID =
0x2acdd68e9e446816f8a4f4667264ce04d0bc9b85a519f7db14c0cf08a606ef3
```

Rules:

- `specific_sponsor` restricts bidding to one invited address (private
  negotiation targeting); bid *amounts* are public on-chain — sealed-bid
  privacy is a commercial-layer concern built on top, not in this primitive.
- Acceptance (of a bid or a proposal) re-verifies IP ownership, closes the
  offer/proposal, consumes the bid, mints the license to the sponsor, then
  settles payment (checks-effects-interactions; a failing transfer reverts
  everything, including the mint).

## Build & Test

```bash
scarb build
snforge test   # 45 tests
```

## Status

Design complete, contract-tested, **not yet declared or deployed**. The
currently-live mainnet contract
(`0x044d9b9c3bb29b94685b0a3fe27a5e2dfa30a3637ab55979c718ebcd3268bc2f`, deployed
2026-07-02) predates this redesign and remains valid for its existing offers —
it does not have `propose_sponsorship`/symmetric proposals, and its accepted-bid
receipts mint through a second, separately deployed `MIP-IP-Factory-ERC721`
instance rather than this contract itself.
