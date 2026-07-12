use anchor_lang::prelude::*;

declare_id!("C6vmifH7NSUttWfCREMUF5jGjFAn74aXT6pcSCowvpGq");

/// IP collection issuance over Metaplex Core. Permissionless and zero-fee:
/// anyone creates a collection, the creator owns it, and the registry records
/// it under a sequential id while holding no rights over it. Royalties are
/// per-asset, written immutably at mint with the minting creator as sole
/// beneficiary. An asset owner can permanently freeze (archive) their asset
/// natively through Core by adding an immutable FreezeDelegate plugin.
#[program]
pub mod mip_collections {
    use super::*;

    /// Creates a new Core collection owned by the caller.
    pub fn create_collection(ctx: Context<CreateCollection>, name: String, uri: String) -> Result<()> {
        require!(!name.is_empty() && name.len() <= 256, MipError::InvalidName);
        require!(uri.len() <= 2048, MipError::InvalidUri);

        let counter = &mut ctx.accounts.registry_counter;
        counter.count = counter.count.checked_add(1).unwrap();
        let collection_id = counter.count;

        let mpl_core_program = ctx.accounts.mpl_core_program.to_account_info();
        let core_collection = ctx.accounts.core_collection.to_account_info();
        let creator = ctx.accounts.creator.to_account_info();
        let system_program = ctx.accounts.system_program.to_account_info();

        mpl_core::instructions::CreateCollectionV2CpiBuilder::new(&mpl_core_program)
            .collection(&core_collection)
            .update_authority(Some(&creator))
            .payer(&creator)
            .system_program(&system_program)
            .name(name.clone())
            .uri(uri.clone())
            .invoke()?;

        let record = &mut ctx.accounts.collection_record;
        record.collection_id = collection_id;
        record.core_collection = ctx.accounts.core_collection.key();
        record.creator = ctx.accounts.creator.key();

        emit!(CollectionCreated {
            collection_id,
            core_collection: ctx.accounts.core_collection.key(),
            creator: ctx.accounts.creator.key(),
            name,
            uri,
        });
        Ok(())
    }

    /// Mints a new asset into a collection. Core enforces that the signer is
    /// the collection's authority; the program holds no mint rights.
    /// `royalty_bps` sets the asset's royalty, written as an immutable
    /// Royalties plugin (authority None — no one can ever update it) with the
    /// minting creator as sole beneficiary. The plugin is attached even at
    /// zero so the creator's authorship is recorded on-chain per asset; the
    /// registration timestamp is the mint transaction's block time.
    pub fn mint_asset(
        ctx: Context<MintAsset>,
        name: String,
        uri: String,
        royalty_bps: u16,
    ) -> Result<()> {
        require!(!name.is_empty() && name.len() <= 256, MipError::InvalidName);
        require!(!uri.is_empty() && uri.len() <= 2048, MipError::InvalidUri);
        require!(royalty_bps <= 10_000, MipError::RoyaltyBpsTooHigh);

        let plugins = vec![mpl_core::types::PluginAuthorityPair {
            plugin: mpl_core::types::Plugin::Royalties(mpl_core::types::Royalties {
                basis_points: royalty_bps,
                creators: vec![mpl_core::types::Creator {
                    address: ctx.accounts.authority.key(),
                    percentage: 100,
                }],
                rule_set: mpl_core::types::RuleSet::None,
            }),
            authority: Some(mpl_core::types::PluginAuthority::None),
        }];

        let mpl_core_program = ctx.accounts.mpl_core_program.to_account_info();
        let asset = ctx.accounts.asset.to_account_info();
        let core_collection = ctx.accounts.core_collection.to_account_info();
        let authority = ctx.accounts.authority.to_account_info();
        let recipient = ctx.accounts.recipient.to_account_info();
        let system_program = ctx.accounts.system_program.to_account_info();

        mpl_core::instructions::CreateV2CpiBuilder::new(&mpl_core_program)
            .asset(&asset)
            .collection(Some(&core_collection))
            .authority(Some(&authority))
            .payer(&authority)
            .owner(Some(&recipient))
            .system_program(&system_program)
            .name(name)
            .uri(uri.clone())
            .plugins(plugins)
            .invoke()?;

        emit!(AssetMinted {
            core_collection: ctx.accounts.core_collection.key(),
            asset: ctx.accounts.asset.key(),
            owner: ctx.accounts.recipient.key(),
            creator: ctx.accounts.authority.key(),
            uri,
            royalty_bps,
        });
        Ok(())
    }
}

#[derive(Accounts)]
pub struct MintAsset<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    /// The new Core asset account; a fresh keypair signs its own creation.
    #[account(mut)]
    pub asset: Signer<'info>,
    /// CHECK: validated by mpl-core as the collection the asset joins.
    #[account(mut)]
    pub core_collection: UncheckedAccount<'info>,
    /// CHECK: the asset's initial owner; any address.
    pub recipient: UncheckedAccount<'info>,
    /// CHECK: constrained to the Metaplex Core program id.
    #[account(address = mpl_core::programs::MPL_CORE_ID)]
    pub mpl_core_program: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[event]
pub struct AssetMinted {
    pub core_collection: Pubkey,
    pub asset: Pubkey,
    pub owner: Pubkey,
    pub creator: Pubkey,
    pub uri: String,
    pub royalty_bps: u16,
}

#[derive(Accounts)]
pub struct CreateCollection<'info> {
    #[account(mut)]
    pub creator: Signer<'info>,
    /// The new Core collection account; a fresh keypair signs its own creation.
    #[account(mut)]
    pub core_collection: Signer<'info>,
    #[account(
        init_if_needed,
        payer = creator,
        space = 8 + 8,
        seeds = [b"counter"],
        bump
    )]
    pub registry_counter: Account<'info, RegistryCounter>,
    #[account(
        init,
        payer = creator,
        space = 8 + 8 + 32 + 32,
        seeds = [b"collection", core_collection.key().as_ref()],
        bump
    )]
    pub collection_record: Account<'info, CollectionRecord>,
    /// CHECK: constrained to the Metaplex Core program id.
    #[account(address = mpl_core::programs::MPL_CORE_ID)]
    pub mpl_core_program: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct RegistryCounter {
    pub count: u64,
}

#[account]
pub struct CollectionRecord {
    pub collection_id: u64,
    pub core_collection: Pubkey,
    pub creator: Pubkey,
}

#[event]
pub struct CollectionCreated {
    pub collection_id: u64,
    pub core_collection: Pubkey,
    pub creator: Pubkey,
    pub name: String,
    pub uri: String,
}

#[error_code]
pub enum MipError {
    #[msg("royalty basis points exceed 10000")]
    RoyaltyBpsTooHigh,
    #[msg("name must be 1..=256 bytes")]
    InvalidName,
    #[msg("uri exceeds 2048 bytes or is empty where required")]
    InvalidUri,
}
