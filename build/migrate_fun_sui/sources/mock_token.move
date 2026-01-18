module migrate_fun_sui::mock_token {
    use sui::coin::{Self, Coin, TreasuryCap};



    public struct MOCK_TOKEN has drop {}

    fun init(witness: MOCK_TOKEN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            9,
            b"OLD",
            b"Old Token",
            b"Mock Old Token for Migration",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(MOCK_TOKEN {}, ctx);
    }

    public fun mint(
        treasury: &mut TreasuryCap<MOCK_TOKEN>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<MOCK_TOKEN> {
        coin::mint(treasury, amount, ctx)
    }
}
