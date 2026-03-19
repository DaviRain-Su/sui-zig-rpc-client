#[test_only]
module receipt_flow_lab::receipt_flow_lab_tests;

use receipt_flow_lab::receipt_flow_lab::{AdminCap, GOLD, Reserve, SILVER};

const ALICE: address = @0xA11CE;

fun setup_reserve<T>(
    scenario: &mut sui::test_scenario::Scenario,
    seed_amount: u64,
    fee_bps: u64,
): sui::object::ID {
    let cap = receipt_flow_lab::receipt_flow_lab::mint_admin_cap(sui::test_scenario::ctx(scenario));
    sui::transfer::public_transfer(cap, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let reserve_id = receipt_flow_lab::receipt_flow_lab::create_reserve<T>(
        &cap,
        sui::balance::create_for_testing<T>(seed_amount),
        fee_bps,
        sui::test_scenario::ctx(scenario),
    );
    sui::test_scenario::return_to_sender(scenario, cap);
    reserve_id
}

#[test]
fun receipt_flow_borrow_repay_returns_change() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _reserve_id = setup_reserve<GOLD>(&mut scenario, 100, 1000);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut reserve = sui::test_scenario::take_from_sender<Reserve<GOLD>>(&scenario);
    let (mut borrowed, receipt) = receipt_flow_lab::receipt_flow_lab::borrow(
        &mut reserve,
        30,
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(receipt_flow_lab::receipt_flow_lab::receipt_reserve_id(&receipt) == sui::object::id(&reserve), 0);
    assert!(receipt_flow_lab::receipt_flow_lab::receipt_principal(&receipt) == 30, 1);
    assert!(receipt_flow_lab::receipt_flow_lab::receipt_fee_due(&receipt) == 3, 2);
    assert!(receipt_flow_lab::receipt_flow_lab::available_value(&reserve) == 70, 3);
    assert!(receipt_flow_lab::receipt_flow_lab::active_loans(&reserve) == 1, 4);

    let top_up = sui::coin::mint_for_testing<GOLD>(5, sui::test_scenario::ctx(&mut scenario));
    sui::coin::join(&mut borrowed, top_up);
    let change = receipt_flow_lab::receipt_flow_lab::repay(
        &mut reserve,
        receipt,
        borrowed,
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(sui::coin::value(&change) == 2, 5);
    assert!(receipt_flow_lab::receipt_flow_lab::available_value(&reserve) == 100, 6);
    assert!(receipt_flow_lab::receipt_flow_lab::collected_fee_value(&reserve) == 3, 7);
    assert!(receipt_flow_lab::receipt_flow_lab::active_loans(&reserve) == 0, 8);
    let change_balance = sui::coin::into_balance(change);
    assert!(sui::balance::destroy_for_testing(change_balance) == 2, 9);

    sui::test_scenario::return_to_sender(&scenario, reserve);
    sui::test_scenario::end(scenario);
}

#[test]
fun receipt_flow_admin_claims_fees_after_repay() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _reserve_id = setup_reserve<GOLD>(&mut scenario, 50, 1000);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let mut reserve = sui::test_scenario::take_from_sender<Reserve<GOLD>>(&scenario);
    let (mut borrowed, receipt) = receipt_flow_lab::receipt_flow_lab::borrow(
        &mut reserve,
        20,
        sui::test_scenario::ctx(&mut scenario),
    );
    let fee_coin = sui::coin::mint_for_testing<GOLD>(2, sui::test_scenario::ctx(&mut scenario));
    sui::coin::join(&mut borrowed, fee_coin);
    let change = receipt_flow_lab::receipt_flow_lab::repay(
        &mut reserve,
        receipt,
        borrowed,
        sui::test_scenario::ctx(&mut scenario),
    );
    sui::coin::destroy_zero(change);

    let claimed = receipt_flow_lab::receipt_flow_lab::claim_fees(
        &cap,
        &mut reserve,
        2,
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(sui::coin::value(&claimed) == 2, 0);
    assert!(receipt_flow_lab::receipt_flow_lab::collected_fee_value(&reserve) == 0, 1);
    let claimed_balance = sui::coin::into_balance(claimed);
    assert!(sui::balance::destroy_for_testing(claimed_balance) == 2, 2);

    sui::test_scenario::return_to_sender(&scenario, reserve);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}

#[test]
fun receipt_flow_specializes_multiple_types() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _reserve_id = setup_reserve<SILVER>(&mut scenario, 40, 1000);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut reserve = sui::test_scenario::take_from_sender<Reserve<SILVER>>(&scenario);
    let (mut borrowed, receipt) = receipt_flow_lab::receipt_flow_lab::borrow(
        &mut reserve,
        10,
        sui::test_scenario::ctx(&mut scenario),
    );
    let fee_coin = sui::coin::mint_for_testing<SILVER>(1, sui::test_scenario::ctx(&mut scenario));
    sui::coin::join(&mut borrowed, fee_coin);
    let change = receipt_flow_lab::receipt_flow_lab::repay(
        &mut reserve,
        receipt,
        borrowed,
        sui::test_scenario::ctx(&mut scenario),
    );
    sui::coin::destroy_zero(change);
    assert!(receipt_flow_lab::receipt_flow_lab::available_value(&reserve) == 40, 0);
    assert!(receipt_flow_lab::receipt_flow_lab::collected_fee_value(&reserve) == 1, 1);
    assert!(receipt_flow_lab::receipt_flow_lab::fee_bps(&reserve) == 1000, 2);

    sui::test_scenario::return_to_sender(&scenario, reserve);
    sui::test_scenario::end(scenario);
}
