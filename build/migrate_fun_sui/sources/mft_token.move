module migrate_fun_sui::mft_token {
    use sui::coin::{Self, TreasuryCap};
    use sui::url;

    public struct MFT_TOKEN has drop {}

    fun init(witness: MFT_TOKEN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness, 
            9, 
            b"MFT", 
            b"MigrateFun Receipt", 
            b"Receipt token for migration claims", 
            option::none(), 
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let witness = MFT_TOKEN {};
        init(witness, ctx);
    }
}
