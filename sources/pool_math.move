module migrate_fun_sui::pool_math {

    // --- Error Codes ---
    const EInvalidSupply: u64 = 1;
    const EOverflow: u64 = 2;

    // --- Math Functions ---

    /// Compute the implied Market Cap of the OLD token.
    /// MC = Price * Supply
    /// Price = ReserveY (SUI) / ReserveX (Old Token)
    /// MC = (ReserveY * Supply) / ReserveX
    public fun compute_market_cap(
        reserve_x: u128, // Old Token Reserve
        reserve_y: u128, // SUI Reserve (Quote)
        supply: u128     // Old Token Total Supply
    ): u128 {
        // We use u128 to prevent overflow during intermediate multiplication
        // MC = (ReserveY * Supply) / ReserveX
        // Assumption: X is the Base Token, Y is the Quote Token (SUI)

        // Safety checks
        if (reserve_x == 0) return 0;

        let numerator = reserve_y * supply;
        if (numerator < reserve_y || numerator < supply) abort EOverflow; // Basic overflow check

        numerator / reserve_x
    }

    /// Compute the initial SqrtPriceX64 for the NEW pool.
    /// New Price = Old MC / New Supply
    /// SqrtPrice = sqrt(Price) * 2^64
    /// This function returns the Q64.64 sqrt_price.
    ///
    /// Note: This is an approximation. For CLMM, we need precise SqrtPriceX64.
    /// Price = y / x
    /// SqrtPrice = sqrt(y / x) * 2^64
    public fun compute_initial_sqrt_price(
        market_cap: u128,
        new_supply: u128
    ): u128 {
        if (new_supply == 0) abort EInvalidSupply;

        // Target Price = MC / Supply
        // We need sqrt(Target Price) * 2^64

        // 1. Calculate Price with high precision (scale by 2^128 potentially)
        // Or better, let's look at the relationship:
        // P = MC / S
        // sqrt(P) = sqrt(MC) / sqrt(S)
        // result = (sqrt(MC) * 2^64) / sqrt(S)

        let sqrt_mc = sqrt_u128(market_cap);
        let sqrt_s = sqrt_u128(new_supply);

        if (sqrt_s == 0) abort EInvalidSupply;

        // Q64.64 fixed point number
        let q64 = 18446744073709551616; // 2^64

        (sqrt_mc * q64) / sqrt_s
    }

    /// Helper: Integer Square Root for u128
    fun sqrt_u128(y: u128): u128 {
        if (y < 4) {
            if (y == 0) return 0;
            return 1
        };
        let z = y;
        let x = y / 2 + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        };
        z
    }
}
