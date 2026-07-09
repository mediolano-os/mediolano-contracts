use core::serde::Serde;
use core::traits::TryInto;
use ip_id::IPIdentity::{IIPIdentityDispatcher, IIPIdentityDispatcherTrait};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    start_cheat_block_timestamp, stop_cheat_block_timestamp,
};
use starknet::ContractAddress;

fn creator() -> ContractAddress {
    'creator'.try_into().unwrap()
}

fn collaborator() -> ContractAddress {
    'collaborator'.try_into().unwrap()
}

fn new_controller() -> ContractAddress {
    'new_controller'.try_into().unwrap()
}

fn zero_address() -> ContractAddress {
    0.try_into().unwrap()
}

fn asset_locator() -> felt252 {
    0x123
}

fn deploy_ip_identity() -> IIPIdentityDispatcher {
    let contract_class = declare("IPIdentity").unwrap().contract_class();
    let calldata = array![];
    let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
    IIPIdentityDispatcher { contract_address }
}

fn register_default_work(ip_identity: IIPIdentityDispatcher) -> felt252 {
    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.register_work("ipfs://work", 'work_hash', 0)
}

#[test]
fn test_register_work_creates_immutable_anchor() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    start_cheat_block_timestamp(ip_identity.contract_address, 1000);
    let ip_id = ip_identity.register_work("ipfs://work-metadata", 'metadata_hash', 0);
    stop_cheat_block_timestamp(ip_identity.contract_address);

    let work = ip_identity.get_work(ip_id);
    let expected_id = ip_identity.derive_ip_id(creator(), 'metadata_hash', 0);
    assert(ip_id == expected_id, 'id not content-derived');
    assert(work.creator == creator(), 'wrong creator');
    assert(work.controller == creator(), 'wrong controller');
    assert(work.metadata_uri == "ipfs://work-metadata", 'wrong uri');
    assert(work.metadata_hash == 'metadata_hash', 'wrong hash');
    assert(work.created_at == 1000, 'wrong timestamp');
    assert(work.representation_count == 0, 'wrong representations');
    assert(work.attestation_count == 0, 'wrong attestations');
    assert(ip_identity.registered_count() == 1, 'wrong count');
}

#[test]
fn test_ip_id_is_deterministic_across_deployments() {
    let first = deploy_ip_identity();
    let second = deploy_ip_identity();

    cheat_caller_address(first.contract_address, creator(), CheatSpan::TargetCalls(1));
    let id_on_first = first.register_work("ipfs://work", 'work_hash', 7);

    cheat_caller_address(second.contract_address, creator(), CheatSpan::TargetCalls(1));
    let id_on_second = second.register_work("ipfs://work", 'work_hash', 7);

    assert(id_on_first == id_on_second, 'id not portable');
    assert(id_on_first == first.derive_ip_id(creator(), 'work_hash', 7), 'derive mismatch');
}

#[test]
#[should_panic(expected: ('IPID: already registered',))]
fn test_duplicate_registration_reverts() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(2));
    ip_identity.register_work("ipfs://work", 'work_hash', 0);
    ip_identity.register_work("ipfs://work", 'work_hash', 0);
}

#[test]
fn test_parallel_claims_on_same_hash_coexist() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    let first_claim = ip_identity.register_work("ipfs://work", 'contested_hash', 0);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let second_claim = ip_identity.register_work("ipfs://copy", 'contested_hash', 0);

    assert(first_claim != second_claim, 'claims must be distinct');
    assert(ip_identity.get_work(first_claim).creator == creator(), 'wrong first claimant');
    assert(ip_identity.get_work(second_claim).creator == collaborator(), 'wrong second claimant');
    assert(ip_identity.registered_count() == 2, 'wrong count');
}

#[test]
fn test_same_creator_distinct_salts_distinct_works() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(2));
    let first = ip_identity.register_work("ipfs://work", 'work_hash', 1);
    let second = ip_identity.register_work("ipfs://work", 'work_hash', 2);

    assert(first != second, 'salts must separate ids');
}

#[test]
#[should_panic(expected: ('IPID: invalid metadata',))]
fn test_register_work_requires_metadata_hash() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.register_work("ipfs://work", 0, 0);
}

#[test]
fn test_controller_links_multiple_representations() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);
    let starknet_key = ip_identity
        .derive_representation_key('starknet', asset_locator(), 7, 0, 'ERC721');
    let ethereum_key = ip_identity
        .derive_representation_key('ethereum', 0x456, 42, 'external_locator_hash', 'ERC1155');

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    start_cheat_block_timestamp(ip_identity.contract_address, 2000);
    ip_identity
        .link_representation(
            ip_id,
            'starknet',
            asset_locator(),
            7,
            0,
            "ipfs://starknet-token",
            'starknet_metadata_hash',
            'ERC721',
        );
    stop_cheat_block_timestamp(ip_identity.contract_address);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            ip_id,
            'ethereum',
            0x456,
            42,
            'external_locator_hash',
            "ipfs://ethereum-token",
            'ethereum_metadata_hash',
            'ERC1155',
        );

    let work = ip_identity.get_work(ip_id);
    let representation = ip_identity.get_representation(starknet_key);
    assert(work.representation_count == 2, 'wrong representation count');
    assert(ip_identity.get_representation_ip_id(starknet_key) == ip_id, 'wrong reverse link');
    assert(ip_identity.get_work_representation_key(ip_id, 0) == starknet_key, 'wrong first key');
    assert(ip_identity.get_work_representation_key(ip_id, 1) == ethereum_key, 'wrong second key');
    assert(representation.representation_key == starknet_key, 'wrong stored key');
    assert(representation.chain_id == 'starknet', 'wrong chain');
    assert(representation.asset_locator == asset_locator(), 'wrong locator');
    assert(representation.token_id == 7, 'wrong token');
    assert(representation.metadata_hash == 'starknet_metadata_hash', 'wrong metadata hash');
    assert(representation.linked_at == 2000, 'wrong linked timestamp');
}

#[test]
#[should_panic(expected: ('IPID: invalid representation',))]
fn test_representation_requires_chain_namespace() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            ip_id,
            0,
            asset_locator(),
            7,
            0,
            "ipfs://starknet-token",
            'starknet_metadata_hash',
            'ERC721',
        );
}

#[test]
#[should_panic(expected: ('IPID: not controller',))]
fn test_only_controller_can_link_representation() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            ip_id,
            'starknet',
            asset_locator(),
            7,
            0,
            "ipfs://starknet-token",
            'starknet_metadata_hash',
            'ERC721',
        );
}

#[test]
#[should_panic(expected: ('IPID: representation linked',))]
fn test_representation_key_is_globally_unique() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    let first_ip_id = ip_identity.register_work("ipfs://work-1", 'work_hash_1', 0);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let second_ip_id = ip_identity.register_work("ipfs://work-2", 'work_hash_2', 0);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            first_ip_id,
            'starknet',
            asset_locator(),
            1,
            0,
            "ipfs://token-1",
            'metadata_hash_1',
            'ERC721',
        );

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            second_ip_id,
            'starknet',
            asset_locator(),
            1,
            0,
            "ipfs://token-1",
            'metadata_hash_1',
            'ERC721',
        );
}

#[test]
fn test_controller_can_be_transferred() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.transfer_controller(ip_id, new_controller());

    let work = ip_identity.get_work(ip_id);
    assert(work.creator == creator(), 'creator should not change');
    assert(work.controller == new_controller(), 'controller did not transfer');

    cheat_caller_address(ip_identity.contract_address, new_controller(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            ip_id,
            'bitcoin',
            0,
            0,
            'inscription_hash',
            "ipfs://ordinal-proof",
            'ordinal_metadata_hash',
            'ORDINAL',
        );

    let ordinal_key = ip_identity
        .derive_representation_key('bitcoin', 0, 0, 'inscription_hash', 'ORDINAL');
    assert(ip_identity.is_representation_linked(ordinal_key), 'representation not linked');
}

#[test]
#[should_panic(expected: ('IPID: invalid controller',))]
fn test_controller_transfer_rejects_zero_address() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.transfer_controller(ip_id, zero_address());
}

#[test]
fn test_relations_support_multiple_parents() {
    let ip_identity = deploy_ip_identity();

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(2));
    let parent_a = ip_identity.register_work("ipfs://parent-a", 'parent_a_hash', 0);
    let parent_b = ip_identity.register_work("ipfs://parent-b", 'parent_b_hash', 0);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(3));
    let remix = ip_identity.register_work("ipfs://remix", 'remix_hash', 0);
    start_cheat_block_timestamp(ip_identity.contract_address, 4000);
    let key_a = ip_identity.relate(remix, parent_a, 'DERIVATIVE');
    stop_cheat_block_timestamp(ip_identity.contract_address);
    let key_b = ip_identity.relate(remix, parent_b, 'DERIVATIVE');

    let work = ip_identity.get_work(remix);
    let relation = ip_identity.get_relation(key_a);
    assert(work.relation_count == 2, 'wrong relation count');
    assert(key_a == ip_identity.derive_relation_key(remix, parent_a, 'DERIVATIVE'), 'wrong key');
    assert(ip_identity.get_work_relation_key(remix, 0) == key_a, 'wrong first key');
    assert(ip_identity.get_work_relation_key(remix, 1) == key_b, 'wrong second key');
    assert(ip_identity.get_relation_ip_id(key_a) == remix, 'wrong reverse link');
    assert(relation.related_ip_id == parent_a, 'wrong related work');
    assert(relation.relation_type == 'DERIVATIVE', 'wrong relation type');
    assert(relation.asserted_by == collaborator(), 'wrong asserter');
    assert(relation.asserted_at == 4000, 'wrong asserted timestamp');
    assert(ip_identity.is_relation_asserted(key_a), 'relation not asserted');
}

#[test]
#[should_panic(expected: ('IPID: not controller',))]
fn test_only_controller_asserts_relations() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(2));
    let other = ip_identity.register_work("ipfs://other", 'other_hash', 0);
    ip_identity.relate(ip_id, other, 'VERSION');
}

#[test]
#[should_panic(expected: ('IPID: invalid work',))]
fn test_relation_requires_existing_related_work() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.relate(ip_id, 'missing_work_id', 'VERSION');
}

#[test]
#[should_panic(expected: ('IPID: self relation',))]
fn test_relation_rejects_self_reference() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.relate(ip_id, ip_id, 'VERSION');
}

#[test]
#[should_panic(expected: ('IPID: relation asserted',))]
fn test_duplicate_relation_reverts() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let other = ip_identity.register_work("ipfs://other", 'other_hash', 0);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(2));
    ip_identity.relate(ip_id, other, 'VERSION');
    ip_identity.relate(ip_id, other, 'VERSION');
}

#[test]
#[should_panic(expected: ('IPID: invalid relation',))]
fn test_relation_requires_type() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let other = ip_identity.register_work("ipfs://other", 'other_hash', 0);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity.relate(ip_id, other, 0);
}

#[test]
fn test_anyone_can_add_append_only_attestation() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    start_cheat_block_timestamp(ip_identity.contract_address, 3000);
    let attestation_id = ip_identity
        .attest(ip_id, 0, 'PROVENANCE', 'provenance_hash', "ipfs://provenance-proof");
    stop_cheat_block_timestamp(ip_identity.contract_address);

    let work = ip_identity.get_work(ip_id);
    let attestation = ip_identity.get_attestation(ip_id, attestation_id);
    assert(attestation_id == 1, 'wrong attestation id');
    assert(work.attestation_count == 1, 'wrong attestation count');
    assert(attestation.attester == collaborator(), 'wrong attester');
    assert(attestation.subject_key == 0, 'wrong subject');
    assert(attestation.attestation_type == 'PROVENANCE', 'wrong type');
    assert(attestation.data_hash == 'provenance_hash', 'wrong data hash');
    assert(attestation.uri == "ipfs://provenance-proof", 'wrong uri');
    assert(attestation.created_at == 3000, 'wrong attestation timestamp');
}

#[test]
#[should_panic(expected: ('IPID: invalid attestation',))]
fn test_attestation_requires_type_and_hash() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    ip_identity.attest(ip_id, 0, 0, 'provenance_hash', "ipfs://provenance-proof");
}

#[test]
fn test_dispute_targets_a_representation_claim() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    ip_identity
        .link_representation(
            ip_id,
            'bitcoin',
            0,
            0,
            'inscription_hash',
            "ipfs://ordinal-proof",
            'ordinal_metadata_hash',
            'ORDINAL',
        );
    let ordinal_key = ip_identity
        .derive_representation_key('bitcoin', 0, 0, 'inscription_hash', 'ORDINAL');

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let attestation_id = ip_identity
        .attest(ip_id, ordinal_key, 'DISPUTE', 'holder_sig_hash', "ipfs://dispute-proof");

    let attestation = ip_identity.get_attestation(ip_id, attestation_id);
    assert(attestation.subject_key == ordinal_key, 'wrong subject key');
    assert(attestation.attestation_type == 'DISPUTE', 'wrong type');
}

#[test]
fn test_confirm_targets_a_relation_claim() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let parent = ip_identity.register_work("ipfs://parent", 'parent_hash', 0);

    cheat_caller_address(ip_identity.contract_address, creator(), CheatSpan::TargetCalls(1));
    let relation_key = ip_identity.relate(ip_id, parent, 'DERIVATIVE');

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    let attestation_id = ip_identity
        .attest(ip_id, relation_key, 'CONFIRM', 'consent_hash', "ipfs://confirm-proof");

    let attestation = ip_identity.get_attestation(ip_id, attestation_id);
    assert(attestation.subject_key == relation_key, 'wrong subject key');
}

#[test]
#[should_panic(expected: ('IPID: invalid subject',))]
fn test_attestation_rejects_unknown_subject() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    ip_identity.attest(ip_id, 'bogus_subject', 'CONFIRM', 'hash', "ipfs://proof");
}

#[test]
#[should_panic(expected: ('IPID: invalid subject',))]
fn test_attestation_rejects_other_works_subject() {
    let ip_identity = deploy_ip_identity();
    let ip_id = register_default_work(ip_identity);

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(2));
    let other = ip_identity.register_work("ipfs://other", 'other_hash', 0);
    ip_identity.link_representation(other, 'starknet', 0x999, 5, 0, "ipfs://t", 'h', 'ERC721');
    let foreign_key = ip_identity.derive_representation_key('starknet', 0x999, 5, 0, 'ERC721');

    cheat_caller_address(ip_identity.contract_address, collaborator(), CheatSpan::TargetCalls(1));
    ip_identity.attest(ip_id, foreign_key, 'CONFIRM', 'hash', "ipfs://proof");
}
