#[test_only]
module vector_router::vector_router_tests;
use vector_router::vector_router::{AdminCap, GOLD, RouteTag, Router, SILVER};

const ALICE: address = @0xA11CE;

fun setup_router<T>(scenario: &mut sui::test_scenario::Scenario): sui::object::ID {
    let cap = vector_router::vector_router::mint_admin_cap(sui::test_scenario::ctx(scenario));
    sui::transfer::public_transfer(cap, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let router_id = vector_router::vector_router::create_router<T>(
        &cap,
        sui::test_scenario::ctx(scenario),
    );
    sui::test_scenario::return_to_sender(scenario, cap);
    router_id
}

#[test]
fun vector_router_routes_object_vectors_and_nested_packets() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _router_id = setup_router<GOLD>(&mut scenario);

    let tag_a = vector_router::vector_router::mint_tag(4, sui::test_scenario::ctx(&mut scenario));
    let tag_b = vector_router::vector_router::mint_tag(7, sui::test_scenario::ctx(&mut scenario));
    sui::transfer::public_transfer(tag_a, ALICE);
    sui::transfer::public_transfer(tag_b, ALICE);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut router = sui::test_scenario::take_from_sender<Router<GOLD>>(&scenario);
    let tag_one = sui::test_scenario::take_from_sender<RouteTag>(&scenario);
    let tag_two = sui::test_scenario::take_from_sender<RouteTag>(&scenario);

    let mut tags = vector::empty<RouteTag>();
    vector::push_back(&mut tags, tag_one);
    vector::push_back(&mut tags, tag_two);

    let mut packets = vector::empty<vector<u8>>();
    vector::push_back(&mut packets, b"abc");
    vector::push_back(&mut packets, b"defg");

    let receipt = vector_router::vector_router::route_objects(&mut router, tags, packets);
    assert!(vector_router::vector_router::object_receipt_router_id(&receipt) == sui::object::id(&router), 0);
    assert!(vector_router::vector_router::object_receipt_tag_count(&receipt) == 2, 1);
    assert!(vector_router::vector_router::object_receipt_total_weight(&receipt) == 11, 2);
    assert!(vector_router::vector_router::object_receipt_packet_count(&receipt) == 2, 3);
    assert!(vector_router::vector_router::object_receipt_packet_bytes(&receipt) == 7, 4);
    assert!(vector_router::vector_router::routed_tag_count(&router) == 2, 5);
    assert!(vector_router::vector_router::routed_packet_count(&router) == 2, 6);
    assert!(vector_router::vector_router::routed_packet_bytes(&router) == 7, 7);
    sui::test_scenario::return_to_sender(&scenario, router);

    sui::test_scenario::end(scenario);
}

#[test]
fun vector_router_routes_two_coin_vectors_with_separate_thresholds() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _router_id = setup_router<GOLD>(&mut scenario);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut router = sui::test_scenario::take_from_sender<Router<GOLD>>(&scenario);

    let mut primary = vector::empty<sui::coin::Coin<GOLD>>();
    vector::push_back(
        &mut primary,
        sui::coin::mint_for_testing<GOLD>(11, sui::test_scenario::ctx(&mut scenario)),
    );
    vector::push_back(
        &mut primary,
        sui::coin::mint_for_testing<GOLD>(4, sui::test_scenario::ctx(&mut scenario)),
    );

    let mut rebate = vector::empty<sui::coin::Coin<GOLD>>();
    vector::push_back(
        &mut rebate,
        sui::coin::mint_for_testing<GOLD>(7, sui::test_scenario::ctx(&mut scenario)),
    );
    vector::push_back(
        &mut rebate,
        sui::coin::mint_for_testing<GOLD>(5, sui::test_scenario::ctx(&mut scenario)),
    );

    let receipt = vector_router::vector_router::route_coin_vectors(
        &mut router,
        primary,
        rebate,
        15,
        12,
    );
    assert!(vector_router::vector_router::coin_receipt_router_id(&receipt) == sui::object::id(&router), 0);
    assert!(vector_router::vector_router::coin_receipt_primary_total(&receipt) == 15, 1);
    assert!(vector_router::vector_router::coin_receipt_rebate_total(&receipt) == 12, 2);
    assert!(vector_router::vector_router::coin_receipt_primary_after(&receipt) == 15, 3);
    assert!(vector_router::vector_router::coin_receipt_rebate_after(&receipt) == 12, 4);
    assert!(vector_router::vector_router::primary_balance_value(&router) == 15, 5);
    assert!(vector_router::vector_router::rebate_balance_value(&router) == 12, 6);
    sui::test_scenario::return_to_sender(&scenario, router);

    sui::test_scenario::end(scenario);
}

#[test]
fun vector_router_specializes_multiple_coin_types() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let _router_id = setup_router<SILVER>(&mut scenario);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut router = sui::test_scenario::take_from_sender<Router<SILVER>>(&scenario);

    let mut primary = vector::empty<sui::coin::Coin<SILVER>>();
    vector::push_back(
        &mut primary,
        sui::coin::mint_for_testing<SILVER>(9, sui::test_scenario::ctx(&mut scenario)),
    );
    let rebate = vector::empty<sui::coin::Coin<SILVER>>();

    let receipt = vector_router::vector_router::route_coin_vectors(
        &mut router,
        primary,
        rebate,
        9,
        0,
    );
    assert!(vector_router::vector_router::coin_receipt_primary_total(&receipt) == 9, 0);
    assert!(vector_router::vector_router::coin_receipt_rebate_total(&receipt) == 0, 1);
    assert!(vector_router::vector_router::primary_balance_value(&router) == 9, 2);
    assert!(vector_router::vector_router::rebate_balance_value(&router) == 0, 3);
    sui::test_scenario::return_to_sender(&scenario, router);

    sui::test_scenario::end(scenario);
}
