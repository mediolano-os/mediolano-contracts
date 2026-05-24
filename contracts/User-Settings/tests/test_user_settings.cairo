use openzeppelin_introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_block_timestamp, cheat_caller_address,
    declare,
};
use starknet::ContractAddress;
use user_settings::interfaces::settings_interfaces::{
    IUSER_SETTINGS_REGISTRY_ID, IUserSettingsRegistryDispatcher,
    IUserSettingsRegistryDispatcherTrait,
};
use user_settings::mocks::signature_account::{
    ISignatureAccountAdminDispatcher, ISignatureAccountAdminDispatcherTrait,
};
use user_settings::structs::settings_structs::IPProtectionLevel;

fn USER1() -> ContractAddress {
    0x101.try_into().unwrap()
}

fn USER2() -> ContractAddress {
    0x102.try_into().unwrap()
}

fn RELAYER() -> ContractAddress {
    0x103.try_into().unwrap()
}

fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}

fn IPFS_URI() -> ByteArray {
    "ipfs://bafybeisettings"
}

fn AR_URI() -> ByteArray {
    "ar://encrypted-settings"
}

fn HTTP_URI() -> ByteArray {
    "https://example.com/settings.json"
}

fn deploy_registry() -> IUserSettingsRegistryDispatcher {
    let contract = declare("UserSettingsRegistry").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IUserSettingsRegistryDispatcher { contract_address }
}

fn deploy_signature_account(owner: ContractAddress) -> ISignatureAccountAdminDispatcher {
    let contract = declare("SignatureAccount").unwrap().contract_class();
    let calldata = array![owner.into(), 0];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    ISignatureAccountAdminDispatcher { contract_address }
}

#[test]
fn test_any_wallet_can_set_own_settings() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(1, true, IPFS_URI(), 'settings_hash');

    let settings = registry.get_settings(USER1());
    assert(settings.user == USER1(), 'user should match');
    assert(
        settings.default_ip_protection_level == IPProtectionLevel::ADVANCED,
        'level should be advanced',
    );
    assert(settings.automatic_ip_registration, 'auto registration');
    assert(settings.encrypted_preferences_uri == IPFS_URI(), 'uri should match');
    assert(settings.encrypted_preferences_hash == 'settings_hash', 'hash should match');
    assert(settings.revision == 1, 'revision should be one');
    assert(registry.get_nonce(USER1()) == 1, 'nonce should be one');
    assert(settings.exists, 'settings should exist');
}

#[test]
fn test_settings_are_keyed_to_caller() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, "", 0);

    cheat_caller_address(registry.contract_address, USER2(), CheatSpan::TargetCalls(1));
    registry.set_settings(1, true, AR_URI(), 'other_hash');

    let user1_settings = registry.get_settings(USER1());
    let user2_settings = registry.get_settings(USER2());

    assert(user1_settings.user == USER1(), 'user1 owns record');
    assert(user2_settings.user == USER2(), 'user2 owns record');
    assert(
        user1_settings.default_ip_protection_level == IPProtectionLevel::STANDARD, 'user1 level',
    );
    assert(
        user2_settings.default_ip_protection_level == IPProtectionLevel::ADVANCED, 'user2 level',
    );
}

#[test]
fn test_update_ip_defaults_preserves_pointer() {
    let registry = deploy_registry();

    cheat_block_timestamp(registry.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, IPFS_URI(), 'settings_hash');

    cheat_block_timestamp(registry.contract_address, 2000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.update_ip_defaults(1, true);

    let settings = registry.get_settings(USER1());
    assert(settings.default_ip_protection_level == IPProtectionLevel::ADVANCED, 'level updated');
    assert(settings.automatic_ip_registration, 'auto updated');
    assert(settings.encrypted_preferences_uri == IPFS_URI(), 'uri preserved');
    assert(settings.encrypted_preferences_hash == 'settings_hash', 'hash preserved');
    assert(settings.revision == 2, 'revision increments');
    assert(settings.updated_at == 2000, 'timestamp updated');
}

#[test]
fn test_update_preferences_pointer() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, "", 0);

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.update_preferences_pointer(AR_URI(), 'new_hash');

    let settings = registry.get_settings(USER1());
    assert(settings.encrypted_preferences_uri == AR_URI(), 'uri updated');
    assert(settings.encrypted_preferences_hash == 'new_hash', 'hash updated');
    assert(settings.revision == 2, 'revision increments');
}

#[test]
fn test_clear_preferences_pointer() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, IPFS_URI(), 'settings_hash');

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.clear_preferences_pointer();

    let settings = registry.get_settings(USER1());
    assert(settings.encrypted_preferences_uri == "", 'uri cleared');
    assert(settings.encrypted_preferences_hash == 0, 'hash cleared');
    assert(settings.revision == 2, 'revision increments');
}

#[test]
fn test_delete_settings_marks_record_inactive() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(1, true, IPFS_URI(), 'settings_hash');

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.delete_settings();

    assert(!registry.has_settings(USER1()), 'settings deleted');
    assert(registry.get_revision(USER1()) == 2, 'revision retained');
}

#[test]
#[should_panic(expected: 'Settings do not exist')]
fn test_get_settings_reverts_after_delete() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(1, true, IPFS_URI(), 'settings_hash');

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.delete_settings();

    registry.get_settings(USER1());
}

#[test]
fn test_relayer_can_set_settings_with_account_signature() {
    let registry = deploy_registry();
    let account = deploy_signature_account(USER1());
    let user = account.contract_address;
    let deadline = 5000;
    let nonce = registry.get_nonce(user);
    let message_hash = registry
        .hash_settings_update(user, 1, true, IPFS_URI(), 'settings_hash', nonce, deadline);

    cheat_caller_address(account.contract_address, USER1(), CheatSpan::TargetCalls(1));
    account.set_expected_hash(message_hash);

    cheat_block_timestamp(registry.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, RELAYER(), CheatSpan::TargetCalls(1));
    registry
        .set_settings_for(
            user, 1, true, IPFS_URI(), 'settings_hash', nonce, deadline, array!['sig'],
        );

    let settings = registry.get_settings(user);
    assert(settings.user == user, 'user should match');
    assert(settings.default_ip_protection_level == IPProtectionLevel::ADVANCED, 'level updated');
    assert(settings.revision == 1, 'revision should increment');
    assert(registry.get_nonce(user) == 1, 'nonce should increment');
}

#[test]
#[should_panic(expected: 'Invalid nonce')]
fn test_relayer_rejects_replayed_nonce() {
    let registry = deploy_registry();
    let account = deploy_signature_account(USER1());
    let user = account.contract_address;
    let deadline = 5000;
    let message_hash = registry.hash_settings_update(user, 0, false, "", 0, 0, deadline);

    cheat_caller_address(account.contract_address, USER1(), CheatSpan::TargetCalls(1));
    account.set_expected_hash(message_hash);

    cheat_block_timestamp(registry.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, RELAYER(), CheatSpan::TargetCalls(1));
    registry.set_settings_for(user, 0, false, "", 0, 0, deadline, array!['sig']);

    cheat_block_timestamp(registry.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, RELAYER(), CheatSpan::TargetCalls(1));
    registry.set_settings_for(user, 0, false, "", 0, 0, deadline, array!['sig']);
}

#[test]
#[should_panic(expected: 'Invalid nonce')]
fn test_direct_write_invalidates_pending_relay_signature() {
    let registry = deploy_registry();
    let account = deploy_signature_account(USER1());
    let user = account.contract_address;
    let deadline = 5000;
    let message_hash = registry.hash_settings_update(user, 0, false, "", 0, 0, deadline);

    cheat_caller_address(account.contract_address, USER1(), CheatSpan::TargetCalls(1));
    account.set_expected_hash(message_hash);

    cheat_caller_address(registry.contract_address, user, CheatSpan::TargetCalls(1));
    registry.set_settings(1, true, IPFS_URI(), 'settings_hash');

    cheat_block_timestamp(registry.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, RELAYER(), CheatSpan::TargetCalls(1));
    registry.set_settings_for(user, 0, false, "", 0, 0, deadline, array!['sig']);
}

#[test]
#[should_panic(expected: 'Signature expired')]
fn test_relayer_rejects_expired_signature() {
    let registry = deploy_registry();
    let account = deploy_signature_account(USER1());
    let user = account.contract_address;
    let deadline = 5000;

    cheat_block_timestamp(registry.contract_address, 5001, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, RELAYER(), CheatSpan::TargetCalls(1));
    registry.set_settings_for(user, 0, false, "", 0, 0, deadline, array!['sig']);
}

#[test]
#[should_panic(expected: 'Unexpected hash')]
fn test_relayer_rejects_invalid_signature_hash() {
    let registry = deploy_registry();
    let account = deploy_signature_account(USER1());
    let user = account.contract_address;
    let deadline = 5000;

    cheat_caller_address(account.contract_address, USER1(), CheatSpan::TargetCalls(1));
    account.set_expected_hash('different_hash');

    cheat_block_timestamp(registry.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(registry.contract_address, RELAYER(), CheatSpan::TargetCalls(1));
    registry
        .set_settings_for(user, 1, true, IPFS_URI(), 'settings_hash', 0, deadline, array!['sig']);
}

#[test]
fn test_supports_user_settings_interface() {
    let registry = deploy_registry();
    let src5 = ISRC5Dispatcher { contract_address: registry.contract_address };

    assert(src5.supports_interface(IUSER_SETTINGS_REGISTRY_ID), 'interface supported');
}

#[test]
#[should_panic(expected: 'URI must be ipfs:// or ar://')]
fn test_rejects_http_preferences_uri() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, HTTP_URI(), 'settings_hash');
}

#[test]
#[should_panic(expected: 'Empty URI needs zero hash')]
fn test_empty_uri_requires_zero_hash() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, "", 'settings_hash');
}

#[test]
#[should_panic(expected: 'Hash is zero')]
fn test_non_empty_uri_requires_hash() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, IPFS_URI(), 0);
}

#[test]
#[should_panic(expected: 'Invalid protection level')]
fn test_rejects_invalid_protection_level() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.set_settings(2, false, "", 0);
}

#[test]
#[should_panic(expected: 'Settings do not exist')]
fn test_update_requires_existing_settings() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, USER1(), CheatSpan::TargetCalls(1));
    registry.update_ip_defaults(0, true);
}

#[test]
#[should_panic(expected: 'Settings do not exist')]
fn test_get_missing_settings_reverts() {
    let registry = deploy_registry();

    registry.get_settings(USER1());
}

#[test]
#[should_panic(expected: 'User is zero address')]
fn test_zero_caller_rejected() {
    let registry = deploy_registry();

    cheat_caller_address(registry.contract_address, ZERO(), CheatSpan::TargetCalls(1));
    registry.set_settings(0, false, "", 0);
}
