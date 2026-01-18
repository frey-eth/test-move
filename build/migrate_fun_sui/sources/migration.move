module migrate_fun_sui::migration {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Clock};
    use sui::balance::{Self, Balance};

    // Internal modules
    use migrate_fun_sui::vault::{Self, OldTokenVault};
    use migrate_fun_sui::pool_math;
    use migrate_fun_sui::events;
    use migrate_fun_sui::flowx_clmm_adapter;

    // External modules
    use flowx_clmm::pool_manager::{PoolRegistry};
    use flowx_clmm::position::{Position};
    use flowx_clmm::versioned::{Versioned};

    // --- Errors ---
    const EInvalidSupply: u64 = 2;
    const ENotInitialized: u64 = 4;
    const EAlreadyFinalized: u64 = 5;

    // --- Structs ---

    /// Admin Capability to authorize migration
    struct AdminCap has key, store {
        id: UID
    }

    /// Shared object to track migration state.
    struct MigrationPool<phantom OldCoin, phantom NewCoin> has key {
        id: UID,
        vault_id: ID,
        // Rates
        old_supply_snapshot: u128,
        new_supply: u64,
        // Balances for User Migration
        new_token_balance: Balance<NewCoin>,
        // State
        is_finalized: bool,
    }

    /// Module Initialization
    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    // --- Phase 1: Initialization (Admin) ---
    /// 1. Withdraw OLD Liquidity (100% from position)
    /// 2. Lock OLD/SUI in Vault
    /// 3. Snapshot Supply & Mint NEW tokens
    /// 4. Create MigrationPool
    public fun initialize<OldCoin, NewCoin>(
        _admin: &AdminCap,
        pool_registry: &mut PoolRegistry,
        owner_position: Position,
        versioned: &Versioned,
        new_token_treasury: &mut TreasuryCap<NewCoin>,
        new_token_supply: u64,
        old_token_supply: u128, // Added argument
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(new_token_supply > 0, EInvalidSupply);

        // 1. Withdraw OLD Liquidity
        let mut_position = &mut owner_position;
        let (coin_old, coin_sui) = flowx_clmm_adapter::remove_all_liquidity<OldCoin, sui::sui::SUI>(
            pool_registry,
            mut_position,
            versioned,
            clock,
            ctx
        );

        // Return empty position to admin
        transfer::public_transfer(owner_position, tx_context::sender(ctx));

        // 2. Lock Assets in Vault
        let old_balance = coin::into_balance(coin_old);
        let sui_balance = coin::into_balance(coin_sui);

        // Create Vault
        let (_, _, vault_id) = vault::lock_assets(old_balance, sui_balance, ctx);

        // 3. Mint NEW Supply
        let new_balance = balance::increase_supply(coin::supply_mut(new_token_treasury), new_token_supply);

        // 4. Create MigrationPool
        let pool = MigrationPool<OldCoin, NewCoin> {
            id: object::new(ctx),
            vault_id,
            old_supply_snapshot: old_token_supply,
            new_supply: new_token_supply,
            new_token_balance: new_balance,
            is_finalized: false,
        };

        transfer::share_object(pool);
    }

    // --- Phase 2: User Migration ---
    public fun migrate_user<OldCoin, NewCoin>(
        pool: &mut MigrationPool<OldCoin, NewCoin>,
        old_coin: Coin<OldCoin>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&old_coin);
        assert!(amount > 0, 0);

        // Burn Old Coin (send to 0x0)
        transfer::public_transfer(old_coin, @0x0);

        // Calculate New Amount
        // Rate = NewSupply / OldSupplySnapshot
        // NewAmount = (Amount * NewSupply) / OldSupplySnapshot
        // Use u128 for calculation
        let new_supply = (pool.new_supply as u128);
        let old_supply = pool.old_supply_snapshot;
        let amount_u128 = (amount as u128);

        // Check for division by zero (should not happen if initialized correctly)
        assert!(old_supply > 0, EInvalidSupply);

        let new_amount_u128 = (amount_u128 * new_supply) / old_supply;
        let new_amount = (new_amount_u128 as u64);

        // Take New Coin from Pool
        let new_coin = coin::take(&mut pool.new_token_balance, new_amount, ctx);

        // Send to User
        transfer::public_transfer(new_coin, tx_context::sender(ctx));
    }

    // --- Phase 3: Finalize (Admin) ---
    public fun finalize_and_add_lp<OldCoin, NewCoin>(
        _admin: &AdminCap,
        pool: &mut MigrationPool<OldCoin, NewCoin>,
        vault: &mut OldTokenVault<OldCoin>,
        pool_registry: &mut PoolRegistry,
        versioned: &Versioned,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!pool.is_finalized, EAlreadyFinalized);

        // Verify Vault ID matches
        assert!(object::id(vault) == pool.vault_id, ENotInitialized);

        // 1. Withdraw SUI from Vault (Liquidity for New Pool)
        // We withdraw ALL SUI.
        let (_, locked_sui_amount) = vault::get_locked_amounts(vault);
        let sui_balance = vault::withdraw_sui(vault, locked_sui_amount, ctx);
        let sui_coin = coin::from_balance(sui_balance, ctx);

        // 2. Calculate Initial Price
        // Market Cap = Locked SUI
        // Price = Market Cap / New Supply
        let new_sqrt_price = pool_math::compute_initial_sqrt_price(
            (locked_sui_amount as u128),
            (pool.new_supply as u128)
        );

        // 3. Create Pool
        let new_fee_rate = 3000;

        flowx_clmm_adapter::create_pool<NewCoin, sui::sui::SUI>(
            pool_registry,
            versioned,
            new_fee_rate,
            new_sqrt_price,
            clock,
            ctx
        );

        // 4. Add Liquidity?
        // "admin can create new pool for new token and adđ lp"
        // We have SUI. We might need NewCoin too?
        // If we minted ALL NewCoin to the pool, and users claim it,
        // then the pool has the remaining NewCoin (unclaimed).
        // But usually, we want to pair the SUI with NewCoin to provide liquidity.
        // Wait, if we give users NewCoin, they hold it.
        // If we put SUI into LP, we need NewCoin to pair with it?
        // Or is it single-sided? FlowX CLMM allows single-sided if price is set?
        // If we just create the pool, price is set.
        // To add liquidity, we need both tokens usually, unless we add out of range.
        // But we want to support trading.
        // If we put ALL SUI into the pool, we are buying NewCoin?
        // The user said: "adđ lp".
        // So we should give the SUI to the admin.
        transfer::public_transfer(sui_coin, tx_context::sender(ctx));

        // Mark finalized
        pool.is_finalized = true;

        // Emit Event
        events::emit_migration_completed(
            object::id(pool_registry), // Placeholder
            object::id(pool_registry), // Placeholder
            0, // Locked Old (we don't track it here easily unless we read vault)
            locked_sui_amount,
            pool.new_supply,
            new_sqrt_price,
            sui::clock::timestamp_ms(clock)
        );
    }
}
