#[test_only]
module pool_like_protocol_lab::pool_like_protocol_lab_tests;

use pool_like_protocol_lab::pool_like_protocol_lab::{
    AdminCap,
    BRONZE,
    GOLD,
    Pool,
    PoolManager,
    Position,
    SILVER,
};

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

fun setup_pool<X, Y>(
    scenario: &mut sui::test_scenario::Scenario,
    fee_bps: u64,
    seed_x: u64,
    seed_y: u64,
): sui::object::ID {
    let cap = pool_like_protocol_lab::pool_like_protocol_lab::mint_admin_cap(
        sui::test_scenario::ctx(scenario),
    );
    sui::transfer::public_transfer(cap, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let pool_id = pool_like_protocol_lab::pool_like_protocol_lab::create_pool<X, Y>(
        &cap,
        fee_bps,
        sui::balance::create_for_testing<X>(seed_x),
        sui::balance::create_for_testing<Y>(seed_y),
        sui::test_scenario::ctx(scenario),
    );
    sui::test_scenario::return_to_sender(scenario, cap);
    pool_id
}

#[test]
fun pool_like_protocol_combines_shared_pool_owned_position_and_manager() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let pool_id = setup_pool<GOLD, SILVER>(&mut scenario, 250, 100, 200);

    sui::test_scenario::next_tx(&mut scenario, BOB);
    let mut pool = sui::test_scenario::take_shared_by_id<Pool<GOLD, SILVER>>(&scenario, pool_id);
    let position = pool_like_protocol_lab::pool_like_protocol_lab::open_position<GOLD, SILVER>(
        &mut pool,
        10,
        90,
        sui::test_scenario::ctx(&mut scenario),
    );
    sui::transfer::public_transfer(position, BOB);
    sui::test_scenario::return_shared(pool);

    sui::test_scenario::next_tx(&mut scenario, BOB);
    let mut pool = sui::test_scenario::take_shared_by_id<Pool<GOLD, SILVER>>(&scenario, pool_id);
    let mut position = sui::test_scenario::take_from_sender<Position<GOLD, SILVER>>(&scenario);

    let receipt = pool_like_protocol_lab::pool_like_protocol_lab::add_liquidity_fix_coin<GOLD, SILVER>(
        &mut pool,
        &mut position,
        sui::coin::mint_for_testing<GOLD>(25, sui::test_scenario::ctx(&mut scenario)),
        sui::coin::mint_for_testing<SILVER>(40, sui::test_scenario::ctx(&mut scenario)),
        20,
        true,
    );
    let manager = pool_like_protocol_lab::pool_like_protocol_lab::register_manager<GOLD, SILVER>(
        &pool,
        &position,
        sui::test_scenario::ctx(&mut scenario),
    );

    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_pool_id(&receipt) == pool_id, 0);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_position_id(&receipt) == sui::object::id(&position), 1);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_added_x(&receipt) == 25, 2);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_added_y(&receipt) == 40, 3);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_liquidity_delta(&receipt) == 25, 4);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_liquidity_after(&receipt) == 25, 5);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_keep_position_open(&receipt), 6);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_reserve_x(&pool) == 125, 7);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_reserve_y(&pool) == 240, 8);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_liquidity(&pool) == 25, 9);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_fees_x(&pool) == 0, 10);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_fees_y(&pool) == 1, 11);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_pool_id(&position) == pool_id, 12);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_index(&position) == 0, 13);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_liquidity(&position) == 25, 14);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_deposited_x(&position) == 25, 15);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_deposited_y(&position) == 40, 16);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::manager_pool_id(&manager) == pool_id, 17);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::manager_has_last_position(&manager), 18);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::manager_last_position_id(&manager) == sui::object::id(&position), 19);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::manager_last_liquidity(&manager) == 25, 20);

    sui::transfer::public_transfer(manager, BOB);
    sui::test_scenario::return_shared(pool);
    sui::test_scenario::return_to_sender(&scenario, position);

    sui::test_scenario::next_tx(&mut scenario, BOB);
    let pool = sui::test_scenario::take_shared_by_id<Pool<GOLD, SILVER>>(&scenario, pool_id);
    let position = sui::test_scenario::take_from_sender<Position<GOLD, SILVER>>(&scenario);
    let mut manager = sui::test_scenario::take_from_sender<PoolManager<GOLD, SILVER>>(&scenario);
    let snapshot = pool_like_protocol_lab::pool_like_protocol_lab::sync_manager<GOLD, SILVER>(
        &mut manager,
        &pool,
        &position,
    );
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_pool_id(&snapshot) == pool_id, 21);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_position_id(&snapshot) == sui::object::id(&position), 22);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_reserve_x(&snapshot) == 125, 23);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_reserve_y(&snapshot) == 240, 24);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_pool_liquidity(&snapshot) == 25, 25);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_position_liquidity(&snapshot) == 25, 26);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::snapshot_manager_sync_count(&snapshot) == 1, 27);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::manager_sync_count(&manager) == 1, 28);
    sui::test_scenario::return_shared(pool);
    sui::test_scenario::return_to_sender(&scenario, position);
    sui::test_scenario::return_to_sender(&scenario, manager);

    sui::test_scenario::end(scenario);
}

#[test]
fun pool_like_protocol_routes_dual_coin_vectors_into_shared_pool() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let pool_id = setup_pool<GOLD, SILVER>(&mut scenario, 100, 10, 20);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut pool = sui::test_scenario::take_shared_by_id<Pool<GOLD, SILVER>>(&scenario, pool_id);
    let position = pool_like_protocol_lab::pool_like_protocol_lab::open_position<GOLD, SILVER>(
        &mut pool,
        5,
        50,
        sui::test_scenario::ctx(&mut scenario),
    );
    sui::transfer::public_transfer(position, ALICE);
    sui::test_scenario::return_shared(pool);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut pool = sui::test_scenario::take_shared_by_id<Pool<GOLD, SILVER>>(&scenario, pool_id);
    let mut position = sui::test_scenario::take_from_sender<Position<GOLD, SILVER>>(&scenario);

    let mut coins_x = vector::empty<sui::coin::Coin<GOLD>>();
    vector::push_back(
        &mut coins_x,
        sui::coin::mint_for_testing<GOLD>(7, sui::test_scenario::ctx(&mut scenario)),
    );
    vector::push_back(
        &mut coins_x,
        sui::coin::mint_for_testing<GOLD>(5, sui::test_scenario::ctx(&mut scenario)),
    );
    let mut coins_y = vector::empty<sui::coin::Coin<SILVER>>();
    vector::push_back(
        &mut coins_y,
        sui::coin::mint_for_testing<SILVER>(3, sui::test_scenario::ctx(&mut scenario)),
    );
    vector::push_back(
        &mut coins_y,
        sui::coin::mint_for_testing<SILVER>(11, sui::test_scenario::ctx(&mut scenario)),
    );

    let receipt = pool_like_protocol_lab::pool_like_protocol_lab::add_liquidity_coin_vectors<GOLD, SILVER>(
        &mut pool,
        &mut position,
        coins_x,
        coins_y,
        12,
        14,
    );
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_added_x(&receipt) == 12, 0);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_added_y(&receipt) == 14, 1);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_liquidity_delta(&receipt) == 12, 2);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_keep_position_open(&receipt), 3);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_reserve_x(&pool) == 22, 4);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_reserve_y(&pool) == 34, 5);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_liquidity(&pool) == 12, 6);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_liquidity(&position) == 12, 7);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_deposited_x(&position) == 12, 8);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_deposited_y(&position) == 14, 9);
    sui::test_scenario::return_shared(pool);
    sui::test_scenario::return_to_sender(&scenario, position);

    sui::test_scenario::end(scenario);
}

#[test]
fun pool_like_protocol_specializes_multiple_pairs_and_fee_paths() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let pool_id = setup_pool<BRONZE, SILVER>(&mut scenario, 1000, 8, 9);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut pool = sui::test_scenario::take_shared_by_id<Pool<BRONZE, SILVER>>(&scenario, pool_id);
    let position = pool_like_protocol_lab::pool_like_protocol_lab::open_position<BRONZE, SILVER>(
        &mut pool,
        1,
        7,
        sui::test_scenario::ctx(&mut scenario),
    );
    sui::transfer::public_transfer(position, ALICE);
    sui::test_scenario::return_shared(pool);

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let mut pool = sui::test_scenario::take_shared_by_id<Pool<BRONZE, SILVER>>(&scenario, pool_id);
    let mut position = sui::test_scenario::take_from_sender<Position<BRONZE, SILVER>>(&scenario);
    let receipt = pool_like_protocol_lab::pool_like_protocol_lab::add_liquidity_fix_coin<BRONZE, SILVER>(
        &mut pool,
        &mut position,
        sui::coin::mint_for_testing<BRONZE>(20, sui::test_scenario::ctx(&mut scenario)),
        sui::coin::mint_for_testing<SILVER>(10, sui::test_scenario::ctx(&mut scenario)),
        10,
        false,
    );
    assert!(!pool_like_protocol_lab::pool_like_protocol_lab::receipt_keep_position_open(&receipt), 0);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::receipt_liquidity_delta(&receipt) == 10, 1);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_fee_bps(&pool) == 1000, 2);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_fees_x(&pool) == 2, 3);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_fees_y(&pool) == 1, 4);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_total_liquidity(&pool) == 10, 5);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_liquidity(&position) == 10, 6);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_lower_tick(&position) == 1, 7);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::position_upper_tick(&position) == 7, 8);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_active_positions(&pool) == 1, 9);
    assert!(pool_like_protocol_lab::pool_like_protocol_lab::pool_next_position_index(&pool) == 1, 10);
    sui::test_scenario::return_shared(pool);
    sui::test_scenario::return_to_sender(&scenario, position);

    sui::test_scenario::end(scenario);
}
