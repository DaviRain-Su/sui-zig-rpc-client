#[test_only]
module dynamic_registry::dynamic_registry_tests;

use dynamic_registry::dynamic_registry::{AdminCap, GOLD, Registry, SILVER, ShadowAnchor};

const ALICE: address = @0xA11CE;

fun setup_registry<T>(
    scenario: &mut sui::test_scenario::Scenario,
    shadow_kind: u64,
    featured_slot: u64,
): sui::object::ID {
    let cap = dynamic_registry::dynamic_registry::mint_admin_cap(sui::test_scenario::ctx(scenario));
    let shadow = dynamic_registry::dynamic_registry::mint_shadow_anchor(
        shadow_kind,
        sui::test_scenario::ctx(scenario),
    );
    sui::transfer::public_transfer(cap, ALICE);
    sui::transfer::public_transfer(shadow, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let shadow = sui::test_scenario::take_from_sender<ShadowAnchor>(scenario);
    let registry_id = dynamic_registry::dynamic_registry::create_registry<T>(
        &cap,
        &shadow,
        featured_slot,
        sui::test_scenario::ctx(scenario),
    );
    sui::test_scenario::return_to_sender(scenario, shadow);
    sui::test_scenario::return_to_sender(scenario, cap);
    registry_id
}

#[test]
fun dynamic_registry_combines_content_anchor_and_dynamic_entries() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _registry_id = setup_registry<GOLD>(&mut scenario, 42, 7);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let shadow = sui::test_scenario::take_from_sender<ShadowAnchor>(&scenario);
    let mut registry = sui::test_scenario::take_from_sender<Registry<GOLD>>(&scenario);

    let entry_a = dynamic_registry::dynamic_registry::mint_entry<GOLD>(
        11,
        b"featured",
        sui::test_scenario::ctx(&mut scenario),
    );
    let entry_b = dynamic_registry::dynamic_registry::mint_entry<GOLD>(
        5,
        b"backup",
        sui::test_scenario::ctx(&mut scenario),
    );
    dynamic_registry::dynamic_registry::add_entry(&cap, &mut registry, 7, entry_a);
    dynamic_registry::dynamic_registry::add_entry(&cap, &mut registry, 8, entry_b);

    let featured_id = *option::borrow(&dynamic_registry::dynamic_registry::entry_id_by_slot(&registry, 7));
    let backup_id = *option::borrow(&dynamic_registry::dynamic_registry::entry_id_by_slot(&registry, 8));
    assert!(dynamic_registry::dynamic_registry::shadow_anchor_id(&registry) == sui::object::id(&shadow), 0);
    assert!(dynamic_registry::dynamic_registry::shadow_anchor_kind(&shadow) == 42, 1);
    assert!(dynamic_registry::dynamic_registry::entry_count(&registry) == 2, 2);
    assert!(dynamic_registry::dynamic_registry::featured_slot(&registry) == 7, 3);
    assert!(dynamic_registry::dynamic_registry::featured_entry_score(&registry) == 11, 4);
    assert!(featured_id != backup_id, 5);
    assert!(featured_id != sui::object::id(&shadow), 6);

    sui::test_scenario::return_to_sender(&scenario, registry);
    sui::test_scenario::return_to_sender(&scenario, shadow);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}

#[test]
fun dynamic_registry_bumps_featured_and_removes_nonfeatured_entries() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _registry_id = setup_registry<GOLD>(&mut scenario, 7, 3);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let shadow = sui::test_scenario::take_from_sender<ShadowAnchor>(&scenario);
    let mut registry = sui::test_scenario::take_from_sender<Registry<GOLD>>(&scenario);

    let featured = dynamic_registry::dynamic_registry::mint_entry<GOLD>(
        9,
        b"hot",
        sui::test_scenario::ctx(&mut scenario),
    );
    let stale = dynamic_registry::dynamic_registry::mint_entry<GOLD>(
        4,
        b"stale",
        sui::test_scenario::ctx(&mut scenario),
    );
    dynamic_registry::dynamic_registry::add_entry(&cap, &mut registry, 3, featured);
    dynamic_registry::dynamic_registry::add_entry(&cap, &mut registry, 4, stale);
    dynamic_registry::dynamic_registry::bump_featured_score(&mut registry, 6);
    assert!(dynamic_registry::dynamic_registry::featured_entry_score(&registry) == 15, 0);

    let removed = dynamic_registry::dynamic_registry::remove_entry(&cap, &mut registry, 4);
    assert!(dynamic_registry::dynamic_registry::entry_score(&removed) == 4, 1);
    assert!(dynamic_registry::dynamic_registry::entry_label_len(&removed) == 5, 2);
    dynamic_registry::dynamic_registry::destroy_entry(removed);
    assert!(dynamic_registry::dynamic_registry::entry_count(&registry) == 1, 3);
    assert!(option::is_none(&dynamic_registry::dynamic_registry::entry_id_by_slot(&registry, 4)), 4);

    sui::test_scenario::return_to_sender(&scenario, registry);
    sui::test_scenario::return_to_sender(&scenario, shadow);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}

#[test]
fun dynamic_registry_specializes_multiple_types() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _registry_id = setup_registry<SILVER>(&mut scenario, 9, 1);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let shadow = sui::test_scenario::take_from_sender<ShadowAnchor>(&scenario);
    let mut registry = sui::test_scenario::take_from_sender<Registry<SILVER>>(&scenario);

    let entry = dynamic_registry::dynamic_registry::mint_entry<SILVER>(
        13,
        b"silver",
        sui::test_scenario::ctx(&mut scenario),
    );
    dynamic_registry::dynamic_registry::add_entry(&cap, &mut registry, 1, entry);
    assert!(dynamic_registry::dynamic_registry::entry_count(&registry) == 1, 0);
    assert!(dynamic_registry::dynamic_registry::featured_entry_score(&registry) == 13, 1);
    assert!(dynamic_registry::dynamic_registry::shadow_anchor_kind(&shadow) == 9, 2);

    sui::test_scenario::return_to_sender(&scenario, registry);
    sui::test_scenario::return_to_sender(&scenario, shadow);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}
