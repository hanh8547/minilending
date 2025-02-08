module leizd::treasury {
    
    friend leizd::asset_pool;

    struct Treasury has key {

    }

    public(friend) entry fun initialize<T>(owner: &signer) {
        move_to(owner, Treasury {});
    }
}