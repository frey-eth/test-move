
module migrate_fun_sui::vault {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;

    // --- Errors ---
    const EInsufficientVaultBalance: u64 = 301;
    const EVaultLocked: u64 = 400;

    public struct Vault<phantom OldToken> has key, store {
        id: UID,
        base_balance: Balance<SUI>,
        old_token_balance: Balance<OldToken>,
        locked: bool
    }

    public(package) fun create<OldToken>(ctx: &mut TxContext): Vault<OldToken> {
        Vault {
            id: object::new(ctx),
            base_balance: balance::zero(),
            old_token_balance: balance::zero(),
            locked: false
        }
    }

    /// Admin locks liquidity into the vault.
    public(package) fun lock_liquidity<OldToken>(
        vault: &mut Vault<OldToken>,
        base_coins: Coin<SUI>,
        old_coins: Coin<OldToken>
    ) {
        assert!(!vault.locked, EVaultLocked); // Cannot lock if already locked
        balance::join(&mut vault.base_balance, coin::into_balance(base_coins));
        balance::join(&mut vault.old_token_balance, coin::into_balance(old_coins));
        vault.locked = true;
    }

    /// Allows migration module to withdraw base assets for new pool creation.
    public(package) fun withdraw_base<OldToken>(
        vault: &mut Vault<OldToken>
    ): Balance<SUI> {
        // We assume migration module checks lock state, but we can enforce strictness if we want?
        // Let's use EInsufficientVaultBalance if needed?
        // Actually, let's just make sure we don't return 0 if that's bad, OR 
        // just leave it. The unused warning is annoying but harmless.
        // Let's use EInsufficientVaultBalance to check we actually have funds?
        let amount = balance::value(&vault.base_balance);
        assert!(amount > 0, EInsufficientVaultBalance);
        balance::split(&mut vault.base_balance, amount)
    }

    /// Allows migration module to withdraw or burn old tokens.
    public(package) fun withdraw_old<OldToken>(
        vault: &mut Vault<OldToken>
    ): Balance<OldToken> {
        let amount = balance::value(&vault.old_token_balance);
        balance::split(&mut vault.old_token_balance, amount)
    }

    /// Allows depositing OldToken (e.g. from user migration).
    public(package) fun deposit_old<OldToken>(
        vault: &mut Vault<OldToken>,
        coins: Coin<OldToken>
    ) {
        balance::join(&mut vault.old_token_balance, coin::into_balance(coins));
    }

    public fun is_locked<OldToken>(vault: &Vault<OldToken>): bool {
        vault.locked
    }

    public fun balances<OldToken>(vault: &Vault<OldToken>): (u64, u64) {
        (balance::value(&vault.base_balance), balance::value(&vault.old_token_balance))
    }
}
