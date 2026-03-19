#[test_only]
module generic_vault::generic_vault_tests;

use generic_vault::generic_vault::{AdminCap, GOLD, SILVER, Vault};

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

fun setup_vault<T>(
    scenario: &mut sui::test_scenario::Scenario,
    manager: address,
    min_deposit: u64,
    withdraw_gate: option::Option<u64>,
    seed_amount: u64,
): sui::object::ID {
    let cap = generic_vault::generic_vault::mint_admin_cap(sui::test_scenario::ctx(scenario));
    sui::transfer::public_transfer(cap, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let config = generic_vault::generic_vault::new_config<T>(manager, min_deposit, withdraw_gate);
    let vault_id = generic_vault::generic_vault::create_vault<T>(
        &cap,
        config,
        sui::balance::create_for_testing<T>(seed_amount),
        sui::test_scenario::ctx(scenario),
    );
    sui::test_scenario::return_to_sender(scenario, cap);
    vault_id
}

#[test]
fun generic_vault_accepts_generic_config_and_balance_seed() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let vault_id = setup_vault<GOLD>(&mut scenario, ALICE, 10, option::some(50), 40);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let vault = sui::test_scenario::take_from_sender<Vault<GOLD>>(&scenario);
    assert!(generic_vault::generic_vault::balance_value(&vault) == 40, 0);
    assert!(generic_vault::generic_vault::manager(&vault) == ALICE, 1);
    assert!(generic_vault::generic_vault::min_deposit(&vault) == 10, 2);
    assert!(generic_vault::generic_vault::has_withdraw_gate(&vault), 3);
    assert!(generic_vault::generic_vault::withdraw_gate_value(&vault) == 50, 4);
    assert!(sui::object::id(&vault) == vault_id, 5);
    sui::test_scenario::return_to_sender(&scenario, vault);

    sui::test_scenario::end(scenario);
}

#[test]
fun generic_vault_mixes_coin_balance_and_option_paths() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _vault_id = setup_vault<GOLD>(&mut scenario, ALICE, 10, option::some(8), 25);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let mut vault = sui::test_scenario::take_from_sender<Vault<GOLD>>(&scenario);

    let coin = sui::coin::mint_for_testing<GOLD>(15, sui::test_scenario::ctx(&mut scenario));
    let receipt = generic_vault::generic_vault::deposit_coin(&mut vault, coin, option::some(40));
    assert!(generic_vault::generic_vault::receipt_vault_id(&receipt) == sui::object::id(&vault), 0);
    assert!(generic_vault::generic_vault::receipt_deposited(&receipt) == 15, 1);
    assert!(generic_vault::generic_vault::receipt_after(&receipt) == 40, 2);
    assert!(generic_vault::generic_vault::receipt_min_deposit(&receipt) == 10, 3);
    assert!(generic_vault::generic_vault::receipt_has_withdraw_gate(&receipt), 4);
    assert!(generic_vault::generic_vault::receipt_withdraw_gate_value(&receipt) == 8, 5);

    generic_vault::generic_vault::reconfigure(
        &cap,
        &mut vault,
        generic_vault::generic_vault::new_config<GOLD>(BOB, 5, option::some(12)),
    );
    let withdrawn = generic_vault::generic_vault::withdraw_coin(
        &cap,
        &mut vault,
        12,
        sui::test_scenario::ctx(&mut scenario),
    );
    assert!(sui::coin::value(&withdrawn) == 12, 6);
    assert!(generic_vault::generic_vault::balance_value(&vault) == 28, 7);
    assert!(generic_vault::generic_vault::manager(&vault) == BOB, 8);
    assert!(generic_vault::generic_vault::min_deposit(&vault) == 5, 9);
    assert!(generic_vault::generic_vault::withdraw_gate_value(&vault) == 12, 10);
    let withdrawn_balance = sui::coin::into_balance(withdrawn);
    assert!(sui::balance::destroy_for_testing(withdrawn_balance) == 12, 11);

    sui::test_scenario::return_to_sender(&scenario, vault);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}

#[test]
fun generic_vault_specializes_multiple_type_args() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _vault_id = setup_vault<SILVER>(&mut scenario, BOB, 3, option::none(), 9);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let vault = sui::test_scenario::take_from_sender<Vault<SILVER>>(&scenario);
    assert!(generic_vault::generic_vault::balance_value(&vault) == 9, 0);
    assert!(generic_vault::generic_vault::manager(&vault) == BOB, 1);
    assert!(generic_vault::generic_vault::min_deposit(&vault) == 3, 2);
    assert!(!generic_vault::generic_vault::has_withdraw_gate(&vault), 3);
    sui::test_scenario::return_to_sender(&scenario, vault);

    sui::test_scenario::end(scenario);
}
