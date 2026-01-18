module migrate_fun_sui::migration {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock::{Clock};
    use sui::transfer;
    use sui::event; 
    
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
    const EMigrationNotEnded: u64 = 204;
    
    // --- FlowX Dependencies ---
    use flowx_clmm::pool_manager::{PoolRegistry};
    use flowx_clmm::position_manager::{PositionRegistry};
    use flowx_clmm::versioned::{Versioned};

    /// Main Configuration Object for a Migration.
    public struct MigrationConfig<phantom OldToken, phantom NewToken> has key {
        id: UID,
        admin: address,
        ratio: u64,
        snapshot_root: vector<u8>,
        finalized: bool,
        start_time: u64,
        
        // Capabilities
        treasury: TreasuryCap<NewToken> 
    }

    /// Tracks user migration state to prevent double-spending the snapshot quota.
    public struct UserMigration has key {
        id: UID,
        migrated_amount: u64
    }

    // --- Phase 1: Initialize ---

    public entry fun initialize_migration<OldToken, NewToken>(
        treasury: TreasuryCap<NewToken>,
        total_old_supply: u64,
        total_new_supply: u64,
        snapshot_root: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Simple Ratio: scaled by 1e9
        let ratio = (total_new_supply as u128) * 1_000_000_000 / (total_old_supply as u128); 
        
        let config = MigrationConfig<OldToken, NewToken> {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            ratio: (ratio as u64),
            snapshot_root,
            finalized: false,
            start_time: sui::clock::timestamp_ms(clock),
            treasury
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

    // --- Phase 2: Lock Liquidity ---

    public entry fun lock_liquidity<OldToken, NewToken>(
        config: &MigrationConfig<OldToken, NewToken>,
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

    // --- Phase 3: User Migrate (Permissionless) ---

    public entry fun migrate<OldToken, NewToken>(
        config: &mut MigrationConfig<OldToken, NewToken>,
        old_coins: Coin<OldToken>,
        snapshot_quota: u64, // The total amount user owns in snapshot
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

        // Update state
        if (sui::dynamic_field::exists_(&config.id, user)) {
            *sui::dynamic_field::borrow_mut<address, u64>(&mut config.id, user) = new_migrated;
        } else {
            sui::dynamic_field::add(&mut config.id, user, new_migrated);
        };

        // 3. Burn Old Logic (Transfer to 0x0)
        transfer::public_transfer(old_coins, @0x0); 

        // 4. Mint New Logic
        let mint_amount = (((amount as u128) * (config.ratio as u128)) / 1_000_000_000) as u64;
        let new_coins = coin::mint(&mut config.treasury, mint_amount, ctx);
        
        transfer::public_transfer(new_coins, user);

        events::emit_user_migrated(
            object::id(config),
            user,
            amount,
            mint_amount
        );
    }

    // --- Phase 4: Finalize ---

    public entry fun finalize_migration<OldToken, NewToken>(
        config: &mut MigrationConfig<OldToken, NewToken>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.admin, ENotAdmin);
        config.finalized = true;
        
        events::emit_migration_finalized(
            object::id(config),
            0 
        );
    }

    // --- Phase 5: Create New Pool ---

    public entry fun create_new_pool<OldToken, NewToken>(
        config: &mut MigrationConfig<OldToken, NewToken>,
        vault: &mut Vault<OldToken>,
        pool_registry: &mut PoolRegistry,
        pos_registry: &mut PositionRegistry, 
        versioned: &Versioned,
        clock: &Clock,
        initial_price_x128: u128, 
        tick_lower: u32,
        tick_upper: u32,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.admin, ENotAdmin);
        assert!(config.finalized, EMigrationNotEnded);
        assert!(vault::is_locked(vault), EVaultNotLocked);

        // 1. Withdraw Base (SUI) from Vault
        let base_balance = vault::withdraw_base(vault);
        let base_coins = coin::from_balance(base_balance, ctx);
        
        // 2. Mint 1M NewTokens for Liquidity
        let lp_token_amount = 1_000_000_000_000_000; 
        let new_coins = coin::mint(&mut config.treasury, lp_token_amount, ctx);

        // 3. Create Pool & Add Liquidity
        flowx_clmm_adapter::create_pool<sui::sui::SUI, NewToken>(
            pool_registry,
            versioned,
            3000, // Fee Tier
            initial_price_x128,
            clock,
            ctx
        );

        flowx_clmm_adapter::add_liquidity<sui::sui::SUI, NewToken>(
            pos_registry,
            pool_registry,
            3000,
            base_coins, // SUI
            new_coins,  // New Token
            tick_lower,
            tick_upper,
            versioned,
            clock,
            ctx
        );

        events::emit_new_pool_created(
            object::id(config),
            object::id(pool_registry), 
            0 
        );
    }
}
