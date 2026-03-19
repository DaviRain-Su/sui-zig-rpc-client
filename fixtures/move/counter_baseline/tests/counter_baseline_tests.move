#[test_only]
module counter_baseline::counter_baseline_tests;

use counter_baseline::counter_baseline::Counter;

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

#[test]
fun counter_baseline_preview_preserves_pure_value_order() {
    let config = counter_baseline::counter_baseline::new_config(ALICE, 7, true);
    let request = counter_baseline::counter_baseline::new_request(5, false, BOB);
    let (receipt, by, enabled_before, owner) = counter_baseline::counter_baseline::preview(
        config,
        request,
        BOB,
        false,
    );

    assert!(counter_baseline::counter_baseline::receipt_before(&receipt) == 7, 0);
    assert!(counter_baseline::counter_baseline::receipt_after(&receipt) == 12, 1);
    assert!(!counter_baseline::counter_baseline::receipt_enabled(&receipt), 2);
    assert!(counter_baseline::counter_baseline::receipt_owner(&receipt) == ALICE, 3);
    assert!(counter_baseline::counter_baseline::receipt_actor(&receipt) == BOB, 4);
    assert!(!counter_baseline::counter_baseline::receipt_actor_is_owner(&receipt), 5);
    assert!(counter_baseline::counter_baseline::receipt_actor_matches_sender(&receipt), 6);
    assert!(by == 5, 7);
    assert!(enabled_before, 8);
    assert!(owner == ALICE, 9);
}

#[test]
fun counter_baseline_create_and_apply_track_sender_context() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _counter_id = counter_baseline::counter_baseline::create_counter(
        counter_baseline::counter_baseline::new_config(BOB, 11, true),
        sui::test_scenario::ctx(&mut scenario),
    );

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut counter = sui::test_scenario::take_from_sender<Counter>(&scenario);
    assert!(counter_baseline::counter_baseline::value(&counter) == 11, 0);
    assert!(counter_baseline::counter_baseline::enabled(&counter), 1);
    assert!(counter_baseline::counter_baseline::owner(&counter) == BOB, 2);
    assert!(counter_baseline::counter_baseline::creator(&counter) == ALICE, 3);
    assert!(counter_baseline::counter_baseline::last_actor(&counter) == ALICE, 4);

    let receipt = counter_baseline::counter_baseline::apply(
        &mut counter,
        counter_baseline::counter_baseline::new_request(9, true, ALICE),
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(counter_baseline::counter_baseline::receipt_before(&receipt) == 11, 5);
    assert!(counter_baseline::counter_baseline::receipt_after(&receipt) == 20, 6);
    assert!(counter_baseline::counter_baseline::receipt_enabled(&receipt), 7);
    assert!(!counter_baseline::counter_baseline::receipt_actor_is_owner(&receipt), 8);
    assert!(counter_baseline::counter_baseline::receipt_actor_matches_sender(&receipt), 9);
    assert!(counter_baseline::counter_baseline::value(&counter) == 20, 10);
    assert!(counter_baseline::counter_baseline::last_actor(&counter) == ALICE, 11);
    sui::test_scenario::return_to_sender(&scenario, counter);

    sui::test_scenario::end(scenario);
}

#[test]
fun counter_baseline_entry_paths_and_sender_probe_work() {
    let mut scenario = sui::test_scenario::begin(BOB);
    counter_baseline::counter_baseline::create_counter_entry(
        counter_baseline::counter_baseline::new_config(BOB, 3, true),
        sui::test_scenario::ctx(&mut scenario),
    );

    sui::test_scenario::next_tx(&mut scenario, BOB);
    let mut counter = sui::test_scenario::take_from_sender<Counter>(&scenario);
    let (matches_sender, sender, amount, enabled) = counter_baseline::counter_baseline::sender_probe(
        BOB,
        13,
        true,
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(matches_sender, 0);
    assert!(sender == BOB, 1);
    assert!(amount == 13, 2);
    assert!(enabled, 3);

    counter_baseline::counter_baseline::apply_entry(
        &mut counter,
        counter_baseline::counter_baseline::new_request(4, false, BOB),
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(counter_baseline::counter_baseline::value(&counter) == 7, 4);
    assert!(!counter_baseline::counter_baseline::enabled(&counter), 5);
    assert!(counter_baseline::counter_baseline::owner(&counter) == BOB, 6);
    assert!(counter_baseline::counter_baseline::creator(&counter) == BOB, 7);
    assert!(counter_baseline::counter_baseline::last_actor(&counter) == BOB, 8);
    sui::test_scenario::return_to_sender(&scenario, counter);

    sui::test_scenario::end(scenario);
}
