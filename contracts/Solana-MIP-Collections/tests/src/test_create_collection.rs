use anchor_lang::{AccountDeserialize, InstructionData, ToAccountMetas};
use litesvm::LiteSVM;
use mpl_core::accounts::BaseCollectionV1;
use mpl_core::programs::MPL_CORE_ID;
use solana_sdk::{
    instruction::Instruction,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
};

fn program_id() -> Pubkey {
    mip_collections::ID
}

fn setup() -> LiteSVM {
    let mut svm = LiteSVM::new();
    svm.add_program_from_file(program_id(), "../target/deploy/mip_collections.so")
        .expect("program .so — run `anchor build` first");
    svm.add_program_from_file(MPL_CORE_ID, "fixtures/mpl_core.so")
        .expect("mpl_core fixture");
    svm
}

fn create_collection_ix(
    creator: &Pubkey,
    core_collection: &Pubkey,
    name: &str,
    uri: &str,
) -> Instruction {
    let (collection_record, _) = Pubkey::find_program_address(
        &[b"collection", core_collection.as_ref()],
        &program_id(),
    );
    Instruction {
        program_id: program_id(),
        accounts: mip_collections::accounts::CreateCollection {
            creator: *creator,
            core_collection: *core_collection,
            registry_counter: Pubkey::find_program_address(&[b"counter"], &program_id()).0,
            collection_record,
            mpl_core_program: MPL_CORE_ID,
            system_program: anchor_lang::system_program::ID,
        }
        .to_account_metas(None),
        data: mip_collections::instruction::CreateCollection {
            name: name.to_string(),
            uri: uri.to_string(),
        }
        .data(),
    }
}

fn send_create(
    svm: &mut LiteSVM,
    creator: &Keypair,
    core_collection: &Keypair,
    name: &str,
) -> Result<(), String> {
    let ix = create_collection_ix(&creator.pubkey(), &core_collection.pubkey(), name, "ipfs://col");
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&creator.pubkey()),
        &[creator, core_collection],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).map(|_| ()).map_err(|e| format!("{:?}", e.err))
}

#[test]
fn create_collection_records_and_creates_core_collection() {
    let mut svm = setup();
    let creator = Keypair::new();
    svm.airdrop(&creator.pubkey(), 10_000_000_000).unwrap();
    let core_collection = Keypair::new();

    send_create(&mut svm, &creator, &core_collection, "My IP").unwrap();

    // Core collection exists, owned by mpl-core, creator is update authority.
    let col_account = svm.get_account(&core_collection.pubkey()).unwrap();
    assert_eq!(col_account.owner, MPL_CORE_ID);
    let base = BaseCollectionV1::from_bytes(&col_account.data).unwrap();
    assert_eq!(base.name, "My IP");
    assert_eq!(base.uri, "ipfs://col");
    assert_eq!(base.update_authority, creator.pubkey());

    // Royalties are per-asset, written at mint — the collection carries none.
    let collection = mpl_core::Collection::from_bytes(&col_account.data).unwrap();
    assert!(collection.plugin_list.royalties.is_none());

    // Registry record: id 1, creator + collection recorded.
    let (record_pda, _) = Pubkey::find_program_address(
        &[b"collection", core_collection.pubkey().as_ref()],
        &program_id(),
    );
    let record_account = svm.get_account(&record_pda).unwrap();
    let record = mip_collections::CollectionRecord::try_deserialize(
        &mut record_account.data.as_slice(),
    )
    .unwrap();
    assert_eq!(record.collection_id, 1);
    assert_eq!(record.core_collection, core_collection.pubkey());
    assert_eq!(record.creator, creator.pubkey());
}

#[test]
fn create_collection_is_permissionless_and_sequential() {
    let mut svm = setup();
    let first = Keypair::new();
    let second = Keypair::new();
    svm.airdrop(&first.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&second.pubkey(), 10_000_000_000).unwrap();
    let col_a = Keypair::new();
    let col_b = Keypair::new();

    send_create(&mut svm, &first, &col_a, "A").unwrap();
    send_create(&mut svm, &second, &col_b, "B").unwrap();

    let record_pda = |col: &Pubkey| {
        Pubkey::find_program_address(&[b"collection", col.as_ref()], &program_id()).0
    };
    let rec_a = mip_collections::CollectionRecord::try_deserialize(
        &mut svm.get_account(&record_pda(&col_a.pubkey())).unwrap().data.as_slice(),
    )
    .unwrap();
    let rec_b = mip_collections::CollectionRecord::try_deserialize(
        &mut svm.get_account(&record_pda(&col_b.pubkey())).unwrap().data.as_slice(),
    )
    .unwrap();
    assert_eq!(rec_a.collection_id, 1);
    assert_eq!(rec_b.collection_id, 2);
    assert_eq!(rec_b.creator, second.pubkey());
}

#[test]
fn create_collection_rejects_empty_name() {
    let mut svm = setup();
    let creator = Keypair::new();
    svm.airdrop(&creator.pubkey(), 10_000_000_000).unwrap();
    let core_collection = Keypair::new();

    let err = send_create(&mut svm, &creator, &core_collection, "").unwrap_err();
    // Anchor error code 6001 is the second #[error_code] variant: InvalidName.
    assert!(err.contains("Custom(6001)"), "unexpected error: {err}");
}
