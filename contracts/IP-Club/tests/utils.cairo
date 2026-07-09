use ip_club::interfaces::IIPClub::IIPClubDispatcher;
use ip_club::interfaces::IIPClubNFT::IIPClubNFTDispatcher;
use ip_club::mocks::MockERC20::{IERC20MintDispatcher, IERC20MintDispatcherTrait};
use openzeppelin_token::erc20::interface::IERC20Dispatcher;
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::{ClassHash, ContractAddress};

pub const ONE_E18: u256 = 1000000000000000000_u256;

pub fn CREATOR() -> ContractAddress {
    0x101.try_into().unwrap()
}

pub fn USER1() -> ContractAddress {
    0x102.try_into().unwrap()
}

pub fn USER2() -> ContractAddress {
    0x103.try_into().unwrap()
}

pub fn ZERO_ADDRESS() -> ContractAddress {
    0.try_into().unwrap()
}

pub fn declare_and_deploy(contract_name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

pub fn deploy_erc20() -> IERC20Dispatcher {
    let mut calldata = array![];
    let initial_supply: u256 = 1000_000_000_u256;
    let name: ByteArray = "DummyERC20";
    let symbol: ByteArray = "DUMMY";

    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(initial_supply);
    let erc20_address = declare_and_deploy("MockERC20", calldata);
    IERC20Dispatcher { contract_address: erc20_address }
}

pub fn mint_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) {
    IERC20MintDispatcher { contract_address: token }.mint(recipient, amount)
}

pub fn deploy_ip_club_contract(ip_club_nft_class_hash: ClassHash) -> IIPClubDispatcher {
    let mut calldata = array![];
    calldata.append_serde(ip_club_nft_class_hash);
    let manager_contract = declare_and_deploy("IPClub", calldata);
    IIPClubDispatcher { contract_address: manager_contract }
}

pub fn deploy_ip_club_nft(
    name: ByteArray,
    symbol: ByteArray,
    club_id: u256,
    creator: ContractAddress,
    ip_club_manager: ContractAddress,
    metadata_uri: ByteArray,
    transfer_lock: Option<u64>,
    royalty_bps: u256,
) -> IIPClubNFTDispatcher {
    let mut calldata = array![];
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(club_id);
    calldata.append_serde(creator);
    calldata.append_serde(ip_club_manager);
    calldata.append_serde(metadata_uri);
    calldata.append_serde(transfer_lock);
    calldata.append_serde(royalty_bps);
    let ip_club_nft = declare_and_deploy("IPClubNFT", calldata);
    IIPClubNFTDispatcher { contract_address: ip_club_nft }
}

pub fn deploy_receiver() -> ContractAddress {
    declare_and_deploy("Receiver", array![])
}

pub fn deploy_reentrant_payment_token(ip_club: ContractAddress, club_id: u256) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(ip_club);
    calldata.append_serde(club_id);
    declare_and_deploy("ReentrantPaymentToken", calldata)
}

#[derive(Drop, Clone)]
pub struct TestContracts {
    pub ip_club: IIPClubDispatcher,
    pub erc20_token: IERC20Dispatcher,
}


pub fn initialize_contracts() -> TestContracts {
    let erc20_token = deploy_erc20();
    let ip_club_nft = declare("IPClubNFT").unwrap().contract_class();
    let ip_club = deploy_ip_club_contract(*ip_club_nft.class_hash);

    TestContracts { ip_club, erc20_token }
}
