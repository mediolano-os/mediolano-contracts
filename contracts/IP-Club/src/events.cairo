use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct NewClubCreated {
    #[key]
    pub club_id: u256,
    #[key]
    pub creator: ContractAddress,
    pub metadata_uri: ByteArray,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct ClubClosed {
    #[key]
    pub club_id: u256,
    #[key]
    pub creator: ContractAddress,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct NewMember {
    #[key]
    pub club_id: u256,
    #[key]
    pub member: ContractAddress,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct NftMinted {
    #[key]
    pub club_id: u256,
    #[key]
    pub token_id: u256,
    #[key]
    pub recipient: ContractAddress,
    pub timestamp: u64,
}
