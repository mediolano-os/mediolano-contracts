use ip_ticket::interface::{
    IIPTicketServiceDispatcher, IIPTicketServiceDispatcherTrait, IIP_TICKET_SERVICE_ID,
};
use ip_ticket::mock::mock_erc20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_block_timestamp, cheat_caller_address,
    declare,
};
use starknet::ContractAddress;

fn CREATOR() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn USER1() -> ContractAddress {
    0x102.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn IPFS_URI() -> ByteArray {
    "ipfs://bafybeiticket"
}

fn AR_URI() -> ByteArray {
    "ar://ticket-series"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/ticket.json"
}

fn declare_and_deploy(contract_name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_ticket_service() -> IIPTicketServiceDispatcher {
    let mut calldata = array![];
    let name: ByteArray = "IP Tickets";
    let symbol: ByteArray = "IPT";
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    let address = declare_and_deploy("IPTicketService", calldata);
    IIPTicketServiceDispatcher { contract_address: address }
}

fn deploy_erc20() -> IERC20Dispatcher {
    let mut calldata = array![];
    let name: ByteArray = "Mock Token";
    let symbol: ByteArray = "MOCK";
    let supply: u256 = 0;
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(supply);
    let address = declare_and_deploy("MockERC20", calldata);
    IERC20Dispatcher { contract_address: address }
}

fn mint_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) {
    IERC20MintDispatcher { contract_address: token }.mint(recipient, amount);
}

fn deploy_receiver() -> ContractAddress {
    declare_and_deploy("Receiver", array![])
}

fn deploy_reentrant_payment_token(
    ticket_service: ContractAddress, series_id: u256,
) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(ticket_service);
    calldata.append_serde(series_id);
    declare_and_deploy("ReentrantPaymentToken", calldata)
}

fn create_free_series(ticket_service: IIPTicketServiceDispatcher, expiration: u64) -> u256 {
    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service.create_ticket_series(0, 10, expiration, 500, Option::None, IPFS_URI())
}

#[test]
fn test_create_ticket_series() {
    let ticket_service = deploy_ticket_service();

    let series_id = create_free_series(ticket_service, 10_000);

    assert(series_id == 1, 'series id should be 1');
    assert(ticket_service.get_last_series_id() == 1, 'last series id');

    let series = ticket_service.get_ticket_series(series_id);
    assert(series.creator == CREATOR(), 'creator should match');
    assert(series.max_supply == 10, 'max supply should match');
    assert(series.royalty_bps == 500, 'royalty should match');
    assert(series.metadata_uri == IPFS_URI(), 'metadata should match');
}

#[test]
fn test_create_ticket_series_accepts_ar_uri() {
    let ticket_service = deploy_ticket_service();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let series_id = ticket_service.create_ticket_series(0, 10, 10_000, 0, Option::None, AR_URI());

    assert(ticket_service.get_ticket_series(series_id).metadata_uri == AR_URI(), 'ar uri');
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_create_ticket_series_rejects_http_uri() {
    let ticket_service = deploy_ticket_service();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service.create_ticket_series(0, 10, 10_000, 0, Option::None, HTTP_URI());
}

#[test]
#[should_panic(expected: 'Max supply is zero')]
fn test_create_ticket_series_rejects_zero_supply() {
    let ticket_service = deploy_ticket_service();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service.create_ticket_series(0, 0, 10_000, 0, Option::None, IPFS_URI());
}

#[test]
#[should_panic(expected: 'Expiration must be future')]
fn test_create_ticket_series_rejects_past_expiration() {
    let ticket_service = deploy_ticket_service();

    cheat_block_timestamp(ticket_service.contract_address, 10_000, CheatSpan::TargetCalls(1));
    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service.create_ticket_series(0, 10, 1_000, 0, Option::None, IPFS_URI());
}

#[test]
#[should_panic(expected: 'Royalty exceeds 10000')]
fn test_create_ticket_series_rejects_bad_royalty() {
    let ticket_service = deploy_ticket_service();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service.create_ticket_series(0, 10, 10_000, 10_001, Option::None, IPFS_URI());
}

#[test]
#[should_panic]
fn test_paid_ticket_requires_token() {
    let ticket_service = deploy_ticket_service();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service.create_ticket_series(100, 10, 10_000, 0, Option::None, IPFS_URI());
}

#[test]
#[should_panic(expected: 'Free ticket cannot use token')]
fn test_free_ticket_rejects_token() {
    let ticket_service = deploy_ticket_service();
    let erc20 = deploy_erc20();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    ticket_service
        .create_ticket_series(0, 10, 10_000, 0, Option::Some(erc20.contract_address), IPFS_URI());
}

#[test]
fn test_mint_free_ticket() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_block_timestamp(ticket_service.contract_address, 1_000, CheatSpan::TargetCalls(1));
    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    let token_id = ticket_service.mint_ticket(series_id);

    assert(token_id == 1, 'token id should be one');
    assert(ticket_service.total_supply() == 1, 'total supply should be one');
    assert(ticket_service.has_valid_ticket(receiver, series_id), 'receiver should be valid');
    assert(ticket_service.get_active_ticket_balance(receiver, series_id) == 1, 'active balance');

    let erc721 = IERC721Dispatcher { contract_address: ticket_service.contract_address };
    assert(erc721.owner_of(token_id) == receiver, 'owner should be receiver');

    let metadata = IERC721MetadataDispatcher { contract_address: ticket_service.contract_address };
    assert(metadata.token_uri(token_id) == IPFS_URI(), 'token uri should match');
}

#[test]
fn test_paid_ticket_transfers_tokens() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();
    let erc20 = deploy_erc20();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let series_id = ticket_service
        .create_ticket_series(
            1000, 10, 10_000, 0, Option::Some(erc20.contract_address), IPFS_URI(),
        );

    mint_erc20(erc20.contract_address, receiver, 3000);
    cheat_caller_address(erc20.contract_address, receiver, CheatSpan::TargetCalls(1));
    erc20.approve(ticket_service.contract_address, 1000);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.mint_ticket(series_id);

    assert(erc20.balance_of(CREATOR()) == 1000, 'creator should be paid');
    assert(erc20.balance_of(receiver) == 2000, 'buyer should pay');
}

#[test]
#[should_panic(expected: 'Max supply reached')]
fn test_mint_ticket_rejects_over_supply() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let series_id = ticket_service.create_ticket_series(0, 1, 10_000, 0, Option::None, IPFS_URI());

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.mint_ticket(series_id);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.mint_ticket(series_id);
}

#[test]
#[should_panic(expected: 'Ticket series expired')]
fn test_mint_ticket_rejects_expired_series() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_block_timestamp(ticket_service.contract_address, 10_000, CheatSpan::TargetCalls(1));
    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.mint_ticket(series_id);
}

#[test]
#[should_panic]
fn test_mint_to_non_receiver_rejected() {
    let ticket_service = deploy_ticket_service();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_caller_address(
        ticket_service.contract_address, ticket_service.contract_address, CheatSpan::TargetCalls(1),
    );
    ticket_service.mint_ticket(series_id);
}

#[test]
fn test_transfer_moves_access() {
    let ticket_service = deploy_ticket_service();
    let receiver_1 = deploy_receiver();
    let receiver_2 = deploy_receiver();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_caller_address(ticket_service.contract_address, receiver_1, CheatSpan::TargetCalls(1));
    let token_id = ticket_service.mint_ticket(series_id);

    let erc721 = IERC721Dispatcher { contract_address: ticket_service.contract_address };
    cheat_caller_address(ticket_service.contract_address, receiver_1, CheatSpan::TargetCalls(1));
    erc721.transfer_from(receiver_1, receiver_2, token_id);

    assert(!ticket_service.has_valid_ticket(receiver_1, series_id), 'sender should lose access');
    assert(ticket_service.has_valid_ticket(receiver_2, series_id), 'receiver should gain access');
    assert(ticket_service.get_active_ticket_balance(receiver_1, series_id) == 0, 'sender bal');
    assert(ticket_service.get_active_ticket_balance(receiver_2, series_id) == 1, 'receiver bal');
}

#[test]
fn test_redeem_ticket_removes_access() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    let token_id = ticket_service.mint_ticket(series_id);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.redeem_ticket(token_id);

    assert(!ticket_service.has_valid_ticket(receiver, series_id), 'redeemed loses access');
    let data = ticket_service.get_ticket_data(token_id);
    assert(data.redeemed, 'ticket should be redeemed');
    assert(!data.valid, 'ticket should be invalid');
}

#[test]
#[should_panic(expected: 'Ticket already redeemed')]
fn test_cannot_redeem_twice() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    let token_id = ticket_service.mint_ticket(series_id);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.redeem_ticket(token_id);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    ticket_service.redeem_ticket(token_id);
}

#[test]
fn test_royalty_info() {
    let ticket_service = deploy_ticket_service();
    let receiver = deploy_receiver();
    let series_id = create_free_series(ticket_service, 10_000);

    cheat_caller_address(ticket_service.contract_address, receiver, CheatSpan::TargetCalls(1));
    let token_id = ticket_service.mint_ticket(series_id);

    let (recipient, amount) = ticket_service.royaltyInfo(token_id, 1000);
    assert(recipient == CREATOR(), 'royalty recipient');
    assert(amount == 50, 'royalty amount');
}

#[test]
#[should_panic]
fn test_royalty_info_rejects_missing_token() {
    let ticket_service = deploy_ticket_service();

    ticket_service.royaltyInfo(999, 1000);
}

#[test]
#[should_panic(expected: 'Reentrant mint')]
fn test_reentrant_payment_token_rejected() {
    let ticket_service = deploy_ticket_service();
    let expected_series_id = 1;
    let token = deploy_reentrant_payment_token(ticket_service.contract_address, expected_series_id);

    cheat_caller_address(ticket_service.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
    let series_id = ticket_service
        .create_ticket_series(1000, 10, 10_000, 0, Option::Some(token), IPFS_URI());
    assert(series_id == expected_series_id, 'expected first series');

    cheat_caller_address(ticket_service.contract_address, USER1(), CheatSpan::TargetCalls(1));
    ticket_service.mint_ticket(series_id);
}

#[test]
fn test_supports_ticket_service_interface() {
    let ticket_service = deploy_ticket_service();
    let src5 = ISRC5Dispatcher { contract_address: ticket_service.contract_address };

    assert(src5.supports_interface(IIP_TICKET_SERVICE_ID), 'interface supported');
}
