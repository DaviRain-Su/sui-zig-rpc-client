module counter_baseline::counter_baseline;

const EDISABLED: u64 = 0;

public struct Counter has key, store {
    id: sui::object::UID,
    value: u64,
    enabled: bool,
    owner: address,
    creator: address,
    last_actor: address,
}

public struct CounterConfig has copy, drop, store {
    owner: address,
    start: u64,
    enabled: bool,
}

public struct IncrementRequest has copy, drop, store {
    by: u64,
    keep_enabled: bool,
    actor: address,
}

public struct CounterReceipt has copy, drop, store {
    before: u64,
    after: u64,
    enabled: bool,
    owner: address,
    actor: address,
    actor_is_owner: bool,
    actor_matches_sender: bool,
}

public fun new_config(owner: address, start: u64, enabled: bool): CounterConfig {
    CounterConfig {
        owner,
        start,
        enabled,
    }
}

public fun new_request(by: u64, keep_enabled: bool, actor: address): IncrementRequest {
    IncrementRequest {
        by,
        keep_enabled,
        actor,
    }
}

public fun preview(
    config: CounterConfig,
    request: IncrementRequest,
    expected_sender: address,
    invert_enabled: bool,
): (CounterReceipt, u64, bool, address) {
    let enabled = if (invert_enabled) !config.enabled else config.enabled;
    let before = config.start;
    let after = if (enabled) before + request.by else before;
    (
        CounterReceipt {
            before,
            after,
            enabled: enabled && request.keep_enabled,
            owner: config.owner,
            actor: request.actor,
            actor_is_owner: request.actor == config.owner,
            actor_matches_sender: request.actor == expected_sender,
        },
        request.by,
        enabled,
        config.owner,
    )
}

public fun sender_probe(
    expected_sender: address,
    amount: u64,
    enabled: bool,
    ctx: &sui::tx_context::TxContext,
): (bool, address, u64, bool) {
    let sender = sui::tx_context::sender(ctx);
    (sender == expected_sender, sender, amount, enabled)
}

#[allow(lint(self_transfer))]
public fun create_counter(
    config: CounterConfig,
    ctx: &mut sui::tx_context::TxContext,
): sui::object::ID {
    let sender = sui::tx_context::sender(ctx);
    let counter = Counter {
        id: sui::object::new(ctx),
        value: config.start,
        enabled: config.enabled,
        owner: config.owner,
        creator: sender,
        last_actor: sender,
    };
    let counter_id = sui::object::id(&counter);
    sui::transfer::public_transfer(counter, sender);
    counter_id
}

#[allow(lint(public_entry))]
public entry fun create_counter_entry(
    config: CounterConfig,
    ctx: &mut sui::tx_context::TxContext,
) {
    let _ = create_counter(config, ctx);
}

public fun apply(
    counter: &mut Counter,
    request: IncrementRequest,
    ctx: &sui::tx_context::TxContext,
): CounterReceipt {
    assert!(counter.enabled, EDISABLED);

    let before = counter.value;
    counter.value = before + request.by;
    counter.enabled = counter.enabled && request.keep_enabled;
    counter.last_actor = request.actor;

    CounterReceipt {
        before,
        after: counter.value,
        enabled: counter.enabled,
        owner: counter.owner,
        actor: request.actor,
        actor_is_owner: request.actor == counter.owner,
        actor_matches_sender: request.actor == sui::tx_context::sender(ctx),
    }
}

#[allow(lint(public_entry))]
public entry fun apply_entry(
    counter: &mut Counter,
    request: IncrementRequest,
    ctx: &sui::tx_context::TxContext,
) {
    let _ = apply(counter, request, ctx);
}

public fun value(counter: &Counter): u64 {
    counter.value
}

public fun enabled(counter: &Counter): bool {
    counter.enabled
}

public fun owner(counter: &Counter): address {
    counter.owner
}

public fun creator(counter: &Counter): address {
    counter.creator
}

public fun last_actor(counter: &Counter): address {
    counter.last_actor
}

public fun receipt_before(receipt: &CounterReceipt): u64 {
    receipt.before
}

public fun receipt_after(receipt: &CounterReceipt): u64 {
    receipt.after
}

public fun receipt_enabled(receipt: &CounterReceipt): bool {
    receipt.enabled
}

public fun receipt_owner(receipt: &CounterReceipt): address {
    receipt.owner
}

public fun receipt_actor(receipt: &CounterReceipt): address {
    receipt.actor
}

public fun receipt_actor_is_owner(receipt: &CounterReceipt): bool {
    receipt.actor_is_owner
}

public fun receipt_actor_matches_sender(receipt: &CounterReceipt): bool {
    receipt.actor_matches_sender
}
