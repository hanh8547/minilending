module leizd::vault {

    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::simple_map;
    use leizd::zusd;
    use leizd::collateral_coin;
    use leizd::debt_coin;

    const ENOT_PERMITED_COIN: u64 = 0;
    const EALREADY_INITIALIZED: u64 = 1;
    const EZERO_AMOUNT: u64 = 2;
    const ENOT_ENOUGH: u64 = 3;
    const EDISABLED_COIN: u64 = 4;

    const DECIMAL_PRECISION: u64 = 1000000000000000000;
    const BORROWING_FEE_FLOOR: u64 = 1000000000000000000 * 8 / 1000; // 0.8%
    
    struct Vault<phantom T> has key {
        coin: coin::Coin<T>,
        balance: simple_map::SimpleMap<address,Balance<T>>,
        active: bool
    }

    struct Balance<phantom T> has store {
        collateral: u64,
        zusd_debt: u64,
    }

    public entry fun initialize(owner: &signer) {
        zusd::initialize(owner);
        collateral_coin::initialize<zusd::ZUSD>(owner);
        debt_coin::initialize<zusd::ZUSD>(owner);
    }

    public entry fun activate_coin<T>(owner: &signer) {
        assert!(!exists<Vault<T>>(@leizd), EALREADY_INITIALIZED);
        move_to(owner, Vault<T> { 
            coin: coin::zero<T>(), 
            balance: simple_map::create<address,Balance<T>>(),
            active: true 
        });
    }

    public entry fun disable_coin<T>(owner: &signer) acquires Vault {
        let owner_addr = signer::address_of(owner);
        let active = &mut borrow_global_mut<Vault<T>>(owner_addr).active;
        *active = false;
    }

    public entry fun deposit<T>(account: &signer, amount: u64) acquires Vault {
        assert!(exists<Vault<T>>(@leizd), ENOT_PERMITED_COIN);
        let pool = borrow_global_mut<Vault<T>>(@leizd);
        assert!(pool.active, EDISABLED_COIN);

        let account_addr = signer::address_of(account);
        if (simple_map::contains_key<address,Balance<T>>(&mut pool.balance, &account_addr)) {
            let balance = simple_map::borrow_mut<address,Balance<T>>(&mut pool.balance, &account_addr);
            balance.collateral = balance.collateral + amount;
        } else {
            simple_map::add<address,Balance<T>>(&mut pool.balance, account_addr, Balance {
                collateral: amount,
                zusd_debt: 0
            });
        };
        let withdrawed = coin::withdraw<T>(account, amount);
        coin::merge(&mut pool.coin, withdrawed);        
    }

    public entry fun withdraw<T>(account: &signer, amount: u64) acquires Vault {
        assert!(exists<Vault<T>>(@leizd), ENOT_PERMITED_COIN);
        assert!(amount > 0, EZERO_AMOUNT);

        let account_addr = signer::address_of(account);
        let pool_ref = borrow_global_mut<Vault<T>>(@leizd);
        assert!(coin::value<T>(&pool_ref.coin) >= amount, ENOT_ENOUGH);

        let deposited = coin::extract(&mut pool_ref.coin, amount);
        coin::deposit<T>(account_addr, deposited);

        assert!(simple_map::contains_key<address,Balance<T>>(&mut pool_ref.balance, &account_addr), ENOT_PERMITED_COIN);
        let balance = simple_map::borrow_mut<address,Balance<T>>(&mut pool_ref.balance, &account_addr);
        balance.collateral = balance.collateral - amount;
    }

    public entry fun borrow_zusd<T>(account: &signer, amount: u64) acquires Vault {
        let account_addr = signer::address_of(account);
        let pool_ref = borrow_global_mut<Vault<T>>(@leizd);
        assert!(simple_map::contains_key<address,Balance<T>>(&mut pool_ref.balance, &account_addr), 0);
        
        let balance = simple_map::borrow_mut<address,Balance<T>>(&mut pool_ref.balance, &account_addr);
        let zusd_fee = borrowing_fee(amount);
        balance.zusd_debt = balance.zusd_debt + amount + zusd_fee;

        zusd::mint(account, amount);
    }

    public entry fun repay_zusd<T>(account: &signer, amount: u64) acquires Vault {
        let account_addr = signer::address_of(account);
        let pool_ref = borrow_global_mut<Vault<T>>(@leizd);
        assert!(simple_map::contains_key<address,Balance<T>>(&mut pool_ref.balance, &account_addr), 0);

        let balance = simple_map::borrow_mut<address,Balance<T>>(&mut pool_ref.balance, &account_addr);
        balance.zusd_debt = balance.zusd_debt - amount;
        zusd::burn(account, amount);
    }

    fun borrowing_rate(): u64 {
        BORROWING_FEE_FLOOR
    }

    public fun borrowing_fee(amount: u64): u64 {
        amount * borrowing_rate() / DECIMAL_PRECISION
    }

    public fun balance<T>(): u64 acquires Vault {
        let coin = &borrow_global<Vault<T>>(@leizd).coin;
        coin::value(coin)
    }

    public fun collateral_of<T>(account_addr: address):u64 acquires Vault {
        let balance = &borrow_global<Vault<T>>(@leizd).balance;
        simple_map::borrow<address,Balance<T>>(balance, &account_addr).collateral
    }

    public fun debt_zusd_of<T>(account_addr: address):u64 acquires Vault {
        let balance = &borrow_global<Vault<T>>(@leizd).balance;
        simple_map::borrow<address,Balance<T>>(balance, &account_addr).zusd_debt
    }
}