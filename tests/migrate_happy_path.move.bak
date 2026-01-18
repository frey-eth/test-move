#[test_only]
module migrate_fun_sui::migrate_happy_path {
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    
    use migrate_fun_sui::migration_project::{Self, MigrationProject, AdminCap};
    use migrate_fun_sui::mft_receipt::{Self, MftTreasury};
    use migrate_fun_sui::user_migration::{Self, UserMigration};
    use migrate_fun_sui::claim_with_mft;
    use migrate_fun_sui::migration_vault::{Self};
    use migrate_fun_sui::admin_controls;

    // --- Mock Tokens ---
    public struct OLD has drop {}
    public struct NEW has drop {}

    // --- Test Data ---
    const ADMIN: address = @0xAD;
    const USER1: address = @0x10;
    const START_TIME: u64 = 100000;
    const DURATION: u64 = 100000; // Ends at 200000
    // Claim Start = End + 24h = 200000 + 86400000.
    
    #[test]
    fun test_migration_flow() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // 1. Setup Phase
        let (mut clock, project_id) = setup(&mut scenario);
        
        // 2. User Migrates
        test_scenario::next_tx(&mut scenario, USER1);
        {
             let mut project = test_scenario::take_shared<MigrationProject<OLD, NEW>>(&scenario);
             
             // Update clock to start time
             clock::set_for_testing(&mut clock, START_TIME);
             
             // Mint OLD tokens for user
             let old_tokens = coin::mint_for_testing<OLD>(1000, test_scenario::ctx(&mut scenario));
             
             let user_mig = migration_project::migrate(
                &mut project,
                &clock,
                old_tokens,
                test_scenario::ctx(&mut scenario)
             );
             
             // Check User State
             assert!(user_migration::amount_migrated(&user_mig) == 1000, 0);
             
             transfer::public_transfer(user_mig, USER1);
             test_scenario::return_shared(project);
        };
        
        // 3. User Checks Receipt (MFT)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mft_coin = test_scenario::take_from_sender<Coin<migrate_fun_sui::mft_receipt::MFT_RECEIPT>>(&scenario);
            assert!(coin::value(&mft_coin) == 1000, 1);
            test_scenario::return_to_sender(&scenario, mft_coin);
        };

        // 4. Admin Funds Vault with NEW tokens
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut project = test_scenario::take_shared<MigrationProject<OLD, NEW>>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            // Need 2000 NEW tokens (1000 * 2/1 rate)
            let new_tokens = coin::mint_for_testing<NEW>(2000, test_scenario::ctx(&mut scenario));
            
            // use migrate_fun_sui::admin_controls;
            admin_controls::deposit_new_tokens(&mut project, &cap, new_tokens);
            
            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(project);
        };

        // 5. Fast Forward to Claims Phase
        test_scenario::next_tx(&mut scenario, USER1);
        {
             let mut project = test_scenario::take_shared<MigrationProject<OLD, NEW>>(&scenario);
             let mut user_mig = test_scenario::take_from_sender<UserMigration>(&scenario);
             let mft_coin = test_scenario::take_from_sender<Coin<migrate_fun_sui::mft_receipt::MFT_RECEIPT>>(&scenario);
             
             // Set time to Claim Start
             let claim_start = START_TIME + DURATION + 86400000;
             clock::set_for_testing(&mut clock, claim_start + 1);
             
             let new_coin = claim_with_mft::claim(
                &mut project,
                &mut user_mig,
                mft_coin,
                &clock,
                test_scenario::ctx(&mut scenario)
             );
             
             assert!(coin::value(&new_coin) == 2000, 2);
             assert!(user_migration::amount_claimed(&user_mig) == 2000, 3);
             
             transfer::public_transfer(new_coin, USER1);
             test_scenario::return_to_sender(&scenario, user_mig);
             test_scenario::return_shared(project);
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
    
    fun setup(scenario: &mut Scenario): (Clock, ID) {
        let ctx = test_scenario::ctx(scenario);
        let clock = clock::create_for_testing(ctx);
        
        // Init MFT
        mft_receipt::init_for_testing(ctx);
        
        test_scenario::next_tx(scenario, ADMIN);
        let treasury = test_scenario::take_from_sender<MftTreasury>(scenario);
        
        // Create Project
        migration_project::create_project<OLD, NEW>(
            treasury,
            START_TIME,
            DURATION,
            2, 1, // Rate 2/1
            100, // Min target
            test_scenario::ctx(scenario)
        );
        
        test_scenario::next_tx(scenario, ADMIN);
        let project = test_scenario::take_shared<MigrationProject<OLD, NEW>>(scenario);
        let id = object::id(&project);
        test_scenario::return_shared(project);
        
        (clock, id)
    }
}
