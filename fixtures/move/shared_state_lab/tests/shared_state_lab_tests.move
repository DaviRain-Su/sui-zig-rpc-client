#[test_only]
module shared_state_lab::shared_state_lab_tests;

use shared_state_lab::shared_state_lab::{AdminCap, SharedCounter};

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

fun setup_counter(
    scenario: &mut sui::test_scenario::Scenario,
    initial_value: u64,
): sui::object::ID {
    let cap = shared_state_lab::shared_state_lab::mint_admin_cap(sui::test_scenario::ctx(scenario));
    sui::transfer::public_transfer(cap, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let counter_id = shared_state_lab::shared_state_lab::create(
        &cap,
        initial_value,
        sui::test_scenario::ctx(scenario),
    );
    sui::test_scenario::return_to_sender(scenario, cap);
    counter_id
}

#[test]
fun shared_counter_supports_shared_mutation_across_transactions() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let counter_id = setup_counter(&mut scenario, 7);

    sui::test_scenario::next_tx(&mut scenario, BOB);
    let mut counter = sui::test_scenario::take_shared_by_id<SharedCounter>(&scenario, counter_id);
    let receipt = shared_state_lab::shared_state_lab::increment(&mut counter, 5);
    assert!(shared_state_lab::shared_state_lab::receipt_counter_id(&receipt) == counter_id, 0);
    assert!(shared_state_lab::shared_state_lab::receipt_before(&receipt) == 7, 1);
    assert!(shared_state_lab::shared_state_lab::receipt_after(&receipt) == 12, 2);
    assert!(shared_state_lab::shared_state_lab::receipt_version(&receipt) == 1, 3);
    sui::test_scenario::return_shared(counter);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let counter = sui::test_scenario::take_shared_by_id<SharedCounter>(&scenario, counter_id);
    assert!(shared_state_lab::shared_state_lab::value(&counter) == 12, 4);
    assert!(shared_state_lab::shared_state_lab::version(&counter) == 1, 5);
    assert!(shared_state_lab::shared_state_lab::is_enabled(&counter), 6);
    sui::test_scenario::return_shared(counter);

    sui::test_scenario::end(scenario);
}

#[test]
fun admin_cap_controls_enabled_state_and_version_migration() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let counter_id = setup_counter(&mut scenario, 3);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let mut counter = sui::test_scenario::take_shared_by_id<SharedCounter>(&scenario, counter_id);
    shared_state_lab::shared_state_lab::set_enabled(&cap, &mut counter, false);
    shared_state_lab::shared_state_lab::migrate(&cap, &mut counter, 1);
    assert!(!shared_state_lab::shared_state_lab::is_enabled(&counter), 7);
    assert!(shared_state_lab::shared_state_lab::version(&counter) == 2, 8);
    sui::test_scenario::return_shared(counter);
    sui::test_scenario::return_to_sender(&scenario, cap);

    sui::test_scenario::end(scenario);
}
