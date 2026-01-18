module migrate_fun_sui::mock_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option;

    struct MOCK_TOKEN has drop {}

    #[allow(deprecated_usage)]
    fun init(witness: MOCK_TOKEN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            9,
            b"OLD",
            b"Old Token",
            b"Mock Old Token for Migration",
            option::none<sui::url::Url>(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }

    public fun mint(
        treasury: &mut TreasuryCap<MOCK_TOKEN>,
        amount: u64,
        _recipient: address,
        ctx: &mut TxContext
    ): Coin<MOCK_TOKEN> {
        coin::mint(treasury, amount, ctx)
    }
}
