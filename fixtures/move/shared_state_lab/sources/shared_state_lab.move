module shared_state_lab::shared_state_lab;

const EDISABLED: u64 = 0;
const EWRONG_VERSION: u64 = 1;

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct SharedCounter has key, store {
    id: sui::object::UID,
    version: u64,
    value: u64,
    enabled: bool,
}

public struct IncrementReceipt has copy, drop, store {
    counter_id: sui::object::ID,
    before: u64,
    after: u64,
    version: u64,
}

public struct CounterUpdated has copy, drop {
    counter_id: sui::object::ID,
    before: u64,
    after: u64,
    version: u64,
    enabled: bool,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

public fun create(
    _cap: &AdminCap,
    initial_value: u64,
    ctx: &mut sui::tx_context::TxContext,
): sui::object::ID {
    let counter = SharedCounter {
        id: sui::object::new(ctx),
        version: 1,
        value: initial_value,
        enabled: true,
    };
    let counter_id = sui::object::id(&counter);
    sui::transfer::share_object(counter);
    counter_id
}

public fun increment(counter: &mut SharedCounter, by: u64): IncrementReceipt {
    assert!(counter.enabled, EDISABLED);

    let before = counter.value;
    counter.value = before + by;

    let receipt = IncrementReceipt {
        counter_id: sui::object::id(counter),
        before,
        after: counter.value,
        version: counter.version,
    };
    emit_update_event(counter, before);
    receipt
}

public fun set_enabled(_cap: &AdminCap, counter: &mut SharedCounter, enabled: bool) {
    let before = counter.value;
    counter.enabled = enabled;
    emit_update_event(counter, before);
}

public fun migrate(_cap: &AdminCap, counter: &mut SharedCounter, expected_version: u64) {
    assert!(counter.version == expected_version, EWRONG_VERSION);
    let before = counter.value;
    counter.version = expected_version + 1;
    emit_update_event(counter, before);
}

public fun value(counter: &SharedCounter): u64 {
    counter.value
}

public fun version(counter: &SharedCounter): u64 {
    counter.version
}

public fun is_enabled(counter: &SharedCounter): bool {
    counter.enabled
}

public fun receipt_before(receipt: &IncrementReceipt): u64 {
    receipt.before
}

public fun receipt_after(receipt: &IncrementReceipt): u64 {
    receipt.after
}

public fun receipt_version(receipt: &IncrementReceipt): u64 {
    receipt.version
}

public fun receipt_counter_id(receipt: &IncrementReceipt): sui::object::ID {
    receipt.counter_id
}

fun emit_update_event(counter: &SharedCounter, before: u64) {
    sui::event::emit(CounterUpdated {
        counter_id: sui::object::id(counter),
        before,
        after: counter.value,
        version: counter.version,
        enabled: counter.enabled,
    });
}
