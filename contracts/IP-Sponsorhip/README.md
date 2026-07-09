# IP Sponsorship

`IP-Sponsorship` is a permissionless Starknet contract for negotiating
time-bound sponsorship licenses on ERC-721 IP assets. An IP owner creates an
offer on an asset they hold; sponsors place bids; the owner accepts one;
payment settles sponsor → author directly and the license is minted as a
standard ERC-721 on the shared `IPSponsorshipLicense` contract — holdable,
listable, and visible to any ERC-721-aware wallet, marketplace, or agent.

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
  license runs to its expiry (valid strictly before `expires_at`). Licensing
  is soft-enforced by default per the Mediolano principles; breach disputes
  are off-chain matters. Transferability is fixed per offer at creation and
  enforced in the license token's own transfer hook: a transferable,
  unexpired license moves through ordinary `transfer_from`. Resales pay an
  EIP-2981 royalty to the original IP author (basis points fixed per offer).
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
| `asset_standard` | ERC721 (`IPSponsorshipLicense`, one shared contract) |
| `asset_role` | Time-bound sponsorship license over an external ERC-721 IP; the token holder is the current licensee |
| `transferability` | Per offer (`transferable` flag, fixed at creation, enforced in the token's transfer hook; expired licenses cannot transfer) |
| `access_semantics` | `is_license_valid(license_id)` derives validity from existence + expiry |
| `marketplace_visibility` | Standard ERC-721 — listable anywhere; EIP-2981 royalty to the IP author |
| `metadata_uri_policy` | `ipfs://` or `ar://` for license terms (the token URI is the terms document) |
| `src5_interface_id` | `IIP_SPONSORSHIP_ID` (registry); `IIP_SPONSORSHIP_LICENSE_ID` + `IERC2981_ID` + `ILICENSED_COLLECTION_ID` (license token) |

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
fn accept_bid(offer_id: u256, sponsor: ContractAddress) -> u256; // author only; settles + mints the license NFT

fn get_offer(offer_id: u256) -> SponsorshipOffer;
fn get_bid(offer_id: u256, sponsor: ContractAddress) -> u256;
fn get_license(license_id: u256) -> LicenseData;
fn is_license_valid(license_id: u256) -> bool;
fn get_last_offer_id() -> u256;
fn get_last_license_id() -> u256;
fn get_license_contract() -> ContractAddress;
fn version() -> ByteArray;
```

A transferable license moves through the license token's standard ERC-721
`transfer_from`/`safe_transfer_from` — there is no bespoke transfer
entrypoint. `IPSponsorshipLicense` is minted only by the registry (one-time
`set_minter` bootstrap; both contracts are ownerless afterwards) and exposes
`get_license_data`, `is_license_valid`, `last_license_id`, `royalty_info`,
and `version()`.

Rules:

- `specific_sponsor` restricts bidding to one invited address (private
  negotiation targeting); bid *amounts* are public on-chain — sealed-bid
  privacy is a commercial-layer concern built on top, not in this primitive.
- Acceptance re-verifies IP ownership, closes the offer, consumes the bid,
  mints the license NFT to the sponsor, then settles payment
  (checks-effects-interactions; a failing transfer reverts everything,
  including the mint).

## Build & Test

```bash
scarb build
snforge test   # 33 tests
```

## Status

Deployed to Starknet mainnet 2026-07-02:
`0x044d9b9c3bb29b94685b0a3fe27a5e2dfa30a3637ab55979c718ebcd3268bc2f`. Accepted-bid
receipt NFTs mint through a second, dedicated `MIP-IP-Factory-ERC721` instance
(`0x06bcfc4e97758a2abf95af4bd49596efdbfd88ccd740caddc56ad0a4bd095839`), never the
genesis-mint instance — the receipt is a non-authoritative convenience;
`is_license_valid()` on this contract is the sole access check.
