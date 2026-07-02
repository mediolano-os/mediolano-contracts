# IP Sponsorship

`IP-Sponsorship` is a permissionless Starknet contract for negotiating
time-bound sponsorship licenses on ERC-721 IP assets. An IP owner creates an
offer on an asset they hold; sponsors place bids; the owner accepts one;
payment settles sponsor → author directly and a license record is issued.

## Design

- **The asset layer is the registry.** There is no internal IP registry: an
  offer references `(nft_contract, token_id)` and the contract verifies
  `owner_of` at offer creation **and again at acceptance** — an offer does
  not survive the sale of the underlying asset. Any ERC-721 IP (MIP
  collection, external) can be sponsored.
- **Allowance-based settlement, no escrow.** A bid is a signal plus an ERC-20
  allowance the sponsor holds open. The contract never holds funds. On
  acceptance, the accepted amount transfers sponsor → author directly; losing
  bidders were never charged. A sponsor withdraws by `retract_bid` (or
  economically by revoking the allowance — acceptance then reverts
  atomically).
- **Licenses are inviolable.** No revocation path exists for anyone — a paid
  license runs to its expiry (`expires_at >= now`, inclusive). Licensing is
  soft-enforced by default per the Mediolano principles; breach disputes are
  off-chain matters. Transferability is fixed per offer at creation.
- **No owner, no admin, no fee.** Offer terms are immutable (new terms = new
  offer); `set_offer_open` is the author's only lever and gates new bids and
  acceptance, reversibly.
- **Minimal storage.** One standing bid per `(offer, sponsor)` in a map —
  rebids overwrite, history lives in keyed events. No enumerable bid lists,
  user lists, or active-offer lists on-chain.

## Service Asset Declaration

This service follows the shared doctrine in
[`docs/SERVICE_ASSET_DOCTRINE.md`](../../docs/SERVICE_ASSET_DOCTRINE.md).

| Field | Value |
| --- | --- |
| `service_id` | `ip-sponsorship` |
| `asset_standard` | None in the current implementation (license is a record) |
| `asset_role` | Time-bound sponsorship license over an external ERC-721 IP |
| `transferability` | Per offer (`transferable` flag, fixed at creation) |
| `access_semantics` | `is_license_valid(license_id)` derives validity from expiry |
| `marketplace_visibility` | Offer/license visibility via keyed events; no asset listing |
| `metadata_uri_policy` | `ipfs://` or `ar://` for license terms |
| `src5_interface_id` | `IIP_SPONSORSHIP_ID` |

If the license becomes asset-backed later, it should be designed explicitly
as a transferable ERC-721 license token; today it is deliberately a record.

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
    specific_sponsor: Option<ContractAddress>,
) -> u256;                                       // caller must own the IP

fn set_offer_open(offer_id: u256, open: bool);   // offer author only
fn place_bid(offer_id: u256, amount: u256);      // >= min_amount; rebid overwrites
fn retract_bid(offer_id: u256);
fn accept_bid(offer_id: u256, sponsor: ContractAddress) -> u256; // author only; settles + issues license

fn transfer_license(license_id: u256, to: ContractAddress);      // holder only, if transferable, before expiry

fn get_offer(offer_id: u256) -> SponsorshipOffer;
fn get_bid(offer_id: u256, sponsor: ContractAddress) -> u256;
fn get_license(license_id: u256) -> License;
fn is_license_valid(license_id: u256) -> bool;
fn get_last_offer_id() -> u256;
fn get_last_license_id() -> u256;
```

Rules:

- `specific_sponsor` restricts bidding to one invited address (private
  negotiation targeting); bid *amounts* are public on-chain — sealed-bid
  privacy is a commercial-layer concern built on top, not in this primitive.
- Acceptance re-verifies IP ownership, closes the offer, consumes the bid,
  records the license, then settles payment (checks-effects-interactions; a
  failing transfer reverts everything).

## Build & Test

```bash
scarb build
snforge test   # 24 tests
```

## Status

Deployed to Starknet mainnet 2026-07-02:
`0x044d9b9c3bb29b94685b0a3fe27a5e2dfa30a3637ab55979c718ebcd3268bc2f`. Accepted-bid
receipt NFTs mint through a second, dedicated `MIP-IP-Factory-ERC721` instance
(`0x06bcfc4e97758a2abf95af4bd49596efdbfd88ccd740caddc56ad0a4bd095839`), never the
genesis-mint instance — the receipt is a non-authoritative convenience;
`is_license_valid()` on this contract is the sole access check.
