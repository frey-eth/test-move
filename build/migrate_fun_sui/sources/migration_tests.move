#[test_only]
module migrate_fun_sui::migration_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::tx_context;
    use std::vector;
    use sui::transfer;

    use migrate_fun_sui::migration::{Self, MigrationConfig};
    use migrate_fun_sui::vault::{Self, Vault};
    use migrate_fun_sui::mock_token::{Self, MOCK_TOKEN};
    use migrate_fun_sui::mock_new_token::{Self, MOCK_NEW_TOKEN};
    
    // Mock FlowX dependencies for compilation (cannot test actual FlowX logic easily without their test utils)
    // We will simulate the "Create Pool" step by ensuring the function calls succeed, 
    // but the actual FlowX interaction might be stubbed if we mocked the adapter.
    // However, since we use the REAL adapter which calls logic we don't have simulated, 
    // the "Create New Pool" test might fail if FlowX packages aren't available in test mode?
    // Actually, `flowx_clmm` is a dependency. If it's a real Mainnet dependency, we can't run it in tests unless we have the bytecode?
    // We'll focus on Phases 1-4 first. Phase 5 might need a specific environment.

    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;


    const MOCK_OLD_SUPPLY: u64 = 1_000_000_000; // 1000 Tokens
    const MOCK_NEW_SUPPLY: u64 = 1_000_000_000; // 1000 Tokens
    const USER1_AMOUNT: u64 = 100_000_000; // 100 Tokens

    // Helper to setup scenario
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // 1. Setup Clock
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::share_for_testing(clock);

        // 2. Mint Tokens
        // Need to initialize MockToken and MockNewToken to get treasuries?
        // We'll mock minting via coin::mint_for_testing as a shortcut if we owned the Treasury capabilities?
        // Or we use the module's init?
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            mock_token::init_for_testing(test_scenario::ctx(&mut scenario));
            mock_new_token::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        scenario
    }

    // Helper to get hash for a leaf
    // We want to match snapshot::hash_leaf exactly.
    // Since we made snapshot::hash_leaf public(package), we can USE IT directly!
    // This avoids code duplication and errors.
    fun get_leaf(user: address, amount: u64): vector<u8> {
        migrate_fun_sui::snapshot::hash_leaf(user, amount)
    }

    #[test]
    fun test_happy_path_migration() {
        let mut scenario = setup_test();
        
        // --- PREP: Get Treasuries and Coins ---
        test_scenario::next_tx(&mut scenario, ADMIN);
        let mut new_treasury = test_scenario::take_from_sender<TreasuryCap<MOCK_NEW_TOKEN>>(&scenario);
        let mut old_treasury = test_scenario::take_from_sender<TreasuryCap<MOCK_TOKEN>>(&scenario);
        let clock = test_scenario::take_shared<Clock>(&scenario);

        // Mint Old Tokens for User
        let user_old_coins = coin::mint(&mut old_treasury, USER1_AMOUNT, test_scenario::ctx(&mut scenario));
        transfer::public_transfer(user_old_coins, USER1);

        // Mint Old Tokens for Liquidity (to lock)
        let liquidity_old_coins = coin::mint(&mut old_treasury, 500_000_000, test_scenario::ctx(&mut scenario));
        // Mint SUI for Liquidity
        let liquidity_sui = coin::mint_for_testing<sui::sui::SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));

        // --- PHASE 1: Initialize ---
        // Snapshot: 1 User. Root = Leaf.
        let root = get_leaf(USER1, USER1_AMOUNT);
        
        migration::initialize_migration<MOCK_TOKEN, MOCK_NEW_TOKEN>(
            new_treasury,
            MOCK_OLD_SUPPLY,
            MOCK_NEW_SUPPLY,
            root,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, ADMIN);
        // Verify Config and Vault created
        let mut config = test_scenario::take_shared<MigrationConfig<MOCK_TOKEN, MOCK_NEW_TOKEN>>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<MOCK_TOKEN>>(&scenario);

        // --- PHASE 2: Lock Liquidity ---
        migration::lock_liquidity(
            &config,
            &mut vault,
            liquidity_sui,
            liquidity_old_coins,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(clock);
        test_scenario::return_to_sender(&scenario, old_treasury); // Done with old treasury

        // --- PHASE 3: User Migrate ---
        test_scenario::next_tx(&mut scenario, USER1);
        let mut config = test_scenario::take_shared<MigrationConfig<MOCK_TOKEN, MOCK_NEW_TOKEN>>(&scenario);
        let user_coins = test_scenario::take_from_sender<Coin<MOCK_TOKEN>>(&scenario);
        
        // Proof is empty for single leaf
        let proof = vector::empty<vector<u8>>();

        migration::migrate(
            &mut config,
            user_coins,
            USER1_AMOUNT,
            proof,
            test_scenario::ctx(&mut scenario)
        );

        // Check if user got new tokens
        // Ratio 1:1 since supplies match
        test_scenario::return_shared(config);
        
        test_scenario::next_tx(&mut scenario, USER1);
        let new_coins = test_scenario::take_from_sender<Coin<MOCK_NEW_TOKEN>>(&scenario);
        assert!(coin::value(&new_coins) == USER1_AMOUNT, 0);
        test_scenario::return_to_sender(&scenario, new_coins);

        // --- PHASE 4: Finalize ---
        test_scenario::next_tx(&mut scenario, ADMIN);
        let mut config = test_scenario::take_shared<MigrationConfig<MOCK_TOKEN, MOCK_NEW_TOKEN>>(&scenario);
        migration::finalize_migration(&mut config, test_scenario::ctx(&mut scenario));
        test_scenario::return_shared(config);

        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = migration::EExceedsSnapshotQuota)]
    fun test_exceed_quota() {
        let mut scenario = setup_test();
        test_scenario::next_tx(&mut scenario, ADMIN);
        let new_treasury = test_scenario::take_from_sender<TreasuryCap<MOCK_NEW_TOKEN>>(&scenario);
        let clock = test_scenario::take_shared<Clock>(&scenario);

        // Root for 100 tokens
        let root = get_leaf(USER1, 100);

        migration::initialize_migration<MOCK_TOKEN, MOCK_NEW_TOKEN>(
            new_treasury,
            1000, 1000,
            root,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        test_scenario::return_shared(clock);

        test_scenario::next_tx(&mut scenario, USER1);
        let mut config = test_scenario::take_shared<MigrationConfig<MOCK_TOKEN, MOCK_NEW_TOKEN>>(&scenario);
        
        // Use cheat to mint coins for user > 100
        let coins = coin::mint_for_testing<MOCK_TOKEN>(101, test_scenario::ctx(&mut scenario));
        
        // Try to migrate 101, claim quota is 100
        migration::migrate(
            &mut config,
            coins,
            100, // Claimed Quota
            vector::empty(), 
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::return_shared(config);
        test_scenario::end(scenario);
    }
}
