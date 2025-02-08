module leizd::debt_coin {

    use std::string;
    use std::signer;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::coins;

    friend leizd::asset_pool;
    friend leizd::pair_pool;
    friend leizd::vault;

    struct Debt<phantom T> {
        borrowed_coin: Coin<T>
    }

    struct Capabilities<phantom T> has key {
        mint_cap: MintCapability<T>,
        burn_cap: BurnCapability<T>
    }

    public(friend) fun initialize<T>(account: &signer) {
        let coin_name = coin::name<T>();
        let coin_symbol = coin::symbol<T>();
        let coin_decimals = coin::decimals<T>();
        let prefix_name = b"Debt ";
        let prefix_symbol = b"d";
        string::insert(&mut coin_name, 0, string::utf8(prefix_name));
        string::insert(&mut coin_symbol, 0, string::utf8(prefix_symbol));        
        let (mint_cap, burn_cap) = coin::initialize<Debt<T>>(
            account,
            coin_name,
            coin_symbol,
            coin_decimals,
            true
        );
        move_to(account, Capabilities<Debt<T>> {
            mint_cap,
            burn_cap
        })
    }

    public(friend) fun mint<T>(account: &signer, amount: u64) acquires Capabilities {
        let caps = borrow_global<Capabilities<Debt<T>>>(@leizd);
        let account_addr = signer::address_of(account);
        if (!coin::is_account_registered<Debt<T>>(account_addr)) {
            coins::register<Debt<T>>(account);
        };

        let coin_minted = coin::mint(amount, &caps.mint_cap);
        coin::deposit(account_addr, coin_minted);
    }

    public(friend) fun burn<T>(account: &signer, amount: u64) acquires Capabilities {
        let caps = borrow_global<Capabilities<Debt<T>>>(@leizd);
        let coin_burned = coin::withdraw<Debt<T>>(account, amount);
        coin::burn(coin_burned, &caps.burn_cap);
    }

    public fun is_coin_initialized<T>(): bool {
        coin::is_coin_initialized<Debt<T>>()
    }

    public fun balance<T>(owner: address): u64 {
        coin::balance<Debt<T>>(owner)
    }
}