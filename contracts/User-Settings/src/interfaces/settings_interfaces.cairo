use starknet::ContractAddress;
use user_settings::structs::settings_structs::PublicUserSettings;

pub const IUSER_SETTINGS_REGISTRY_ID: felt252 =
    0x0204179c15f947088fc3173f05d6f0f8db3fd935f248d535a669f2cbe3c68f6d;

#[starknet::interface]
pub trait IUserSettingsRegistry<TContractState> {
    fn set_settings(
        ref self: TContractState,
        default_ip_protection_level: u8,
        automatic_ip_registration: bool,
        encrypted_preferences_uri: ByteArray,
        encrypted_preferences_hash: felt252,
    );

    fn set_settings_for(
        ref self: TContractState,
        user: ContractAddress,
        default_ip_protection_level: u8,
        automatic_ip_registration: bool,
        encrypted_preferences_uri: ByteArray,
        encrypted_preferences_hash: felt252,
        nonce: u64,
        deadline: u64,
        signature: Array<felt252>,
    );

    fn update_ip_defaults(
        ref self: TContractState, default_ip_protection_level: u8, automatic_ip_registration: bool,
    );

    fn update_preferences_pointer(
        ref self: TContractState,
        encrypted_preferences_uri: ByteArray,
        encrypted_preferences_hash: felt252,
    );

    fn clear_preferences_pointer(ref self: TContractState);

    fn delete_settings(ref self: TContractState);

    fn has_settings(self: @TContractState, user: ContractAddress) -> bool;

    fn get_settings(self: @TContractState, user: ContractAddress) -> PublicUserSettings;

    fn get_revision(self: @TContractState, user: ContractAddress) -> u64;

    fn get_nonce(self: @TContractState, user: ContractAddress) -> u64;

    fn hash_settings_update(
        self: @TContractState,
        user: ContractAddress,
        default_ip_protection_level: u8,
        automatic_ip_registration: bool,
        encrypted_preferences_uri: ByteArray,
        encrypted_preferences_hash: felt252,
        nonce: u64,
        deadline: u64,
    ) -> felt252;
}

#[starknet::interface]
pub trait ISRC6Account<TContractState> {
    fn is_valid_signature(
        self: @TContractState, hash: felt252, signature: Array<felt252>,
    ) -> felt252;
}
