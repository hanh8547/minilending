module leizd::interest_rate_model {

    const DECIMAL_PRECISION: u64 = 1000000000000000000;

    struct State<phantom T> has key {
        optimal_utilization: u64,
        threshold_large: u64,
        threshold_low: u64,
        integrator_gain: u64,
        // TODO
    }

    public entry fun initialize<T>(owner: &signer) {
        move_to(owner, State<T> {
            optimal_utilization: 0,
            threshold_large: 0,
            threshold_low: 0,
            integrator_gain: 0
        });
    }

    public fun interest_rate<T>(timestamp: u64): u64 {
        // TODO
        1 * DECIMAL_PRECISION + timestamp - timestamp
    }

    public fun update<T>() {
        // TODO
    }
}