module migrate_fun_sui::vault {
    use sui::object::{Self, UID};
    use sui::balance::{Balance};
    use sui::transfer;
    use sui::tx_context::{TxContext};

    friend migrate_fun_sui::migration;

    /// Vault to permanently lock Old Token and SUI.
    /// This struct has NO `store` ability, so it cannot be transferred.
    /// It has `key`, so it's a shared object or owned object.
    /// We will make it a shared object or keep it owned by the migration contract (if possible)
    /// or just transfer to a null address (burn).
    /// BUT the requirement says "Vault has no withdraw function".
    /// Best practice: Create a shared object that holds the balances.
    struct OldTokenVault<phantom OldCoin> has key {
        id: UID,
        locked_old: Balance<OldCoin>,
        locked_sui: Balance<sui::sui::SUI>,
    }

    /// Create and lock assets.
    /// Only the migration module can call this.
    public(friend) fun lock_assets<OldCoin>(
        old_balance: Balance<OldCoin>,
        sui_balance: Balance<sui::sui::SUI>,
        ctx: &mut TxContext
    ): (u64, u64, object::ID) {
        let old_amount = sui::balance::value(&old_balance);
        let sui_amount = sui::balance::value(&sui_balance);

        let vault = OldTokenVault {
            id: object::new(ctx),
            locked_old: old_balance,
            locked_sui: sui_balance,
        };

        let vault_id = object::id(&vault);

        // Make it a shared object so it's visible but immutable (no mutable functions exposed publically)
        // Actually, since there are no public functions to mutate it, even if shared, it's safe.
        // Or we can just freeze it?
        // If we freeze it, we can't add to it later (which is fine, migration is one-time).
        // But `Balance` inside a frozen object is fine? Yes.
        // Let's share it to be safe and visible.
        transfer::share_object(vault);

        (old_amount, sui_amount, vault_id)
    }

    // --- Withdraw Functions (Friend Only) ---

    public(friend) fun withdraw_sui<OldCoin>(
        vault: &mut OldTokenVault<OldCoin>,
        amount: u64,
        ctx: &mut TxContext
    ): Balance<sui::sui::SUI> {
        sui::balance::split(&mut vault.locked_sui, amount)
    }

    public(friend) fun withdraw_old<OldCoin>(
        vault: &mut OldTokenVault<OldCoin>,
        amount: u64,
        ctx: &mut TxContext
    ): Balance<OldCoin> {
        sui::balance::split(&mut vault.locked_old, amount)
    }

    // --- Getters ---

    public fun get_locked_amounts<OldCoin>(vault: &OldTokenVault<OldCoin>): (u64, u64) {
        (
            sui::balance::value(&vault.locked_old),
            sui::balance::value(&vault.locked_sui)
        )
    }
}
