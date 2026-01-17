module migrate_fun_sui::migration {
    use std::type_name;
    use std::ascii;
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Clock};
    
    // Internal modules
    use migrate_fun_sui::flowx_clmm_adapter;
    use migrate_fun_sui::pool_math;
    use migrate_fun_sui::events;

    // External modules
    use flowx_clmm::pool_manager::{PoolRegistry};
    use flowx_clmm::versioned::{Versioned};

    // --- Errors ---
    const EInvalidFeeRate: u64 = 1;

    // --- Structs ---
    
    /// Admin Capability to authorize migration
    public struct AdminCap has key, store {
        id: UID
    }

    /// Module Initialization
    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    // --- Entry Functions ---

    /// Execute the migration.
    /// 1. Calculate Old Market Cap from FlowX Pool state.
    /// 2. Calculate New Initial Price.
    /// 3. Mint New Token Supply.
    /// 4. Create New FlowX Pool (New/SUI) with that price.
    /// 
    /// Assumptions:
    /// - Old Coin is X, SUI is Y (quote) in the Old Pool.
    /// - New Coin will be X, SUI will be Y (quote) in the New Pool.
    /// - Admin provides SUI liquidity if needed (Wait, if we just define price, do we need to provide liquidity immediately?
    ///   Yes, "Seed new pool". We need to put the minted New Tokens into the pool.)
    ///   However, FlowX pool creation initializes the price/tick. Liquidity addition is separate.
    ///   For this MVP, we will:
    ///     a. Create Pool (sets price).
    ///     b. (Optional) Admin should add liquidity in a separate transaction or we try to do it here.
    ///     "Seed new pool" implies adding the tokens. 
    ///     But adding liquidity requires a Position. 
    ///     Let's start with JUST creating the pool with the correct Price, which effectively sets the valuation.
    ///     Actual liquidity provision can be complex (allocating ticks).
    ///     We will focus on Step 1: Create Pool with Correct Price.
    ///     If scope permits, we add liquidity. Given "Simple > complete", Price initialization is the key "Migration" step.
    public entry fun migrate_with_flowx<OldCoin, NewCoin>(
        _admin: &AdminCap,
        pool_registry: &mut PoolRegistry,
        versioned: &Versioned,
        old_fee_rate: u64,
        old_token_supply: u128,
        new_token_treasury: &mut TreasuryCap<NewCoin>,
        new_token_supply: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // 1. Read Old Pool State (OldCoin / SUI)
        // We assume OldCoin is X, SUI is Y.
        // We use SUI as the quote currency.
        // 1. Read Old Pool State (OldCoin / SUI)
        // We assume OldCoin is X, SUI is Y.
        // We use SUI as the quote currency.
        let (reserve_x, reserve_y, _) = flowx_clmm_adapter::read_pool_state<OldCoin, sui::sui::SUI>(
            pool_registry, 
            old_fee_rate
        );

        // 2. Compute Market Cap
        // MC = (Reserve SUI * Supply Old) / Reserve Old
        let old_market_cap_sui = pool_math::compute_market_cap(
            (reserve_x as u128), // Reserve Old
            (reserve_y as u128), // Reserve SUI
            old_token_supply
        );

        // 3. Compute New Initial Price
        // P_new = MC / S_new
        let new_sqrt_price = pool_math::compute_initial_sqrt_price(
            old_market_cap_sui,
            (new_token_supply as u128)
        );

        // 4. Mint New Supply
        // We mint it to the admin (sender) so they can add liquidity manually.
        let new_coins = coin::mint(new_token_treasury, new_token_supply, ctx);
        transfer::public_transfer(new_coins, tx_context::sender(ctx));

        // 5. Create New FlowX Pool
        // We use the same fee rate for simplicity, or hardcode standard 3000 (0.3%).
        let new_fee_rate = 3000;
        
        flowx_clmm_adapter::create_pool<NewCoin, sui::sui::SUI>(
            pool_registry,
            versioned,
            new_fee_rate,
            new_sqrt_price,
            clock,
            ctx
        );

        // 6. Emit Event
        let old_tn = type_name::get<OldCoin>();
        let new_tn = type_name::get<NewCoin>();

        events::emit_migration_completed(
            object::id(pool_registry), // Placeholder
            object::id(pool_registry), // Placeholder
            std::ascii::into_bytes(type_name::get_module(&old_tn)),
            std::ascii::into_bytes(type_name::get_module(&new_tn)),
            old_market_cap_sui,
            new_sqrt_price,
            new_token_supply,
            sui::clock::timestamp_ms(clock)
        );
    }
}
