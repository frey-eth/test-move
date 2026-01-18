
module migrate_fun_sui::flowx_clmm_adapter {
    use sui::coin::{Self, Coin};
    use sui::clock::{Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    
    // Import FlowX modules from the dependency
    use flowx_clmm::pool::{Self};
    use flowx_clmm::pool_manager::{Self, PoolRegistry};
    use flowx_clmm::versioned::{Versioned};
    use flowx_clmm::position_manager::{Self, PositionRegistry};
    use flowx_clmm::utils;
    use flowx_clmm::i32;

    // --- Reader Functions ---

    /// Read the state of an existing FlowX Pool.
    /// Returns (Reserve X, Reserve Y, SqrtPrice).
    public fun read_pool_state<X, Y>(
        pool_registry: &PoolRegistry,
        fee_rate: u64
    ): (u64, u64, u128) {
        if (utils::is_ordered<X, Y>()) {
            let pool = pool_manager::borrow_pool<X, Y>(pool_registry, fee_rate);
            let sqrt_price = pool::sqrt_price_current(pool);
            let (res_x, res_y) = pool::reserves(pool);
            (res_x, res_y, sqrt_price)
        } else {
            // Pool is stored as <Y, X>
            let pool = pool_manager::borrow_pool<Y, X>(pool_registry, fee_rate);
            let sqrt_price = pool::sqrt_price_current(pool); // Price is for Y/X
            let (res_y, res_x) = pool::reserves(pool); // Returns (Y, X)
            (res_x, res_y, sqrt_price)
        }
    }

    // --- Writer Functions ---

    /// Create a new pool using FlowX logic.
    /// Wrapper for `pool_manager::create_and_initialize_pool`.
    public fun create_pool<X, Y>(
        pool_registry: &mut PoolRegistry,
        versioned: &Versioned,
        fee_rate: u64,
        initial_sqrt_price: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        pool_manager::create_and_initialize_pool<X, Y>(
            pool_registry,
            fee_rate,
            initial_sqrt_price,
            versioned,
            clock,
            ctx
        );
    }
    
    /// Add Liquidity to a pool.
    /// Orchestrates open_position and increase_liquidity.
    /// Transfers the Position object to the sender.
    public fun add_liquidity<X, Y>(
        position_registry: &mut PositionRegistry,
        pool_registry: &mut PoolRegistry,
        fee_rate: u64,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        tick_lower: u32,
        tick_upper: u32,
        versioned: &Versioned,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let _amount_x = coin::value(&coin_x); // Unused vars usually prefixed
        let _amount_y = coin::value(&coin_y);
        
        // Convert u32 ticks to I32. Assumes positive ticks for simplicity.
        // If ticks are conceptually negative, caller must handle it, 
        // but since input is u32, we treat it as positive index or raw.
        let lower = i32::from(tick_lower);
        let upper = i32::from(tick_upper);

        // 1. Open Position
        // Note: open_position transfers the object to sender? No, it returns Position.
        let mut position = position_manager::open_position<X, Y>(
            position_registry,
            pool_registry,
            fee_rate,
            lower,
            upper,
            versioned,
            ctx
        );

        // 2. Increase Liquidity
        position_manager::increase_liquidity<X, Y>(
            pool_registry,
            &mut position,
            coin_x,
            coin_y,
            0, // min_x
            0, // min_y
            sui::clock::timestamp_ms(clock) + 1000000, // Deadline
            versioned,
            clock,
            ctx
        );

        // 3. Transfer Position to Sender (Admin/Protocol)
        transfer::public_transfer(position, tx_context::sender(ctx));
    }
}
