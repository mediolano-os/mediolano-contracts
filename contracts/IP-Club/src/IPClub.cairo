// IP-Club — permissionless registry/factory for NFT-gated communities.
//
// Anyone can create a club; each club gets its own immutable IPClubNFT
// membership contract (a card is transferable only after the club's vesting
// lock, or never if none is set). The registry has
// no owner, no admin, no upgrade path, and takes no fee — optional entry
// fees flow directly from joiner to club creator. The creator's only lever
// is `set_club_open`, which gates NEW joins; existing memberships and the
// right to leave are never affected.
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
    use crate::events::{ClubStatusUpdated, MemberLeft, NewClubCreated, NewMember};
    use crate::interfaces::IIPClub::{IIPClub, IIP_CLUB_ID};
    use crate::interfaces::IIPClubNFT::{IIPClubNFTDispatcher, IIPClubNFTDispatcherTrait};
    use crate::types::{ClubRecord, bytearray_starts_with};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        ip_club_nft_class_hash: ClassHash,
        last_club_id: u256,
        clubs: Map<u256, ClubRecord>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        NewClubCreated: NewClubCreated,
        ClubStatusUpdated: ClubStatusUpdated,
        NewMember: NewMember,
        MemberLeft: MemberLeft,
    }

    #[constructor]
    fn constructor(ref self: ContractState, ip_club_nft_class_hash: ClassHash) {
        assert(ip_club_nft_class_hash.into() != 0_felt252, 'Class hash is zero');
        self.src5.register_interface(IIP_CLUB_ID);
        self.ip_club_nft_class_hash.write(ip_club_nft_class_hash);
    }

    #[abi(embed_v0)]
    impl IPClubImpl of IIPClub<ContractState> {
        fn create_club(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            metadata_uri: ByteArray,
            max_members: Option<u32>,
            entry_fee: Option<u256>,
            payment_token: Option<ContractAddress>,
            transfer_lock: Option<u64>,
            royalty_bps: u256,
        ) -> u256 {
            assert(name.len() > 0, 'Name must not be empty');
            assert(symbol.len() > 0, 'Symbol must not be empty');
            assert(royalty_bps <= 10000, 'Royalty exceeds 10000');
            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, 'URI must be ipfs:// or ar://');

            if let Option::Some(max) = max_members {
                assert(max > 0, 'Max members cannot be zero');
            }

            // A paid club carries both fee and token; a free club neither.
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

            let ip_club_manager = get_contract_address();
            let creator = get_caller_address();
            assert(!creator.is_zero(), 'Creator is zero address');
            let next_club_id = self.last_club_id.read() + 1;
            let deploy_salt = PoseidonTrait::new()
                .update_with(creator)
                .update_with(next_club_id)
                .finalize();

            let mut constructor_calldata: Array<felt252> = array![];
            (
                name.clone(),
                symbol.clone(),
                next_club_id,
                creator,
                ip_club_manager,
                metadata_uri.clone(),
                transfer_lock,
                royalty_bps,
            )
                .serialize(ref constructor_calldata);

            let (ip_club_nft_address, _) = deploy_syscall(
                self.ip_club_nft_class_hash.read(), deploy_salt, constructor_calldata.span(), false,
            )
                .unwrap();

            let club_record = ClubRecord {
                creator,
                club_nft: ip_club_nft_address,
                open: true,
                num_members: 0,
                max_members,
                entry_fee,
                payment_token,
                transfer_lock,
                royalty_bps,
            };

            self.clubs.entry(next_club_id).write(club_record);
            self.last_club_id.write(next_club_id);

            self
                .emit(
                    NewClubCreated {
                        club_id: next_club_id,
                        creator,
                        club_nft: ip_club_nft_address,
                        metadata_uri,
                        transfer_lock,
                        royalty_bps,
                        timestamp: get_block_timestamp(),
                    },
                );

            next_club_id
        }

        fn set_club_open(ref self: ContractState, club_id: u256, open: bool) {
            let mut club_record = self.clubs.entry(club_id).read();
            assert(!club_record.creator.is_zero(), 'Club does not exist');
            assert(club_record.creator == get_caller_address(), 'Only club creator');

            club_record.open = open;
            self.clubs.entry(club_id).write(club_record);

            self.emit(ClubStatusUpdated { club_id, open, timestamp: get_block_timestamp() });
        }

        fn join_club(ref self: ContractState, club_id: u256) {
            let mut club_record = self.clubs.entry(club_id).read();

            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Caller is zero address');
            assert(!club_record.creator.is_zero(), 'Club does not exist');
            assert(club_record.open, 'Club not open');

            if let Option::Some(max) = club_record.max_members {
                assert(club_record.num_members < max, 'Club full');
            }

            let creator = club_record.creator;
            let club_nft = club_record.club_nft;
            let entry_fee = club_record.entry_fee;
            let payment_token = club_record.payment_token;

            club_record.num_members += 1;
            self.clubs.entry(club_id).write(club_record);

            // State is final before the external calls (checks-effects-
            // interactions); a reentrant call runs under its own caller
            // context against consistent storage.
            if let Option::Some(fee) = entry_fee {
                // create_club guarantees a paid club carries a non-zero
                // payment token, and club fee terms are immutable.
                let token = IERC20Dispatcher { contract_address: payment_token.unwrap() };
                let result = token.transfer_from(caller, creator, fee);
                assert(result, 'Token Transfer Failed');
            }

            let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_nft };
            ip_club_nft.mint(caller);

            self.emit(NewMember { club_id, member: caller, timestamp: get_block_timestamp() });
        }

        fn leave_club(ref self: ContractState, club_id: u256, token_id: u256) {
            let mut club_record = self.clubs.entry(club_id).read();

            let caller = get_caller_address();
            assert(!club_record.creator.is_zero(), 'Club does not exist');

            let club_nft = club_record.club_nft;

            // Leaving is always allowed — open or closed. The entry fee is
            // not refunded; it flowed to the creator at join time.
            assert(club_record.num_members > 0, 'No members');
            club_record.num_members -= 1;
            self.clubs.entry(club_id).write(club_record);

            // The NFT contract verifies caller's ownership of token_id and
            // burns it (only this registry may call burn).
            let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_nft };
            ip_club_nft.burn(caller, token_id);

            self.emit(MemberLeft { club_id, member: caller, timestamp: get_block_timestamp() });
        }

        fn get_club_record(self: @ContractState, club_id: u256) -> ClubRecord {
            let club_record = self.clubs.entry(club_id).read();
            assert(!club_record.creator.is_zero(), 'Club does not exist');
            club_record
        }

        fn is_member(self: @ContractState, club_id: u256, user: ContractAddress) -> bool {
            let club_record = self.clubs.entry(club_id).read();
            assert(!club_record.creator.is_zero(), 'Club does not exist');
            let ip_club_nft = IIPClubNFTDispatcher { contract_address: club_record.club_nft };
            ip_club_nft.has_nft(user)
        }

        fn get_last_club_id(self: @ContractState) -> u256 {
            self.last_club_id.read()
        }

        fn version(self: @ContractState) -> ByteArray {
            "2.0.0"
        }
    }
}
