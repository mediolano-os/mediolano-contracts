#[starknet::contract]
pub mod UserSettingsRegistry {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{
        ContractAddress, VALIDATED, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use user_settings::interfaces::settings_interfaces::{
        ISRC6AccountDispatcher, ISRC6AccountDispatcherTrait, IUSER_SETTINGS_REGISTRY_ID,
        IUserSettingsRegistry,
    };
    use user_settings::structs::settings_structs::{
        IPProtectionLevel, PublicUserSettings, bytearray_starts_with, hash_bytearray,
    };

    const SET_SETTINGS_TYPEHASH: felt252 = 'USER_SETTINGS_SET_V1';

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        settings: Map<ContractAddress, PublicUserSettings>,
        revisions: Map<ContractAddress, u64>,
        nonces: Map<ContractAddress, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        SettingsUpdated: SettingsUpdated,
        IpDefaultsUpdated: IpDefaultsUpdated,
        PreferencesPointerUpdated: PreferencesPointerUpdated,
        PreferencesPointerCleared: PreferencesPointerCleared,
        SettingsDeleted: SettingsDeleted,
        SettingsRelayed: SettingsRelayed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SettingsUpdated {
        #[key]
        pub user: ContractAddress,
        pub default_ip_protection_level: u8,
        pub automatic_ip_registration: bool,
        pub encrypted_preferences_uri: ByteArray,
        pub encrypted_preferences_hash: felt252,
        pub revision: u64,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct IpDefaultsUpdated {
        #[key]
        pub user: ContractAddress,
        pub default_ip_protection_level: u8,
        pub automatic_ip_registration: bool,
        pub revision: u64,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PreferencesPointerUpdated {
        #[key]
        pub user: ContractAddress,
        pub encrypted_preferences_uri: ByteArray,
        pub encrypted_preferences_hash: felt252,
        pub revision: u64,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PreferencesPointerCleared {
        #[key]
        pub user: ContractAddress,
        pub revision: u64,
        pub updated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SettingsDeleted {
        #[key]
        pub user: ContractAddress,
        pub revision: u64,
        pub deleted_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SettingsRelayed {
        #[key]
        pub user: ContractAddress,
        #[key]
        pub relayer: ContractAddress,
        pub nonce: u64,
        pub deadline: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.src5.register_interface(IUSER_SETTINGS_REGISTRY_ID);
    }

    #[abi(embed_v0)]
    pub impl UserSettingsRegistryImpl of IUserSettingsRegistry<ContractState> {
        fn set_settings(
            ref self: ContractState,
            default_ip_protection_level: u8,
            automatic_ip_registration: bool,
            encrypted_preferences_uri: ByteArray,
            encrypted_preferences_hash: felt252,
        ) {
            let user = get_caller_address();
            assert(!user.is_zero(), 'User is zero address');

            self.bump_nonce(user);
            self
                .write_settings(
                    user,
                    default_ip_protection_level,
                    automatic_ip_registration,
                    encrypted_preferences_uri,
                    encrypted_preferences_hash,
                );
        }

        fn set_settings_for(
            ref self: ContractState,
            user: ContractAddress,
            default_ip_protection_level: u8,
            automatic_ip_registration: bool,
            encrypted_preferences_uri: ByteArray,
            encrypted_preferences_hash: felt252,
            nonce: u64,
            deadline: u64,
            signature: Array<felt252>,
        ) {
            assert(!user.is_zero(), 'User is zero address');
            assert(get_block_timestamp() <= deadline, 'Signature expired');
            assert(nonce == self.nonces.entry(user).read(), 'Invalid nonce');

            let message_hash = self
                .hash_settings_update(
                    user,
                    default_ip_protection_level,
                    automatic_ip_registration,
                    encrypted_preferences_uri.clone(),
                    encrypted_preferences_hash,
                    nonce,
                    deadline,
                );
            let signature_result = ISRC6AccountDispatcher { contract_address: user }
                .is_valid_signature(message_hash, signature);
            let is_valid_signature = signature_result == VALIDATED || signature_result == 1;
            assert(is_valid_signature, 'Invalid signature');

            self.nonces.entry(user).write(nonce + 1);
            self
                .write_settings(
                    user,
                    default_ip_protection_level,
                    automatic_ip_registration,
                    encrypted_preferences_uri,
                    encrypted_preferences_hash,
                );
            self.emit(SettingsRelayed { user, relayer: get_caller_address(), nonce, deadline });
        }

        fn update_ip_defaults(
            ref self: ContractState,
            default_ip_protection_level: u8,
            automatic_ip_registration: bool,
        ) {
            let user = get_caller_address();
            assert(!user.is_zero(), 'User is zero address');

            let mut settings = self.settings.entry(user).read();
            assert(settings.exists, 'Settings do not exist');

            self.bump_nonce(user);
            let level = reverse_process_ip_protection_level(default_ip_protection_level);
            let now = get_block_timestamp();
            let revision = self.next_revision(user);
            settings.default_ip_protection_level = level;
            settings.automatic_ip_registration = automatic_ip_registration;
            settings.revision = revision;
            settings.updated_at = now;
            self.settings.entry(user).write(settings);

            self
                .emit(
                    IpDefaultsUpdated {
                        user,
                        default_ip_protection_level,
                        automatic_ip_registration,
                        revision,
                        updated_at: now,
                    },
                );
        }

        fn update_preferences_pointer(
            ref self: ContractState,
            encrypted_preferences_uri: ByteArray,
            encrypted_preferences_hash: felt252,
        ) {
            let user = get_caller_address();
            assert(!user.is_zero(), 'User is zero address');
            assert_valid_preferences_pointer(
                @encrypted_preferences_uri, encrypted_preferences_hash,
            );

            let mut settings = self.settings.entry(user).read();
            assert(settings.exists, 'Settings do not exist');

            self.bump_nonce(user);
            let now = get_block_timestamp();
            let revision = self.next_revision(user);
            settings.encrypted_preferences_uri = encrypted_preferences_uri.clone();
            settings.encrypted_preferences_hash = encrypted_preferences_hash;
            settings.revision = revision;
            settings.updated_at = now;
            self.settings.entry(user).write(settings);

            self
                .emit(
                    PreferencesPointerUpdated {
                        user,
                        encrypted_preferences_uri,
                        encrypted_preferences_hash,
                        revision,
                        updated_at: now,
                    },
                );
        }

        fn clear_preferences_pointer(ref self: ContractState) {
            let user = get_caller_address();
            assert(!user.is_zero(), 'User is zero address');

            let mut settings = self.settings.entry(user).read();
            assert(settings.exists, 'Settings do not exist');

            self.bump_nonce(user);
            let now = get_block_timestamp();
            let revision = self.next_revision(user);
            settings.encrypted_preferences_uri = "";
            settings.encrypted_preferences_hash = 0;
            settings.revision = revision;
            settings.updated_at = now;
            self.settings.entry(user).write(settings);

            self.emit(PreferencesPointerCleared { user, revision, updated_at: now });
        }

        fn delete_settings(ref self: ContractState) {
            let user = get_caller_address();
            assert(!user.is_zero(), 'User is zero address');

            let settings = self.settings.entry(user).read();
            assert(settings.exists, 'Settings do not exist');

            self.bump_nonce(user);
            let now = get_block_timestamp();
            let revision = self.next_revision(user);
            let deleted_settings = PublicUserSettings {
                user,
                default_ip_protection_level: IPProtectionLevel::STANDARD,
                automatic_ip_registration: false,
                encrypted_preferences_uri: "",
                encrypted_preferences_hash: 0,
                revision,
                updated_at: now,
                exists: false,
            };
            self.settings.entry(user).write(deleted_settings);

            self.emit(SettingsDeleted { user, revision, deleted_at: now });
        }

        fn has_settings(self: @ContractState, user: ContractAddress) -> bool {
            self.settings.entry(user).read().exists
        }

        fn get_settings(self: @ContractState, user: ContractAddress) -> PublicUserSettings {
            let settings = self.settings.entry(user).read();
            assert(settings.exists, 'Settings do not exist');
            settings
        }

        fn get_revision(self: @ContractState, user: ContractAddress) -> u64 {
            self.revisions.entry(user).read()
        }

        fn get_nonce(self: @ContractState, user: ContractAddress) -> u64 {
            self.nonces.entry(user).read()
        }

        fn hash_settings_update(
            self: @ContractState,
            user: ContractAddress,
            default_ip_protection_level: u8,
            automatic_ip_registration: bool,
            encrypted_preferences_uri: ByteArray,
            encrypted_preferences_hash: felt252,
            nonce: u64,
            deadline: u64,
        ) -> felt252 {
            hash_settings_update_message(
                user,
                default_ip_protection_level,
                automatic_ip_registration,
                @encrypted_preferences_uri,
                encrypted_preferences_hash,
                nonce,
                deadline,
            )
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn write_settings(
            ref self: ContractState,
            user: ContractAddress,
            default_ip_protection_level: u8,
            automatic_ip_registration: bool,
            encrypted_preferences_uri: ByteArray,
            encrypted_preferences_hash: felt252,
        ) {
            assert_valid_preferences_pointer(
                @encrypted_preferences_uri, encrypted_preferences_hash,
            );

            let level = reverse_process_ip_protection_level(default_ip_protection_level);
            let now = get_block_timestamp();
            let revision = self.next_revision(user);
            let settings = PublicUserSettings {
                user,
                default_ip_protection_level: level,
                automatic_ip_registration,
                encrypted_preferences_uri: encrypted_preferences_uri.clone(),
                encrypted_preferences_hash,
                revision,
                updated_at: now,
                exists: true,
            };

            self.settings.entry(user).write(settings);
            self
                .emit(
                    SettingsUpdated {
                        user,
                        default_ip_protection_level,
                        automatic_ip_registration,
                        encrypted_preferences_uri,
                        encrypted_preferences_hash,
                        revision,
                        updated_at: now,
                    },
                );
        }

        fn next_revision(ref self: ContractState, user: ContractAddress) -> u64 {
            let revision = self.revisions.entry(user).read() + 1;
            self.revisions.entry(user).write(revision);
            revision
        }

        fn bump_nonce(ref self: ContractState, user: ContractAddress) -> u64 {
            let nonce = self.nonces.entry(user).read() + 1;
            self.nonces.entry(user).write(nonce);
            nonce
        }
    }

    fn assert_valid_preferences_pointer(uri: @ByteArray, commitment: felt252) {
        if uri.len() == 0 {
            assert(commitment == 0, 'Empty URI needs zero hash');
            return;
        }

        let valid_uri = bytearray_starts_with(uri, @"ipfs://")
            || bytearray_starts_with(uri, @"ar://");
        assert(valid_uri, 'URI must be ipfs:// or ar://');
        assert(commitment != 0, 'Hash is zero');
    }

    fn reverse_process_ip_protection_level(level: u8) -> IPProtectionLevel {
        match level {
            0 => IPProtectionLevel::STANDARD,
            1 => IPProtectionLevel::ADVANCED,
            _ => {
                assert(false, 'Invalid protection level');
                IPProtectionLevel::STANDARD
            },
        }
    }

    fn hash_settings_update_message(
        user: ContractAddress,
        default_ip_protection_level: u8,
        automatic_ip_registration: bool,
        encrypted_preferences_uri: @ByteArray,
        encrypted_preferences_hash: felt252,
        nonce: u64,
        deadline: u64,
    ) -> felt252 {
        PoseidonTrait::new()
            .update_with(SET_SETTINGS_TYPEHASH)
            .update_with(get_contract_address())
            .update_with(user)
            .update_with(default_ip_protection_level)
            .update_with(if automatic_ip_registration {
                1
            } else {
                0
            })
            .update_with(hash_bytearray(encrypted_preferences_uri))
            .update_with(encrypted_preferences_hash)
            .update_with(nonce)
            .update_with(deadline)
            .finalize()
    }
}
