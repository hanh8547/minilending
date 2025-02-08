#[test_only]
module leizd::integration {

    #[test_only]
    struct USDC {}
    struct WETH {}
    struct UNI {}

    #[test_only]
    use aptos_std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use leizd::asset_pool;
    use leizd::vault;
    use leizd::zusd;
    use leizd::pair_pool;
    use leizd::collateral_coin;
    use leizd::debt_coin;

    #[test(owner=@leizd)]
    public entry fun test_init_by_owner(owner: signer) {

        // init coins
        account::create_account(signer::address_of(&owner));
        init_usdc(&owner);
        init_weth(&owner);

        // list coins
        asset_pool::list_new_coin<USDC>(&owner);
        asset_pool::list_new_coin<WETH>(&owner);

        assert!(asset_pool::balance<USDC>() == 0, 0);
        assert!(asset_pool::balance<WETH>() == 0, 0);
    }

    #[test(owner=@leizd, account1=@0x11, aptos_framework=@aptos_framework)]
    public entry fun test_deposit_asset(owner: signer, account1: signer, aptos_framework: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_usdc(&owner);
        asset_pool::list_new_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);
        assert!(coin::balance<USDC>(account1_addr) == 100, 0);

        asset_pool::deposit<USDC>(&account1, 10);
        assert!(coin::balance<USDC>(account1_addr) == 90, 0);
        assert!(asset_pool::balance<USDC>() == 10, 0);
        assert!(collateral_coin::balance<USDC>(account1_addr) == 10, 0);
    }

    #[test(owner=@leizd, account1=@0x11)]
    public entry fun test_deposit_to_vault(owner: signer, account1: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));

        init_usdc(&owner);

        // init bridge coin
        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);

        vault::deposit<USDC>(&account1, 10);
        assert!(coin::balance<USDC>(account1_addr) == 90, 0);
        assert!(vault::balance<USDC>() == 10, 0);
        assert!(vault::collateral_of<USDC>(account1_addr) == 10, 0);
    }

    #[test(owner=@leizd, account1=@0x11)]
    public entry fun test_borrow_zusd(owner: signer, account1: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));

        init_usdc(&owner);

        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 10000);

        vault::deposit<USDC>(&account1, 1000);
        vault::borrow_zusd<USDC>(&account1, 1000);
        assert!(zusd::balance(account1_addr) == 1000, 0);
        assert!(vault::collateral_of<USDC>(account1_addr) == 1000, 0);
        assert!(vault::debt_zusd_of<USDC>(account1_addr) == 1008, 0);
    }

    #[test(owner=@leizd, account1=@0x11)]
    public entry fun test_withdraw_from_vault(owner: signer, account1: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));

        init_usdc(&owner);

        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);
        vault::deposit<USDC>(&account1, 10);

        vault::withdraw<USDC>(&account1, 9);
        assert!(coin::balance<USDC>(account1_addr) == 99, 0);
        assert!(vault::balance<USDC>() == 1, 0);
        assert!(vault::collateral_of<USDC>(account1_addr) == 1, 0);
    }

    #[test(owner=@leizd, account1=@0x11, account2=@0x2, aptos_framework=@aptos_framework)]
    public entry fun test_deposit_bridge_coin(owner: signer, account1: signer, account2: signer, aptos_framework: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        account::create_account(signer::address_of(&account2));
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_usdc(&owner);
        init_uni(&owner);
        asset_pool::list_new_coin<USDC>(&owner);
        asset_pool::list_new_coin<UNI>(&owner);
        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        let account2_addr = signer::address_of(&account2);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);
        managed_coin::register<UNI>(&account2);
        managed_coin::mint<UNI>(&owner, account2_addr, 100);

        asset_pool::deposit<UNI>(&account2, 10);
        vault::deposit<USDC>(&account1, 30);
        vault::borrow_zusd<USDC>(&account1, 30);

        pair_pool::deposit<USDC>(&account1, 10);
        assert!(pair_pool::balance<USDC>() == 10, 0);
        assert!(pair_pool::balance<UNI>() == 0, 0);
        assert!(zusd::balance(account1_addr) == 20, 0);
    }

    #[test(owner=@leizd, account1=@0x11, account2=@0x2, aptos_framework=@aptos_framework)]
    public entry fun test_withdraw_bridge_coin(owner: signer, account1: signer, account2: signer, aptos_framework: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        account::create_account(signer::address_of(&account2));
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_usdc(&owner);
        init_uni(&owner);
        asset_pool::list_new_coin<USDC>(&owner);
        asset_pool::list_new_coin<UNI>(&owner);
        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        let account2_addr = signer::address_of(&account2);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);
        managed_coin::register<UNI>(&account2);
        managed_coin::mint<UNI>(&owner, account2_addr, 100);

        asset_pool::deposit<UNI>(&account2, 10);
        vault::deposit<USDC>(&account1, 30);
        vault::borrow_zusd<USDC>(&account1, 30);
        pair_pool::deposit<USDC>(&account1, 10);

        pair_pool::withdraw<USDC>(&account1, 10);
        assert!(pair_pool::balance<USDC>() == 0, 0);
    }

    #[test(owner=@leizd, account1=@0x11, account2=@0x2, aptos_framework=@aptos_framework)]
    public entry fun test_borrow_uni_by_weth(owner: signer, account1: signer, account2: signer, aptos_framework: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        account::create_account(signer::address_of(&account2));
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_usdc(&owner);
        init_uni(&owner);
        init_weth(&owner);
        asset_pool::list_new_coin<USDC>(&owner);
        asset_pool::list_new_coin<UNI>(&owner);
        asset_pool::list_new_coin<WETH>(&owner);
        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        let account2_addr = signer::address_of(&account2);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);
        managed_coin::register<WETH>(&account1);
        managed_coin::mint<WETH>(&owner, account1_addr, 100);
        managed_coin::register<UNI>(&account2);
        managed_coin::mint<UNI>(&owner, account2_addr, 100);
        managed_coin::register<WETH>(&account2);
        managed_coin::mint<WETH>(&owner, account2_addr, 100);
        managed_coin::register<zusd::ZUSD>(&account1);
        managed_coin::register<zusd::ZUSD>(&account2);

        asset_pool::deposit<UNI>(&account2, 50);
        asset_pool::deposit<WETH>(&account1, 50);
        vault::deposit<USDC>(&account1, 80);
        vault::borrow_zusd<USDC>(&account1, 80);
        pair_pool::deposit<UNI>(&account1, 30);
        pair_pool::deposit<WETH>(&account1, 30);

        // WETH -> UNI
        asset_pool::borrow<UNI,WETH>(&account2, 10);
        assert!(coin::balance<WETH>(account2_addr) == 110, 0);
        assert!(debt_coin::balance<WETH>(account2_addr) == 10, 0);
    }

    #[test(owner=@leizd, account1=@0x11, account2=@0x2, aptos_framework=@aptos_framework)]
    public entry fun test_repay_uni_for_weth(owner: signer, account1: signer, account2: signer, aptos_framework: signer) {
        account::create_account(signer::address_of(&owner));
        account::create_account(signer::address_of(&account1));
        account::create_account(signer::address_of(&account2));
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_usdc(&owner);
        init_uni(&owner);
        init_weth(&owner);
        asset_pool::list_new_coin<USDC>(&owner);
        asset_pool::list_new_coin<UNI>(&owner);
        asset_pool::list_new_coin<WETH>(&owner);
        vault::initialize(&owner);
        vault::activate_coin<USDC>(&owner);

        let account1_addr = signer::address_of(&account1);
        let account2_addr = signer::address_of(&account2);
        managed_coin::register<USDC>(&account1);
        managed_coin::mint<USDC>(&owner, account1_addr, 100);
        managed_coin::register<WETH>(&account1);
        managed_coin::mint<WETH>(&owner, account1_addr, 100);
        managed_coin::register<UNI>(&account2);
        managed_coin::mint<UNI>(&owner, account2_addr, 100);
        managed_coin::register<WETH>(&account2);
        managed_coin::mint<WETH>(&owner, account2_addr, 100);
        managed_coin::register<zusd::ZUSD>(&account1);
        managed_coin::register<zusd::ZUSD>(&account2);

        asset_pool::deposit<UNI>(&account2, 50);
        asset_pool::deposit<WETH>(&account1, 50);
        vault::deposit<USDC>(&account1, 80);
        vault::borrow_zusd<USDC>(&account1, 80);
        pair_pool::deposit<UNI>(&account1, 30);
        pair_pool::deposit<WETH>(&account1, 30);
        asset_pool::borrow<UNI,WETH>(&account2, 10);

        asset_pool::repay<UNI,WETH>(&account2, 10);
        assert!(coin::balance<WETH>(account2_addr) == 100, 0);
        assert!(debt_coin::balance<WETH>(account2_addr) == 0, 0);
    }

    fun init_usdc(account: &signer) {
        init_coin<USDC>(account, b"USDC", 6);
    }

    fun init_weth(account: &signer) {
        init_coin<WETH>(account, b"WETH", 18);
    }

    fun init_uni(account: &signer) {
        init_coin<UNI>(account, b"UNI", 18);
    }


    fun init_coin<T>(account: &signer, name: vector<u8>, decimals: u64) {
        managed_coin::initialize<T>(
            account,
            name,
            name,
            decimals,
            true
        );
        assert!(coin::is_coin_initialized<T>(), 0);
        managed_coin::register<T>(account);
    }
}