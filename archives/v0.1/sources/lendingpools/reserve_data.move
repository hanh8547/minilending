module leizd::reserve_data {

    use std::signer;

    struct ReserveData<phantom T> has key {
        ltv: u64,
        liquidation_threshold: u64,
        liquidation_bonus: u64,
        reserve_factor: u64,
        is_active: bool,
    }

    public entry fun initialize<T>(owner: &signer) {
        move_to(owner, default_reserve_data<T>());
    }

    public entry fun set_ltv<T>(owner: &signer, ltv: u64) acquires ReserveData {
        let owner_addr = signer::address_of(owner);
        let ltv_ref = &mut borrow_global_mut<ReserveData<T>>(owner_addr).ltv;
        *ltv_ref = ltv;
    }

    public fun ltv<T>(): u64 acquires ReserveData {
        borrow_global<ReserveData<T>>(@leizd).ltv
    }

    public fun reserve_factor<T>(): u64 acquires ReserveData {
        borrow_global<ReserveData<T>>(@leizd).reserve_factor
    }

    public fun is_active<T>(): bool acquires ReserveData {
        borrow_global<ReserveData<T>>(@leizd).is_active
    }

    public fun default_reserve_data<T>(): ReserveData<T> {
        ReserveData<T> {
            ltv: 90,
            liquidation_threshold: 85,
            liquidation_bonus: 10,
            reserve_factor: 20,
            is_active: true
        }
    }
}