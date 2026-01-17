module migrate_fun_sui::mock_new_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;

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
        transfer::public_share_object(treasury); // Share treasury so anyone can mint for testing
    }

    public fun mint(
        treasury: &mut TreasuryCap<MOCK_NEW_TOKEN>, 
        amount: u64, 
        ctx: &mut TxContext
    ): Coin<MOCK_NEW_TOKEN> {
        coin::mint(treasury, amount, ctx)
    }
}
