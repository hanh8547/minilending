module leizd::pair_pool {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::simple_map;
    use leizd::zusd::{ZUSD};
    use leizd::collateral_coin;
    use leizd::debt_coin;

    friend leizd::asset_pool;

    const EZERO_AMOUNT: u64 = 0;
    const ENOT_ENOUGH: u64 = 3;

    struct PairPool<phantom T> has key {
        coin: coin::Coin<ZUSD>,
        balance: simple_map::SimpleMap<address,Balance<T>>
    }

    struct Balance<phantom T> has store {
        collateral: u64,
        debt: u64
    }

    public(friend) entry fun initialize<T>(owner: &signer) {
        move_to(owner, PairPool<T> {
            coin: coin::zero(), 
            balance: simple_map::create<address,Balance<T>>()
        });
    }

    public entry fun deposit<T>(account: &signer, amount: u64) acquires PairPool {
        assert!(amount > 0, EZERO_AMOUNT);

        let pool_ref = borrow_global_mut<PairPool<T>>(@leizd);

        let account_addr = signer::address_of(account);
        if (simple_map::contains_key<address,Balance<T>>(&mut pool_ref.balance, &account_addr)) {
            let balance = simple_map::borrow_mut<address,Balance<T>>(&mut pool_ref.balance, &account_addr);
            balance.collateral = balance.collateral + amount;
        } else {
            simple_map::add<address,Balance<T>>(&mut pool_ref.balance, account_addr, Balance {
                collateral: amount,
                debt: 0
            });
        };

        let withdrawed = coin::withdraw<ZUSD>(account, amount);
        coin::merge(&mut pool_ref.coin, withdrawed);

        collateral_coin::mint<ZUSD>(account, amount);
    }

    public entry fun withdraw<T>(account: &signer, amount: u64) acquires PairPool {
        assert!(amount > 0, EZERO_AMOUNT);

        let account_addr = signer::address_of(account);
        let pool_ref = borrow_global_mut<PairPool<T>>(@leizd);
        assert!(coin::value<ZUSD>(&pool_ref.coin) >= amount, ENOT_ENOUGH);

        let deposited = coin::extract(&mut pool_ref.coin, amount);
        coin::deposit<ZUSD>(account_addr, deposited);

        collateral_coin::burn<ZUSD>(account, amount);
    }

    public(friend) entry fun borrow<T>(account: &signer, amount: u64) acquires PairPool {

        let account_addr = signer::address_of(account);
        let pool_ref = borrow_global_mut<PairPool<T>>(@leizd);
        assert!(coin::value<ZUSD>(&pool_ref.coin) >= amount, ENOT_ENOUGH);

        let deposited = coin::extract(&mut pool_ref.coin, amount);
        coin::deposit<ZUSD>(account_addr, deposited);

        debt_coin::mint<ZUSD>(account, amount);
    }

    public(friend) entry fun repay<T>() {
        // TODO
    }

    public fun balance<T>(): u64 acquires PairPool {
        let coin = &borrow_global<PairPool<T>>(@leizd).coin;
        coin::value(coin)
    }
}