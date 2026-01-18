module migrate_fun_sui::events {
    use sui::event;
    use sui::object;

    /// Emitted when a migration is successfully completed.
    /// Emitted when a migration is successfully completed.
    struct MigrationCompleted has copy, drop {
        old_pool: object::ID,
        new_pool: object::ID,
        locked_old: u64,
        locked_sui: u64,
        new_supply: u64,
        price_new: u128, // Using u128 for SqrtPriceX64 as in previous code
        timestamp: u64
    }

    public fun emit_migration_completed(
        old_pool: object::ID,
        new_pool: object::ID,
        locked_old: u64,
        locked_sui: u64,
        new_supply: u64,
        price_new: u128,
        timestamp: u64
    ) {
        event::emit(MigrationCompleted {
            old_pool,
            new_pool,
            locked_old,
            locked_sui,
            new_supply,
            price_new,
            timestamp
        });
    }
}
