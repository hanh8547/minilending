module leizd::zusd {

    use std::string;
    use aptos_std::signer;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::coins;

    friend leizd::vault;

    struct ZUSD has key, store {}

    struct Capabilities<phantom T> has key {
        mint_cap: MintCapability<T>,
        burn_cap: BurnCapability<T>,
    }

    public(friend) fun initialize(owner: &signer) {
        let (mint_cap, burn_cap) = coin::initialize<ZUSD>(
            owner,
            string::utf8(b"ZUSD"),
            string::utf8(b"BRD"),
            18,
            true
        );
        move_to(owner, Capabilities<ZUSD> {
            mint_cap,
            burn_cap,
        });
    }

    public(friend) fun mint(dest: &signer, amount: u64) acquires Capabilities {
        let dest_addr = signer::address_of(dest);
        if (!coin::is_account_registered<ZUSD>(dest_addr)) {
            coins::register<ZUSD>(dest);
        };

        let caps = borrow_global<Capabilities<ZUSD>>(@leizd);
        let coin_minted = coin::mint(amount, &caps.mint_cap);
        coin::deposit(dest_addr, coin_minted);
    }

    public(friend) fun burn(account: &signer, amount: u64) acquires Capabilities {
        let caps = borrow_global<Capabilities<ZUSD>>(@leizd);
        let coin_burned = coin::withdraw<ZUSD>(account, amount);
        coin::burn(coin_burned, &caps.burn_cap);
    }

    public fun balance(owner: address): u64 {
        coin::balance<ZUSD>(owner)
    }
}