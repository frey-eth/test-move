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
    use migrate_fun_sui::mft_token::{Self, MFT_TOKEN};
    
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;

    const MOCK_OLD_SUPPLY: u64 = 1_000_000_000; 
    const MOCK_NEW_SUPPLY: u64 = 1_000_000_000; 
    const USER1_AMOUNT: u64 = 1_000_000; // 1M

    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // 1. Setup Clock
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::share_for_testing(clock);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            mock_token::init_for_testing(test_scenario::ctx(&mut scenario));
            mock_new_token::init_for_testing(test_scenario::ctx(&mut scenario));
            mft_token::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        scenario
    }

    fun get_leaf(user: address, amount: u64): vector<u8> {
        migrate_fun_sui::snapshot::hash_leaf(user, amount)
    }

    #[test]
    fun test_mft_migration_flow() {
        let mut scenario = setup_test();
        
        // --- PREP ---
        test_scenario::next_tx(&mut scenario, ADMIN);
        let mut new_treasury = test_scenario::take_from_sender<TreasuryCap<MOCK_NEW_TOKEN>>(&scenario);
        let mut receipt_treasury = test_scenario::take_from_sender<TreasuryCap<MFT_TOKEN>>(&scenario);
        let mut old_treasury = test_scenario::take_from_sender<TreasuryCap<MOCK_TOKEN>>(&scenario);
        let clock = test_scenario::take_shared<Clock>(&scenario);

        // Mint Old Tokens
        let user_old_coins = coin::mint(&mut old_treasury, USER1_AMOUNT, test_scenario::ctx(&mut scenario));
        transfer::public_transfer(user_old_coins, USER1);

        // Mint for Liquidity (Setup Vault later)
        let liquidity_sui = coin::mint_for_testing<sui::sui::SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));

        // --- PHASE 1: Initialize ---
        let root = get_leaf(USER1, USER1_AMOUNT);
        
        migration::initialize_migration<MOCK_TOKEN, MOCK_NEW_TOKEN, MFT_TOKEN>(
            new_treasury,
            receipt_treasury,
            MOCK_OLD_SUPPLY,
            MOCK_NEW_SUPPLY,
            root,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, ADMIN);
        let mut config = test_scenario::take_shared<MigrationConfig<MOCK_TOKEN, MOCK_NEW_TOKEN, MFT_TOKEN>>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<MOCK_TOKEN>>(&scenario);

        // --- PHASE 3: Migrate (Get MFT) ---
        test_scenario::next_tx(&mut scenario, USER1);
        let user_coins = test_scenario::take_from_sender<Coin<MOCK_TOKEN>>(&scenario);
        
        migration::migrate(
            &mut config,
            &mut vault,
            user_coins,
            USER1_AMOUNT,
            vector::empty(),
            test_scenario::ctx(&mut scenario)
        );

        // Verify MFT Received
        test_scenario::next_tx(&mut scenario, USER1);
        let mft_coins = test_scenario::take_from_sender<Coin<MFT_TOKEN>>(&scenario);
        assert!(coin::value(&mft_coins) == USER1_AMOUNT, 1); 

        // Verify Vault Received Old Tokens
        let (_, old_bal) = vault::balances(&vault);
        assert!(old_bal == USER1_AMOUNT, 2);

        test_scenario::return_to_sender(&scenario, mft_coins);
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        test_scenario::return_to_sender(&scenario, old_treasury);
        
        coin::burn_for_testing(liquidity_sui);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}

