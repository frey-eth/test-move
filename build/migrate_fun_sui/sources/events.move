module migrate_fun_sui::events {
    use sui::object::{ID};
    use sui::event;
    use std::ascii::{String};

    // --- Event Structs (Internal Use or Public Inspection) ---

    public struct MigrationInitialized has copy, drop {
        migration_id: ID,
        old_token: String,
        new_token: String,
        ratio: u64,
        start_time: u64
    }

    public struct LiquidityLocked has copy, drop {
        migration_id: ID,
        old_token_amount: u64,
        sui_amount: u64
    }

    public struct UserMigrated has copy, drop {
        migration_id: ID,
        user: address,
        old_amount_burned: u64,
        new_amount_minted: u64
    }

    public struct MigrationFinalized has copy, drop {
        migration_id: ID,
        timestamp: u64
    }

    public struct NewPoolCreated has copy, drop {
        migration_id: ID,
        pool_id: ID,
        liquidity_amount: u128
    }

    // --- Public Emitters ---

    public fun emit_migration_initialized(
        migration_id: ID,
        old_token: String,
        new_token: String,
        ratio: u64,
        start_time: u64
    ) {
        event::emit(MigrationInitialized {
            migration_id,
            old_token,
            new_token,
            ratio,
            start_time
        });
    }

    public fun emit_liquidity_locked(
        migration_id: ID,
        old_token_amount: u64,
        sui_amount: u64
    ) {
        event::emit(LiquidityLocked {
            migration_id,
            old_token_amount,
            sui_amount
        });
    }

    public fun emit_user_migrated(
        migration_id: ID,
        user: address,
        old_amount_burned: u64,
        new_amount_minted: u64
    ) {
        event::emit(UserMigrated {
            migration_id,
            user,
            old_amount_burned,
            new_amount_minted
        });
    }

    public fun emit_migration_finalized(
        migration_id: ID,
        timestamp: u64
    ) {
        event::emit(MigrationFinalized {
            migration_id,
            timestamp
        });
    }

    public fun emit_new_pool_created(
        migration_id: ID,
        pool_id: ID,
        liquidity_amount: u128
    ) {
        event::emit(NewPoolCreated {
            migration_id,
            pool_id,
            liquidity_amount
        });
    }
}
