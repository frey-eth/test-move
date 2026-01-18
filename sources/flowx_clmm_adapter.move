module migrate_fun_sui::flowx_clmm_adapter {
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::clock::{Clock};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};

    // Import FlowX modules from the dependency
    use flowx_clmm::pool::{Self, Pool};
    use flowx_clmm::pool_manager::{Self, PoolRegistry};
    use flowx_clmm::versioned::{Versioned};
    use flowx_clmm::position::{Self, Position};
    use flowx_clmm::position_manager;

    // --- Error Codes ---
    const EPoolNotFound: u64 = 1;

    // --- Structs ---
    // --- Reader Functions ---

    /// Read the state of an existing FlowX Pool.
    /// Returns (Reserve X, Reserve Y, SqrtPrice).
    public fun read_pool_state<X, Y>(
        pool_registry: &PoolRegistry,
        fee_rate: u64
    ): (u64, u64, u128) {
        // Borrow the pool.
        let pool = pool_manager::borrow_pool<X, Y>(pool_registry, fee_rate);

        let sqrt_price = pool::sqrt_price_current(pool);
        let (res_x, res_y) = pool::reserves(pool);

        (res_x, res_y, sqrt_price)
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

    /*
    /// Add Liquidity to a pool.
    /// Disabled for MVP. Requires PositionManager.
    public fun add_liquidity<X, Y>(
        config: &position_manager::GlobalConfig,
        pool_registry: &mut PoolRegistry,
        fee_rate: u64,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        tick_lower: u32,  // Simplified types for adapter
        tick_upper: u32,
        versioned: &Versioned,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let amount_x = coin::value(&coin_x);
        let amount_y = coin::value(&coin_y);

        position_manager::mint<X, Y>(
            config,
            pool_registry,
            fee_rate,
            tick_lower,
            tick_upper,
            amount_x,
            amount_y,
            0,
            0,
            coin::into_balance(coin_x),
            coin::into_balance(coin_y),
            tx_context::sender(ctx),
            versioned,
            clock,
            ctx
        );
    }
    */
    /// Remove all liquidity from a position.
    /// Returns the withdrawn Coin<X> and Coin<Y>.
    public fun remove_all_liquidity<X, Y>(
        pool_registry: &mut PoolRegistry,
        position: &mut Position,
        versioned: &Versioned,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>) {
        let liquidity = position::liquidity(position);

        // 1. Decrease Liquidity
        // We need a deadline. Usually timestamp + something.
        // Or just current timestamp if strict?
        // Let's use timestamp + 1000ms just to be safe, or just timestamp.
        let deadline = sui::clock::timestamp_ms(clock) + 1000;

        // Note: decrease_liquidity takes &TxContext (read-only)
        // But we have &mut TxContext. We can freeze it? No.
        // We can pass it as immutable? Yes, &mut T can be coerced to &T.

        position_manager::decrease_liquidity<X, Y>(
            pool_registry,
            position,
            liquidity,
            0, // min_amount_x
            0, // min_amount_y
            deadline,
            versioned,
            clock,
            ctx // Coerced to &TxContext
        );

        // 2. Collect Owed Tokens
        // We request the max amount possible (u64::MAX) to collect everything owed.
        // Assuming collect caps at what is owed.
        let max_u64 = 18446744073709551615;

        let (coin_x, coin_y) = position_manager::collect<X, Y>(
            pool_registry,
            position,
            max_u64,
            max_u64,
            versioned,
            clock,
            ctx
        );

        (coin_x, coin_y)
    }
}
