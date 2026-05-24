# IP Commission Escrow

`IPCommissionEscrow` is a Mediolano service contract for commissioning custom creative work through an escrowed marketplace offer.

A commissioner creates an offer asset with a brief, usage-license terms, payment token, and milestone schedule. The offer can be open to any creator or exclusive to one invited creator/account.

## Service Declaration

| Field | Value |
| --- | --- |
| `service_id` | `ip-commission-escrow` |
| `asset_standard` | ERC721 |
| `asset_role` | Non-transferable commission offer / escrow record |
| `transferability` | non-transferable |
| `access_semantics` | Commission state, milestone approval, creator claims, and commissioner refunds derive from escrow records, not from transfer of the ERC-721 |
| `marketplace_visibility` | display/index as an offer asset; no default listing or resale |
| `metadata_uri_policy` | brief, license, and deliverable URIs must be `ipfs://` or `ar://` |
| `src5_interface_id` | `IIP_COMMISSION_ESCROW_ID` |

## Commission Flow

1. The commissioner calls `create_commission` with:
   - optional invited creator;
   - ERC-20 payment token;
   - total payment amount;
   - content-addressed brief URI and hash;
   - content-addressed license URI and hash;
   - revision allowance;
   - deadline;
   - milestone amounts.
2. The contract mints a non-transferable ERC-721 offer asset to the commissioner.
3. The commissioner calls `fund_commission`, depositing the full total amount into escrow.
4. The creator calls `accept_commission`.
5. The creator submits each milestone with `submit_milestone`.
6. The commissioner either calls `request_revision` or `approve_milestone`.
7. Approved milestone amounts become claimable by the creator through `claim_creator_funds`.
8. The commission completes when every milestone is approved.

## Open And Exclusive Offers

If `invited_creator` is zero, the offer is open and any non-commissioner account can accept after funding.

If `invited_creator` is non-zero, the offer is exclusive and only that account can accept.

## Payment And Refunds

The full commission amount is escrowed before acceptance. Milestones split release timing, not funding custody.

Deposits validate exact ERC-20 receipt by comparing the escrow contract balance before and after `transfer_from`.

The commissioner can cancel only while the commission is `Open` or `Funded`. Funded cancellations create a pull refund claim through `claim_commissioner_refund`.

If a commission is already in progress and the deadline passes, the commissioner can cancel and recover only unreleased escrow. Any already approved milestone amount remains claimable by the creator.

## License Semantics

The contract records a content-addressed license pointer and hash. It does not enforce copyright, usage rights, attribution, or off-chain delivery obligations. Those terms are declared for marketplace display, indexers, and off-chain legal or workflow enforcement.

## Non-Goals

- No admin, upgrade, pause, or dispute-arbitration role exists.
- No off-chain creative quality judgment is performed.
- No copyright transfer is assumed by payment alone.
- No partial funding model exists in this version.
- No post-acceptance unilateral cancellation exists before the deadline.

Custom SRC5 interface ID:

```cairo
pub const IIP_COMMISSION_ESCROW_ID: felt252 =
    0x020b1655b35dced41a9f0c857992e8dffdf747d83ddc9e922b572a6d8dcc3d08;
```
