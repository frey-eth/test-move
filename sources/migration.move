module migrate_fun_sui::migration {

    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock::{Clock};



    use migrate_fun_sui::vault::{Self, Vault};
    use migrate_fun_sui::snapshot;
    use migrate_fun_sui::events;
    use migrate_fun_sui::flowx_clmm_adapter;


    // --- Errors ---
    const ENotAdmin: u64 = 100;
    const EMigrationAlreadyFinalized: u64 = 201;
    const EMigrationEnded: u64 = 203;
    const EExceedsSnapshotQuota: u64 = 300;
    const EVaultNotLocked: u64 = 401;

    const EClaimsNotEnabled: u64 = 205;

    // --- FlowX Dependencies ---
    use flowx_clmm::pool_manager::{PoolRegistry};
    use flowx_clmm::position_manager::{PositionRegistry};
    use flowx_clmm::versioned::{Versioned};

    /// Main Configuration Object for a Migration.
    /// Generic over <OldToken, NewToken, ReceiptToken>
    public struct MigrationConfig<phantom OldToken, phantom NewToken, phantom Receipt> has key {
        id: UID,
        admin: address,
        ratio: u64,
        snapshot_root: vector<u8>,
        finalized: bool,
        start_time: u64,

        // Capabilities
        treasury_new: TreasuryCap<NewToken>,
        treasury_receipt: TreasuryCap<Receipt>
    }

    /// Tracks user migration state to prevent double-spending.
    public struct UserMigration has key {
        id: UID,
        migrated_amount: u64
    }

    // --- Phase 1: Initialize ---

    public fun initialize_migration<OldToken, NewToken, Receipt>(
        treasury_new: TreasuryCap<NewToken>,
        treasury_receipt: TreasuryCap<Receipt>,
        total_old_supply: u64,
        total_new_supply: u64,
        snapshot_root: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Simple Ratio: scaled by 1e9
        let ratio = (total_new_supply as u128) * 1_000_000_000 / (total_old_supply as u128);

        let config = MigrationConfig<OldToken, NewToken, Receipt> {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            ratio: (ratio as u64),
            snapshot_root,
            finalized: false,
            start_time: sui::clock::timestamp_ms(clock),
            treasury_new,
            treasury_receipt
        };

        // Create the Vault immediately
        let vault = vault::create<OldToken>(ctx);
        transfer::public_share_object(vault);

        events::emit_migration_initialized(
            object::id(&config),
            std::type_name::get_with_original_ids<OldToken>().into_string(),
            std::type_name::get_with_original_ids<NewToken>().into_string(),
            (ratio as u64),
            sui::clock::timestamp_ms(clock)
        );

        transfer::share_object(config);
    }

    // --- Phase 2: Lock Liquidity (Admin) ---
    // (Unchanged logic, just updated signature with Receipt generic)

    public fun lock_liquidity<OldToken, NewToken, Receipt>(
        config: &MigrationConfig<OldToken, NewToken, Receipt>,
        vault: &mut Vault<OldToken>,
        base_coins: Coin<sui::sui::SUI>,
        old_coins: Coin<OldToken>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.admin, ENotAdmin);
        assert!(!config.finalized, EMigrationAlreadyFinalized);

        let amt_old = coin::value(&old_coins);
        let amt_sui = coin::value(&base_coins);

        vault::lock_liquidity(vault, base_coins, old_coins);

        events::emit_liquidity_locked(
            object::id(config),
            amt_old,
            amt_sui
        );
    }

    // --- Phase 3: User Migrate (Deposit Old -> Get Receipt) ---

    public fun migrate<OldToken, NewToken, Receipt>(
        config: &mut MigrationConfig<OldToken, NewToken, Receipt>,
        vault: &mut Vault<OldToken>,
        old_coins: Coin<OldToken>,
        snapshot_quota: u64,
        proof: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        assert!(!config.finalized, EMigrationEnded);

        let user = tx_context::sender(ctx);
        let amount = coin::value(&old_coins);

        // 1. Verify Proof
        snapshot::verify_proof(config.snapshot_root, user, snapshot_quota, proof);

        // 2. Track / Validate Usage
        let migrated_so_far = if (sui::dynamic_field::exists_(&config.id, user)) {
            *sui::dynamic_field::borrow<address, u64>(&config.id, user)
        } else {
            0
        };

        let new_migrated = migrated_so_far + amount;
        assert!(new_migrated <= snapshot_quota, EExceedsSnapshotQuota);

        if (sui::dynamic_field::exists_(&config.id, user)) {
            *sui::dynamic_field::borrow_mut<address, u64>(&mut config.id, user) = new_migrated;
        } else {
            sui::dynamic_field::add(&mut config.id, user, new_migrated);
        };

        // 3. Deposit Old Token to Vault (Locked until Finalize)
        vault::deposit_old(vault, old_coins);

        // 4. MINT RECEIPTS (MFT) - 1:1 with Old Token Amount (implied ratio handled at Claim?)
        // Or should Receipt be 1:1 with New Token? user guide says "1:1 exchange (1 MFT = 1 new token)"
        // So we apply Ratio HERE.
        let receipt_amount = (((amount as u128) * (config.ratio as u128)) / 1_000_000_000) as u64;

        let receipt_coins = coin::mint(&mut config.treasury_receipt, receipt_amount, ctx);
        transfer::public_transfer(receipt_coins, user);

        events::emit_user_migrated(
            object::id(config),
            user,
            amount,
            receipt_amount
        );
    }

    // --- Phase 4: Finalize & Create Pool (Atomic: Liquidate Old -> Create New Pool) ---

    public fun finalize_and_create_pool<OldToken, NewToken, Receipt>(
        config: &mut MigrationConfig<OldToken, NewToken, Receipt>,
        vault: &mut Vault<OldToken>,
        pool_registry: &mut PoolRegistry,
        pos_registry: &mut PositionRegistry,
        versioned: &Versioned,
        clock: &Clock,
        old_pool_fee: u64, // Fee rate of OldToken/SUI pool
        min_sui_out: u64,  // Min SUI expected from liquidation
        initial_price_x128: u128,
        tick_lower: u32,
        tick_upper: u32,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.admin, ENotAdmin);
        assert!(!config.finalized, EMigrationAlreadyFinalized);
        assert!(vault::is_locked(vault), EVaultNotLocked);

        // 1. Set Finalized
        config.finalized = true;

        // 2. Withdraw ALL Old Tokens
        let old_balance = vault::withdraw_old(vault);
        let old_coins = coin::from_balance(old_balance, ctx);

        // 3. LIQUIDATE: Swap OldToken -> SUI
        let old_balance_val = coin::value(&old_coins);

        // Note: Returns SUI only. Remainder OldToken is refunded to admin by FlowX Router.
        let mut sui_coins = flowx_clmm_adapter::swap_exact_input<OldToken, sui::sui::SUI>(
            pool_registry,
            old_pool_fee,
            old_coins,
            min_sui_out,
            versioned,
            clock,
            ctx
        );

        // 4. Combine with existing Base SUI in Vault
        let base_balance = vault::withdraw_base(vault);
        let base_coins = coin::from_balance(base_balance, ctx);
        coin::join(&mut sui_coins, base_coins);

        // 5. Mint NewTokens for Liquidity based on "Same Ratio"
        // Amount New = Amount Old Liquidated * Ratio
        let lp_token_amount = (((old_balance_val as u128) * (config.ratio as u128)) / 1_000_000_000) as u64;
        let new_coins = coin::mint(&mut config.treasury_new, lp_token_amount, ctx);

        // 6. Create Pool & Add Liquidity (FlowX)
        flowx_clmm_adapter::create_pool<sui::sui::SUI, NewToken>(
            pool_registry,
            versioned,
            3000,
            initial_price_x128,
            clock,
            ctx
        );

        flowx_clmm_adapter::add_liquidity<sui::sui::SUI, NewToken>(
            pos_registry,
            pool_registry,
            3000,
            sui_coins,
            new_coins,
            tick_lower,
            tick_upper,
            versioned,
            clock,
            ctx
        );

        events::emit_migration_finalized(object::id(config), 0);
    }

    // --- Phase 5: Claim (Burn MFT -> Get New) ---

    public fun claim<OldToken, NewToken, Receipt>(
        config: &mut MigrationConfig<OldToken, NewToken, Receipt>,
        receipt: Coin<Receipt>,
        ctx: &mut TxContext
    ) {
        assert!(config.finalized, EClaimsNotEnabled);

        let amount = coin::value(&receipt);

        // 1. Burn Receipt
        coin::burn(&mut config.treasury_receipt, receipt);

        // 2. Mint New Token (1:1)
        let new_coins = coin::mint(&mut config.treasury_new, amount, ctx);
        transfer::public_transfer(new_coins, tx_context::sender(ctx));
    }
}
