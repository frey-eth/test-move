module migrate_fun_sui::events {
    use sui::event;
    use sui::object::{ID};

    /// Emitted when a migration is successfully completed.
    public struct MigrationCompleted has copy, drop {
        old_pool: ID,
        new_pool: ID, // This might not be available directly if we just create and don't get the ID back immediately in v2
                      // But we can emit the coin types.
        coin_type_x: vector<u8>, // ASCII string of type
        coin_type_y: vector<u8>,
        old_market_cap: u128,
        new_start_price_x64: u128,
        new_supply: u64,
        timestamp: u64
    }

    public fun emit_migration_completed(
        old_pool: ID,
        new_pool: ID,
        coin_type_x: vector<u8>,
        coin_type_y: vector<u8>,
        old_market_cap: u128,
        new_start_price_x64: u128,
        new_supply: u64,
        timestamp: u64
    ) {
        event::emit(MigrationCompleted {
            old_pool,
            new_pool,
            coin_type_x,
            coin_type_y,
            old_market_cap,
            new_start_price_x64,
            new_supply,
            timestamp
        });
    }
}
