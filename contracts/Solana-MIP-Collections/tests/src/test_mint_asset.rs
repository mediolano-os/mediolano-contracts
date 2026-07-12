use anchor_lang::{InstructionData, ToAccountMetas};
use litesvm::LiteSVM;
use mpl_core::accounts::BaseAssetV1;
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

fn setup_with_collection() -> (LiteSVM, Keypair, Keypair) {
    let mut svm = LiteSVM::new();
    svm.add_program_from_file(program_id(), "../target/deploy/mip_collections.so")
        .unwrap();
    svm.add_program_from_file(MPL_CORE_ID, "fixtures/mpl_core.so")
        .unwrap();
    let creator = Keypair::new();
    svm.airdrop(&creator.pubkey(), 10_000_000_000).unwrap();
    let core_collection = Keypair::new();
    let ix = Instruction {
        program_id: program_id(),
        accounts: mip_collections::accounts::CreateCollection {
            creator: creator.pubkey(),
            core_collection: core_collection.pubkey(),
            registry_counter: Pubkey::find_program_address(&[b"counter"], &program_id()).0,
            collection_record: Pubkey::find_program_address(
                &[b"collection", core_collection.pubkey().as_ref()],
                &program_id(),
            )
            .0,
            mpl_core_program: MPL_CORE_ID,
            system_program: anchor_lang::system_program::ID,
        }
        .to_account_metas(None),
        data: mip_collections::instruction::CreateCollection {
            name: "My IP".to_string(),
            uri: "ipfs://col".to_string(),
        }
        .data(),
    };
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&creator.pubkey()),
        &[&creator, &core_collection],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).unwrap();
    (svm, creator, core_collection)
}

fn mint_ix(
    authority: &Pubkey,
    asset: &Pubkey,
    core_collection: &Pubkey,
    recipient: &Pubkey,
    uri: &str,
    royalty_bps: u16,
) -> Instruction {
    Instruction {
        program_id: program_id(),
        accounts: mip_collections::accounts::MintAsset {
            authority: *authority,
            asset: *asset,
            core_collection: *core_collection,
            recipient: *recipient,
            mpl_core_program: MPL_CORE_ID,
            system_program: anchor_lang::system_program::ID,
        }
        .to_account_metas(None),
        data: mip_collections::instruction::MintAsset {
            name: "Work #1".to_string(),
            uri: uri.to_string(),
            royalty_bps,
        }
        .data(),
    }
}

fn send_mint(
    svm: &mut LiteSVM,
    authority: &Keypair,
    asset: &Keypair,
    core_collection: &Pubkey,
    recipient: &Pubkey,
    uri: &str,
    royalty_bps: u16,
) -> Result<(), String> {
    let ix = mint_ix(&authority.pubkey(), &asset.pubkey(), core_collection, recipient, uri, royalty_bps);
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&authority.pubkey()),
        &[authority, asset],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).map(|_| ()).map_err(|e| format!("{:?}", e.err))
}

#[test]
fn mint_asset_into_collection_for_recipient() {
    let (mut svm, creator, core_collection) = setup_with_collection();
    let alice = Keypair::new();
    let asset = Keypair::new();

    send_mint(
        &mut svm,
        &creator,
        &asset,
        &core_collection.pubkey(),
        &alice.pubkey(),
        "ipfs://asset/1",
        500,
    )
    .unwrap();

    let asset_account = svm.get_account(&asset.pubkey()).unwrap();
    assert_eq!(asset_account.owner, MPL_CORE_ID);
    let base = BaseAssetV1::from_bytes(&asset_account.data).unwrap();
    assert_eq!(base.owner, alice.pubkey());
    assert_eq!(base.name, "Work #1");
    assert_eq!(base.uri, "ipfs://asset/1");
    assert_eq!(
        base.update_authority,
        mpl_core::types::UpdateAuthority::Collection(core_collection.pubkey())
    );

    // Immutable per-asset royalty: creator sole beneficiary, authority None
    // so no one — including the collection authority — can ever change it.
    let parsed = mpl_core::Asset::from_bytes(&asset_account.data).unwrap();
    let royalties = parsed.plugin_list.royalties.expect("royalties plugin");
    assert_eq!(royalties.royalties.basis_points, 500);
    assert_eq!(royalties.royalties.creators.len(), 1);
    assert_eq!(royalties.royalties.creators[0].address, creator.pubkey());
    assert_eq!(royalties.royalties.creators[0].percentage, 100);
    assert_eq!(royalties.base.authority.authority_type, mpl_core::AuthorityType::None);
}

#[test]
fn mint_asset_zero_royalty_still_records_creator() {
    let (mut svm, creator, core_collection) = setup_with_collection();
    let alice = Keypair::new();
    let asset = Keypair::new();

    send_mint(
        &mut svm,
        &creator,
        &asset,
        &core_collection.pubkey(),
        &alice.pubkey(),
        "ipfs://asset/1",
        0,
    )
    .unwrap();

    let asset_account = svm.get_account(&asset.pubkey()).unwrap();
    let parsed = mpl_core::Asset::from_bytes(&asset_account.data).unwrap();
    let royalties = parsed.plugin_list.royalties.expect("royalties plugin");
    assert_eq!(royalties.royalties.basis_points, 0);
    assert_eq!(royalties.royalties.creators[0].address, creator.pubkey());
    assert_eq!(royalties.base.authority.authority_type, mpl_core::AuthorityType::None);
}

#[test]
fn mint_asset_rejects_royalty_over_100_pct() {
    let (mut svm, creator, core_collection) = setup_with_collection();
    let asset = Keypair::new();

    let err = send_mint(
        &mut svm,
        &creator,
        &asset,
        &core_collection.pubkey(),
        &creator.pubkey(),
        "ipfs://asset/1",
        10_001,
    )
    .unwrap_err();
    // Anchor error code 6000 is the first #[error_code] variant: RoyaltyBpsTooHigh.
    assert!(err.contains("Custom(6000)"), "unexpected error: {err}");
}

#[test]
fn mint_asset_rejects_empty_uri() {
    let (mut svm, creator, core_collection) = setup_with_collection();
    let asset = Keypair::new();

    let err = send_mint(
        &mut svm,
        &creator,
        &asset,
        &core_collection.pubkey(),
        &creator.pubkey(),
        "",
        0,
    )
    .unwrap_err();
    // Anchor error code 6002 is the third #[error_code] variant: InvalidUri.
    assert!(err.contains("Custom(6002)"), "unexpected error: {err}");
}

#[test]
fn mint_asset_rejects_non_authority() {
    let (mut svm, _creator, core_collection) = setup_with_collection();
    let mallory = Keypair::new();
    svm.airdrop(&mallory.pubkey(), 10_000_000_000).unwrap();
    let asset = Keypair::new();

    let result = send_mint(
        &mut svm,
        &mallory,
        &asset,
        &core_collection.pubkey(),
        &mallory.pubkey(),
        "ipfs://evil",
        0,
    );
    assert!(result.is_err(), "non-authority mint must fail via Core");
}
