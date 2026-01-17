module migrate_fun_sui::mock_sui {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;

    public struct MOCK_SUI has drop {}

    fun init(witness: MOCK_SUI, ctx: &mut TxContext) {
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
        transfer::public_share_object(treasury); // Share treasury so anyone can mint for testing
    }

    public fun mint(
        treasury: &mut TreasuryCap<MOCK_SUI>, 
        amount: u64, 
        ctx: &mut TxContext
    ): Coin<MOCK_SUI> {
        coin::mint(treasury, amount, ctx)
    }
}
