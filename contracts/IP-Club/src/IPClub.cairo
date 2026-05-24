#[starknet::contract]
pub mod IPClub {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::events::{ClubClosed, NewClubCreated, NewMember};
    use crate::interfaces::IIPClub::{IIPClub, IIP_CLUB_ID};
    use crate::interfaces::IIPClubNFT::{IIPClubNFTDispatcher, IIPClubNFTDispatcherTrait};
    use crate::types::{ClubRecord, ClubStatus, bytearray_starts_with};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        ip_club_nft_class_hash: ClassHash, // Class hash for club NFT contracts
        last_club_id: u256, // Last used club ID
        clubs: Map<u256, ClubRecord>, // Mapping from club ID to club record
        join_locked: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        NewClubCreated: NewClubCreated, // Emitted when a new club is created
        NewMember: NewMember, // Emitted when a new member joins a club
        ClubClosed: ClubClosed // Emitted when a club is closed
    }

    #[constructor]
    fn constructor(ref self: ContractState, ip_club_nft_class_hash: ClassHash) {
        assert(ip_club_nft_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.src5.register_interface(IIP_CLUB_ID);
        self.ip_club_nft_class_hash.write(ip_club_nft_class_hash); // Store NFT class hash
    }

    #[abi(embed_v0)]
    impl IPClubImpl of IIPClub<ContractState> {
        /// Creates a new club and deploys its associated NFT contract.
        /// # Description
        /// This function initializes a new club entity and deploys a dedicated NFT contract for it.
        fn create_club(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            metadata_uri: ByteArray,
            max_members: Option<u32>,
            entry_fee: Option<u256>,
            payment_token: Option<ContractAddress>,
        ) -> u256 {
            assert(name.len() > 0, 'Name must not be empty');
            assert(symbol.len() > 0, 'Symbol must not be empty');
            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if let Option::Some(max) = max_members {
                assert(max > 0, 'Max members cannot be zero');
            }

            assert(
                (entry_fee.is_some() && payment_token.is_some())
                    || (entry_fee.is_none() && payment_token.is_none()),
                'Invalid fee configuration',
            );

            if let Option::Some(fee) = entry_fee {
                assert(fee > 0, 'Entry fee cannot be zero');
            }

            if let Option::Some(token) = payment_token {
                assert(!token.is_zero(), 'Payment token cannot be null');
            }

            let ip_club_manager = get_contract_address(); // Address of this contract
            let creator = get_caller_address(); // Club creator
            assert(!creator.is_zero(), 'Creator is zero address');
            let next_club_id = self.last_club_id.read() + 1; // Increment club ID
            let deploy_salt = PoseidonTrait::new()
                .update_with(creator)
                .update_with(next_club_id)
                .finalize();

            let mut constructor_calldata: Array<felt252> = array![];

            // Serialize constructor arguments for NFT contract
            (
                name.clone(),
                symbol.clone(),
                next_club_id,
                creator,
                ip_club_manager,
                metadata_uri.clone(),
            )
                .serialize(ref constructor_calldata);

            // Deploy the NFT contract for the club
            let (ip_club_nft_address, _) = deploy_syscall(
                self.ip_club_nft_class_hash.read(), deploy_salt, constructor_calldata.span(), false,
            )
                .unwrap();

            // Create and store the club record
            let club_record = ClubRecord {
                id: next_club_id,
                name,
                symbol,
                metadata_uri: metadata_uri.clone(),
                status: ClubStatus::Open,
                num_members: 0,
                creator,
                club_nft: ip_club_nft_address,
                max_members,
                entry_fee,
                payment_token,
            };

            self.clubs.entry(next_club_id).write(club_record);
            self.last_club_id.write(next_club_id);

            // Emit event for new club creation
            self
                .emit(
                    NewClubCreated {
                        club_id: next_club_id,
                        creator,
                        metadata_uri,
                        timestamp: get_block_timestamp(),
                    },
                );

            next_club_id
        }

        /// Closes an existing club, removing it from the registry.
        /// # Access Control
        /// Only the creator of the club can call this function.
        /// # Arguments
        /// * `club_id` - The unique identifier of the club to close.
        fn close_club(ref self: ContractState, club_id: u256) {
            let mut club_record = self.clubs.entry(club_id).read();
            let caller = get_caller_address();

            assert(club_record.status != ClubStatus::Inactive, 'Club does not exist');
            assert(club_record.status == ClubStatus::Open, 'Club not open');
            assert(club_record.creator == caller, 'Not Authorized');

            club_record.status = ClubStatus::Closed;
            self.clubs.entry(club_id).write(club_record);

            // Emit event for club closure
            self.emit(ClubClosed { club_id, creator: caller, timestamp: get_block_timestamp() });
        }

        /// Allows a user to join a club by minting a membership NFT and transferring the entry fee
        /// if required.
        /// # Details
        /// This function manages the club membership process, including:
        /// - Minting a membership NFT for the user.
        /// - Processing the entry fee payment if an entry fee is specified.
        /// # Access Control
        /// Accessible to any user wishing to join a club.
        fn join_club(ref self: ContractState, club_id: u256) {
            let mut club_record = self.clubs.entry(club_id).read();

            let caller = get_caller_address();

            assert(!caller.is_zero(), 'Caller is zero address');
            assert(club_record.status != ClubStatus::Inactive, 'Club does not exist');
            assert(club_record.status == ClubStatus::Open, 'Club not open');

            let is_member = self.is_member(club_id, caller);
            assert(!is_member, 'Already a member');

            // Check if club is full
            if let Option::Some(max) = club_record.max_members {
                assert(club_record.num_members < max, 'Club full');
            }

            assert(!self.join_locked.read(), 'Reentrant join');
            self.join_locked.write(true);

            let creator = club_record.creator;
            let club_nft = club_record.club_nft;
            let entry_fee = club_record.entry_fee;
            let payment_token = club_record.payment_token;

            club_record.num_members += 1;
            self.clubs.entry(club_id).write(club_record);

            // Handle entry fee payment if required
            if let Option::Some(fee) = entry_fee {
                let payment_token_address = match payment_token {
                    Option::Some(token) => token,
                    Option::None => panic!("Payment token missing"),
                };
                let payment_token = IERC20Dispatcher { contract_address: payment_token_address };
                let result = payment_token.transfer_from(caller, creator, fee);
                assert(result, 'Token Transfer Failed');
            }

            // Mint club NFT to the new member
            let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_nft };
            ip_club_nft.mint(caller);

            self.join_locked.write(false);

            // Emit event for new member
            self.emit(NewMember { club_id, member: caller, timestamp: get_block_timestamp() });
        }

        // Get the club record for a given club ID
        fn get_club_record(self: @ContractState, club_id: u256) -> ClubRecord {
            let club_record = self.clubs.entry(club_id).read();
            assert(club_record.status != ClubStatus::Inactive, 'Club does not exist');
            club_record
        }

        // Check if a user is a member of a club (owns the club NFT)
        fn is_member(self: @ContractState, club_id: u256, user: ContractAddress) -> bool {
            let club_record = self.clubs.entry(club_id).read();
            assert(club_record.status != ClubStatus::Inactive, 'Club does not exist');
            let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
            ip_club_nft.has_nft(user)
        }

        fn get_last_club_id(self: @ContractState) -> u256 {
            self.last_club_id.read()
        }
    }
}
