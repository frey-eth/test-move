module migrate_fun_sui::mock_new_token {
    use sui::coin::{Self, Coin, TreasuryCap};



    public struct MOCK_NEW_TOKEN has drop {}

    fun init(witness: MOCK_NEW_TOKEN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            9,
            b"NEW",
            b"New Token",
            b"Mock New Token for Migration",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(MOCK_NEW_TOKEN {}, ctx);
    }

    public fun mint(
        treasury: &mut TreasuryCap<MOCK_NEW_TOKEN>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<MOCK_NEW_TOKEN> {
        coin::mint(treasury, amount, ctx)
    }
}
