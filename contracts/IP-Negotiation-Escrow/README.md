# IP Negotiation Escrow

`IPNegotiationEscrow` is a Mediolano service contract for escrowed negotiation around an existing IP asset.

A seller creates a listing asset that points to the IP asset being negotiated, the asking price, listing metadata, and proposed terms. A buyer funds the escrow, the seller submits fulfillment or license-transfer proof, and the buyer approves release to the seller.

## Service Declaration

| Field | Value |
| --- | --- |
| `service_id` | `ip-negotiation-escrow` |
| `asset_standard` | ERC721 |
| `asset_role` | Non-transferable negotiation listing / escrow record for an existing IP asset |
| `transferability` | non-transferable |
| `access_semantics` | Listing state, buyer approval, seller claims, and buyer refunds derive from escrow records, not from transfer of the ERC-721 |
| `marketplace_visibility` | display/index as a negotiation listing asset; no default resale |
| `metadata_uri_policy` | listing, terms, and fulfillment URIs must be `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_NEGOTIATION_ESCROW_ID` |

## Negotiation Flow

1. The seller calls `create_listing` with:
   - existing IP asset contract;
   - existing IP asset token ID;
   - ERC-20 payment token;
   - price;
   - content-addressed listing URI and hash;
   - content-addressed terms URI and hash;
   - deadline.
2. The contract mints a non-transferable ERC-721 negotiation listing asset to the seller.
3. A buyer calls `fund_listing`, depositing the full price into escrow.
4. The seller calls `submit_fulfillment` with a content-addressed fulfillment or license-transfer proof.
5. The buyer calls `approve_fulfillment`.
6. The approved amount becomes claimable by the seller through `claim_seller_funds`.

## Payment And Refunds

The full price is escrowed up front. Deposits validate exact ERC-20 receipt by comparing the escrow contract balance before and after `transfer_from`.

Seller payouts and buyer refunds are pull based. Approval creates a seller claim; expired funded cancellation creates a buyer refund claim.

The seller can cancel an open listing before it is funded. Once funded, the buyer can cancel only after the deadline and only while the seller has not submitted fulfillment.

## IP Asset Semantics

The ERC-721 minted by this contract is a negotiation listing record, not the underlying IP asset. It is non-transferable and exists for marketplace display, indexer discovery, and protocol state anchoring.

This contract records the referenced IP asset and fulfillment proof, but it does not transfer the external IP NFT or enforce an off-chain legal license. A future adapter can wire explicit asset-transfer behavior if the protocol wants atomic settlement against a known asset standard.

## Non-Goals

- No admin, upgrade, pause, or dispute-arbitration role exists.
- No external IP asset transfer is performed by this version.
- No partial funding or bid ladder exists in this version.
- No off-chain legal interpretation is performed.
- No unilateral cancellation exists after fulfillment has been submitted.

Custom SRC5 interface ID:

```cairo
pub const IIP_NEGOTIATION_ESCROW_ID: felt252 =
    0x0148a3c45c2f9c346979ac40c2783ef0c0d4fd028dbf7097d15a925fe601c54d;
```
