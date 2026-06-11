use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct NewClubCreated {
    #[key]
    pub club_id: u256,
    #[key]
    pub creator: ContractAddress,
    pub club_nft: ContractAddress,
    pub metadata_uri: ByteArray,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct ClubStatusUpdated {
    #[key]
    pub club_id: u256,
    pub open: bool,
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
pub struct MemberLeft {
    #[key]
    pub club_id: u256,
    #[key]
    pub member: ContractAddress,
    pub timestamp: u64,
}

