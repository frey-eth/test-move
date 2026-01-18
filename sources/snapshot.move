module migrate_fun_sui::snapshot {
    use std::vector;
    use sui::address;
    
    const EInvalidProof: u64 = 302;

    /// Verifies that a (user, amount) pair is part of the Merkle Tree defined by `root`.
    /// Proof is a list of sibling hashes (32 bytes each) ordered from leaf to root.
    public fun verify_proof(
        root: vector<u8>,
        user: address,
        amount: u64,
        proof: vector<vector<u8>>
    ) {
        let leaf = hash_leaf(user, amount);
        let computed_root = process_proof(leaf, proof);
        assert!(computed_root == root, EInvalidProof);
    }

    /// Computes the double-hash of the leaf: H(user | amount_bytes)
    /// Made public(package) for testing if needed, but internal logic uses it.
    public(package) fun hash_leaf(user: address, amount: u64): vector<u8> {
        let user_bytes = address::to_bytes(user);
        let amount_bytes = u64_to_bytes(amount); 
        
        let mut payload = vector::empty<u8>();
        vector::append(&mut payload, user_bytes);
        vector::append(&mut payload, amount_bytes);
        
        std::hash::sha3_256(payload)
    }

    /// Iterates through the proof elements to compute the root candidate.
    fun process_proof(leaf: vector<u8>, proof: vector<vector<u8>>): vector<u8> {
        let mut current_hash = leaf;
        let mut i = 0;
        let len = vector::length(&proof);
        
        while (i < len) {
            let sibling = *vector::borrow(&proof, i);
            current_hash = hash_pair(current_hash, sibling);
            i = i + 1;
        };
        current_hash
    }

    /// Sorts the pair (a, b) and hashes them together: H(min(a,b) | max(a,b))
    fun hash_pair(a: vector<u8>, b: vector<u8>): vector<u8> {
        let first;
        let second;
        if (compare(&a, &b) < 2) { // 0 or 1 means a <= b
            first = a;
            second = b;
        } else {
            first = b;
            second = a;
        };

        let mut data = vector::empty<u8>();
        vector::append(&mut data, first);
        vector::append(&mut data, second);
        std::hash::sha3_256(data)
    }

    /// Returns 0 if equal, 1 if a < b, 2 if a > b
    fun compare(a: &vector<u8>, b: &vector<u8>): u8 {
        let len = vector::length(a);
        let mut i = 0;
        while (i < len) {
            let byte_a = *vector::borrow(a, i);
            let byte_b = *vector::borrow(b, i);
            if (byte_a < byte_b) return 1;
            if (byte_a > byte_b) return 2;
            i = i + 1;
        };
        0 // Equal
    }

    public(package) fun u64_to_bytes(v: u64): vector<u8> {
        use sui::bcs;
        bcs::to_bytes(&v)
    }
}
