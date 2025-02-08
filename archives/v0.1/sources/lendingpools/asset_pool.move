module leizd::asset_pool {

    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::simple_map;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use leizd::collateral_coin;
    use leizd::debt_coin;
    use leizd::price_oracle;
    use leizd::pair_pool;
    use leizd::reserve_data;
    use leizd::interest_rate_model;

    const EZERO_AMOUNT: u64 = 0;
    const ENOT_INITIALIZED: u64 = 1;
    const EALREADY_LISTED: u64 = 2;
    const ENOT_ENOUGH: u64 = 3;
    const ENOT_POOL_IS_INACTIVE: u64 = 4;

    const DECIMAL_PRECISION: u64 = 1000000000000000000;


    struct Pool<phantom T> has key {
        coin: coin::Coin<T>,
        balance: simple_map::SimpleMap<address,Balance<T>>,
        total_deposited: u64,
        total_borrowed: u64,
        active: bool
    }

    struct Balance<phantom T> has store {
        collateral: u64,
        debt: u64
    }

    struct State<phantom T> has key {
        last_timestamp: u64,
        protocol_fees: u64
    }

    public entry fun list_new_coin<T>(owner: &signer) {
        assert!(coin::is_coin_initialized<T>(), ENOT_INITIALIZED);
        assert!(!collateral_coin::is_coin_initialized<T>(), EALREADY_LISTED);
        assert!(!debt_coin::is_coin_initialized<T>(), EALREADY_LISTED);
        
        collateral_coin::initialize<T>(owner);
        debt_coin::initialize<T>(owner);
        pair_pool::initialize<T>(owner);
        reserve_data::initialize<T>(owner);
        interest_rate_model::initialize<T>(owner);
        move_to(owner, Pool<T> {
            coin: coin::zero<T>(), 
            balance: simple_map::create<address,Balance<T>>(),
            total_deposited: 0,
            total_borrowed: 0,
            active: true
        });
        move_to(owner, State<T> {
            last_timestamp: 0,
            protocol_fees: 0
        });
    }

    public entry fun deposit<T>(account: &signer, amount: u64) acquires Pool, State {
        assert!(amount > 0, EZERO_AMOUNT);
        assert!(reserve_data::is_active<T>(), ENOT_POOL_IS_INACTIVE);

        accrue_interest<T>();

        let pool_ref = borrow_global_mut<Pool<T>>(@leizd);

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

        let withdrawed = coin::withdraw<T>(account, amount);
        coin::merge(&mut pool_ref.coin, withdrawed);
    
        collateral_coin::mint<T>(account, amount);
    }

    public fun withdraw<T>(account: &signer, amount: u64) acquires Pool {
        assert!(amount > 0, EZERO_AMOUNT);

        let account_addr = signer::address_of(account);
        let pool_ref = borrow_global_mut<Pool<T>>(@leizd);
        assert!(coin::value<T>(&pool_ref.coin) >= amount, ENOT_ENOUGH);

        let deposited = coin::extract(&mut pool_ref.coin, amount);
        coin::deposit<T>(account_addr, deposited);

        collateral_coin::burn<T>(account, amount);
    }

    public fun borrow<C,D>(account: &signer, amount: u64) acquires Pool, State {
        
        accrue_interest<D>();

        let account_addr = signer::address_of(account);
        validate_borrow<C,D>(account_addr, amount);

        // borrow bridge coin
        pair_pool::borrow<C>(account, amount);

        // deposit bridge coin
        pair_pool::deposit<D>(account, amount);

        let pool_ref = borrow_global_mut<Pool<D>>(@leizd);
        let deposited = coin::extract(&mut pool_ref.coin, amount);
        coin::deposit<D>(account_addr, deposited);

        debt_coin::mint<D>(account, amount);
    }

    public fun repay<C,D>(account: &signer, amount: u64) acquires Pool {

        let withdrawed = coin::withdraw<D>(account, amount);
        let coin_ref = &mut borrow_global_mut<Pool<D>>(@leizd).coin;
        coin::merge(coin_ref, withdrawed);

        pair_pool::borrow<D>(account, amount);
        pair_pool::deposit<C>(account, amount);

        debt_coin::burn<D>(account, amount);
    }

    fun accrue_interest<T>() acquires State, Pool {
        let state = borrow_global_mut<State<T>>(@leizd);
        let now = timestamp::now_microseconds();

        if (state.last_timestamp == 0) {
            state.last_timestamp = now;
            return
        };

        if (state.last_timestamp == now) {
            return
        };

        let interest = interest_rate_model::interest_rate<T>(now);
        let protocol_share_fee = 0; // TODO

        let pool = borrow_global_mut<Pool<T>>(@leizd);
        let total_borrowed_cached = pool.total_borrowed;
        let protocol_fees_cached = state.protocol_fees;

        let accrued_interest = total_borrowed_cached * interest / DECIMAL_PRECISION;
        let protocol_share = accrued_interest * protocol_share_fee / DECIMAL_PRECISION;
        let new_protocol_fees = protocol_fees_cached + protocol_share;
        let depositors_share = accrued_interest - protocol_share;

        pool.total_borrowed = total_borrowed_cached + accrued_interest;
        pool.total_deposited = pool.total_deposited + depositors_share;
        state.protocol_fees = new_protocol_fees;
        state.last_timestamp = now;
    }

    fun validate_borrow<C,D>(account_addr: address, amount: u64) acquires Pool {
        let c_pool = borrow_global<Pool<C>>(@leizd);
        let d_pool = borrow_global<Pool<C>>(@leizd);
        assert!(c_pool.active && d_pool.active, 0);
        assert!(coin::value(&d_pool.coin) >= amount, 0);

        let allowed_volume = collateral_volume<C>(account_addr, c_pool) * reserve_data::ltv<C>();
        assert!(allowed_volume >= borrowing_volume<D>(amount), 0);
    }

    fun collateral_volume<T>(account_addr: address, pool: &Pool<T>): u64 {
        let price = price_oracle::asset_price<T>();
        if (simple_map::contains_key<address,Balance<T>>(&pool.balance, &account_addr)) {
            simple_map::borrow<address,Balance<T>>(&pool.balance, &account_addr).collateral * price
        } else {
            0
        }
    }

    fun borrowing_volume<T>(amount: u64): u64 {
        let price = price_oracle::asset_price<T>();
        price * amount
    }

    public fun balance<T>(): u64 acquires Pool {
        let coin = &borrow_global<Pool<T>>(@leizd).coin;
        coin::value(coin)
    }

    #[test_only]
    struct CoinA {}
    struct CoinB {}

    #[test_only]
    use aptos_framework::managed_coin;

    #[test(owner=@leizd, account1 = @0x11, aptos_framework=@aptos_framework)]
    public entry fun test_deposit_and_withdraw(owner: signer, account1: signer, aptos_framework: signer) acquires Pool, State {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        managed_coin::initialize<CoinA>(
            &owner,
            b"CoinA",
            b"AAA",
            18,
            true
        );
        assert!(coin::is_coin_initialized<CoinA>(), 0);
        managed_coin::register<CoinA>(&owner);
        managed_coin::register<CoinA>(&account1);

        managed_coin::initialize<CoinB>(
            &owner,
            b"CoinB",
            b"BBB",
            18,
            true
        );
        assert!(coin::is_coin_initialized<CoinB>(), 0);
        managed_coin::register<CoinB>(&owner);
        managed_coin::register<CoinB>(&account1);

        list_new_coin<CoinA>(&owner);
        list_new_coin<CoinB>(&owner);

        let source_addr = signer::address_of(&owner);
        let user_addr = signer::address_of(&account1);

        managed_coin::mint<CoinA>(&owner, user_addr, 100);
        assert!(coin::balance<CoinA>(user_addr) == 100, 0);
        assert!(coin::balance<CoinA>(source_addr) == 0, 0);

        managed_coin::mint<CoinB>(&owner, user_addr, 100);
        assert!(coin::balance<CoinB>(user_addr) == 100, 0);

        deposit<CoinA>(&account1, 30);
        assert!(coin::balance<CoinA>(user_addr) == 70, 0);
        assert!(collateral_coin::balance<CoinA>(user_addr) == 30, 0);
        assert!(balance<CoinA>() == 30, 0);

        deposit<CoinA>(&account1, 10);
        assert!(coin::balance<CoinA>(user_addr) == 60, 0);
        assert!(collateral_coin::balance<CoinA>(user_addr) == 40, 0);
        assert!(balance<CoinA>() == 40, 0);

        deposit<CoinB>(&account1, 70);
        assert!(coin::balance<CoinB>(user_addr) == 30, 0);
        assert!(collateral_coin::balance<CoinB>(user_addr) == 70, 0);
        assert!(balance<CoinB>() == 70, 0);

        withdraw<CoinA>(&account1, 40);
        assert!(coin::balance<CoinA>(user_addr) == 100, 0);
        assert!(collateral_coin::balance<CoinA>(user_addr) == 0, 0);
        assert!(balance<CoinA>() == 0, 0);
        assert!(balance<CoinB>() == 70, 0);
    }

    #[test(owner=@leizd, account1 = @0x11, account2 = @0x2, aptos_framework= @aptos_framework)]
    public entry fun test_borrow(owner: signer, account1: signer, account2: signer, aptos_framework: signer) acquires Pool, State {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        account::create_account(signer::address_of(&account2));
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        
        managed_coin::initialize<CoinA>(
            &owner,
            b"CoinA",
            b"AAA",
            18,
            true
        );
        assert!(coin::is_coin_initialized<CoinA>(), 0);
        managed_coin::register<CoinA>(&account1);
        managed_coin::register<CoinA>(&account2);

        managed_coin::initialize<CoinB>(
            &owner,
            b"CoinB",
            b"BBB",
            18,
            true
        );
        assert!(coin::is_coin_initialized<CoinB>(), 0);
        managed_coin::register<CoinB>(&account1);
        managed_coin::register<CoinB>(&account2);

        list_new_coin<CoinA>(&owner);
        list_new_coin<CoinB>(&owner);

        let user1_addr = signer::address_of(&account1);
        managed_coin::mint<CoinA>(&owner, user1_addr, 100);
        assert!(coin::balance<CoinA>(user1_addr) == 100, 0);
        

        let user2_addr = signer::address_of(&account2);
        managed_coin::mint<CoinB>(&owner, user2_addr, 100);
        assert!(coin::balance<CoinB>(user2_addr) == 100, 0);
        
        deposit<CoinA>(&account1, 30);
        assert!(coin::balance<CoinA>(user1_addr) == 70, 0);

        deposit<CoinB>(&account2, 50);
        assert!(coin::balance<CoinB>(user2_addr) == 50, 0);
        
        // borrow<CoinA>(&account2, 10);
        // assert!(coin::balance<CoinA>(user2_addr) == 10, 0);
        // assert!(coin::balance<CoinB>(user2_addr) == 50, 0);
    }
}