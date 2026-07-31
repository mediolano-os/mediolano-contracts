use starknet::{ClassHash, ContractAddress};
use crate::types::{Campaign, CampaignStatus, Position};

// Protocol discovery ID registered via SRC5.
// starknet_keccak("mediolano.ip-crowdfunding-collection")
pub const IIP_CROWDFUNDING_COLLECTION_ID: felt252 =
    0x1ca39f27ea66535fc3ceda4034bf407bfba9d0e57f91ce57ee08e67564e4b06;

// starknet_keccak("mediolano.ip-crowdfunding-collection-factory")
pub const IIP_CROWDFUNDING_COLLECTION_FACTORY_ID: felt252 =
    0xb6cbd8e29167b4fca59079072e0125d765efbb8a5fe0318bc426043ddb79b9;

#[starknet::interface]
pub trait IIPCrowdfundingCollection<TContractState> {
    /// Owner-only. Opens a deadline-bound campaign and assigns the next
    /// sequential token ID. The outcome is arithmetic: at `end_time` the
    /// campaign has succeeded iff `total_raised >= goal_amount`.
    fn create_campaign(
        ref self: TContractState,
        goal_amount: u256,
        payment_token: ContractAddress,
        end_time: u64,
        metadata_uri: ByteArray,
    ) -> u256;

    /// Backs the campaign while it is live. Overfunding is welcome.
    /// Returns the amount contributed.
    fn contribute(ref self: TContractState, token_id: u256, amount: u256) -> u256;

    /// Returns part of the caller's contribution while the campaign is
    /// live. No one but the backer controls this exit.
    fn withdraw(ref self: TContractState, token_id: u256, amount: u256);

    /// Owner-only. Cancels a live campaign; contributions become refundable.
    fn cancel_campaign(ref self: TContractState, token_id: u256);

    /// Owner-only, once. Pays out the raise after a successful campaign.
    fn claim_proceeds(ref self: TContractState, token_id: u256) -> u256;

    /// Refunds the caller's full position after failure or cancellation.
    fn claim_refund(ref self: TContractState, token_id: u256) -> u256;

    /// Backer of a successful campaign, once. Mints the supporter receipt —
    /// `contributed` units of the campaign's token id. Receipts are
    /// soulbound: proof of backing, never tradable.
    fn mint_receipt(ref self: TContractState, token_id: u256);

    /// Derived from time, raise, and the cancelled flag — never stored.
    fn campaign_status(self: @TContractState, token_id: u256) -> CampaignStatus;

    /// Returns the Campaign. Panics if never created.
    fn get_campaign(self: @TContractState, token_id: u256) -> Campaign;

    /// Returns the backer's position; all-zero for addresses that never
    /// contributed.
    fn get_position(self: @TContractState, token_id: u256, backer: ContractAddress) -> Position;

    /// Number of campaigns created so far (ids are sequential from 1).
    fn campaign_count(self: @TContractState) -> u256;

    /// Collection identity, set once at deploy.
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn base_uri(self: @TContractState) -> ByteArray;

    fn version(self: @TContractState) -> ByteArray;
}

#[starknet::interface]
pub trait IIPCrowdfundingCollectionFactory<TContractState> {
    fn collection_class_hash(self: @TContractState) -> ClassHash;
    fn version(self: @TContractState) -> ByteArray;
    /// Deploys a new collection. The caller becomes its owner. `base_uri` is the
    /// collection-level metadata URI, embedded on-chain in the deploy transaction.
    fn deploy_collection(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, base_uri: ByteArray,
    ) -> ContractAddress;
}
