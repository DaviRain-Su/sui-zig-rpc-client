module pool_like_protocol_lab::pool_like_protocol_lab;

const EWRONG_POOL: u64 = 0;
const EMIN_LIQUIDITY: u64 = 1;
const EMIN_X_TOTAL: u64 = 2;
const EMIN_Y_TOTAL: u64 = 3;
const EWRONG_MANAGER: u64 = 4;

public struct GOLD has drop, store {}
public struct SILVER has drop, store {}
public struct BRONZE has drop, store {}

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct Pool<phantom X, phantom Y> has key, store {
    id: sui::object::UID,
    reserve_x: sui::balance::Balance<X>,
    reserve_y: sui::balance::Balance<Y>,
    fee_bps: u64,
    active_positions: u64,
    total_liquidity: u64,
    next_position_index: u64,
    total_fees_x: u64,
    total_fees_y: u64,
}

public struct Position<phantom X, phantom Y> has key, store {
    id: sui::object::UID,
    pool_id: sui::object::ID,
    index: u64,
    lower_tick: u64,
    upper_tick: u64,
    liquidity: u64,
    deposited_x: u64,
    deposited_y: u64,
}

public struct PoolManager<phantom X, phantom Y> has key, store {
    id: sui::object::UID,
    pool_id: sui::object::ID,
    last_position_id: option::Option<sui::object::ID>,
    last_liquidity: u64,
    sync_count: u64,
}

public struct AddLiquidityReceipt<phantom X, phantom Y> has copy, drop, store {
    pool_id: sui::object::ID,
    position_id: sui::object::ID,
    added_x: u64,
    added_y: u64,
    liquidity_delta: u64,
    liquidity_after: u64,
    keep_position_open: bool,
}

public struct LiquiditySnapshot<phantom X, phantom Y> has copy, drop, store {
    pool_id: sui::object::ID,
    position_id: sui::object::ID,
    reserve_x: u64,
    reserve_y: u64,
    pool_liquidity: u64,
    position_liquidity: u64,
    manager_sync_count: u64,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

public fun create_pool<X, Y>(
    _cap: &AdminCap,
    fee_bps: u64,
    seed_x: sui::balance::Balance<X>,
    seed_y: sui::balance::Balance<Y>,
    ctx: &mut sui::tx_context::TxContext,
): sui::object::ID {
    let pool = Pool {
        id: sui::object::new(ctx),
        reserve_x: seed_x,
        reserve_y: seed_y,
        fee_bps,
        active_positions: 0,
        total_liquidity: 0,
        next_position_index: 0,
        total_fees_x: 0,
        total_fees_y: 0,
    };
    let pool_id = sui::object::id(&pool);
    sui::transfer::share_object(pool);
    pool_id
}

public fun open_position<X, Y>(
    pool: &mut Pool<X, Y>,
    lower_tick: u64,
    upper_tick: u64,
    ctx: &mut sui::tx_context::TxContext,
): Position<X, Y> {
    let index = pool.next_position_index;
    pool.next_position_index = index + 1;
    pool.active_positions = pool.active_positions + 1;

    Position {
        id: sui::object::new(ctx),
        pool_id: sui::object::id(pool),
        index,
        lower_tick,
        upper_tick,
        liquidity: 0,
        deposited_x: 0,
        deposited_y: 0,
    }
}

public fun register_manager<X, Y>(
    pool: &Pool<X, Y>,
    position: &Position<X, Y>,
    ctx: &mut sui::tx_context::TxContext,
): PoolManager<X, Y> {
    assert!(position.pool_id == sui::object::id(pool), EWRONG_POOL);
    PoolManager {
        id: sui::object::new(ctx),
        pool_id: sui::object::id(pool),
        last_position_id: option::some(sui::object::id(position)),
        last_liquidity: position.liquidity,
        sync_count: 0,
    }
}

public fun add_liquidity_fix_coin<X, Y>(
    pool: &mut Pool<X, Y>,
    position: &mut Position<X, Y>,
    coin_x: sui::coin::Coin<X>,
    coin_y: sui::coin::Coin<Y>,
    min_liquidity: u64,
    keep_position_open: bool,
): AddLiquidityReceipt<X, Y> {
    assert!(position.pool_id == sui::object::id(pool), EWRONG_POOL);

    let added_x = sui::coin::value(&coin_x);
    let added_y = sui::coin::value(&coin_y);
    let liquidity_delta = if (added_x < added_y) added_x else added_y;
    assert!(liquidity_delta >= min_liquidity, EMIN_LIQUIDITY);

    sui::balance::join(&mut pool.reserve_x, sui::coin::into_balance(coin_x));
    sui::balance::join(&mut pool.reserve_y, sui::coin::into_balance(coin_y));

    position.deposited_x = position.deposited_x + added_x;
    position.deposited_y = position.deposited_y + added_y;
    position.liquidity = position.liquidity + liquidity_delta;
    pool.total_liquidity = pool.total_liquidity + liquidity_delta;
    pool.total_fees_x = pool.total_fees_x + added_x * pool.fee_bps / 10000;
    pool.total_fees_y = pool.total_fees_y + added_y * pool.fee_bps / 10000;

    AddLiquidityReceipt {
        pool_id: sui::object::id(pool),
        position_id: sui::object::id(position),
        added_x,
        added_y,
        liquidity_delta,
        liquidity_after: position.liquidity,
        keep_position_open,
    }
}

public fun add_liquidity_coin_vectors<X, Y>(
    pool: &mut Pool<X, Y>,
    position: &mut Position<X, Y>,
    coins_x: vector<sui::coin::Coin<X>>,
    coins_y: vector<sui::coin::Coin<Y>>,
    min_added_x: u64,
    min_added_y: u64,
): AddLiquidityReceipt<X, Y> {
    assert!(position.pool_id == sui::object::id(pool), EWRONG_POOL);

    let added_x = join_coin_vector(&mut pool.reserve_x, coins_x);
    let added_y = join_coin_vector(&mut pool.reserve_y, coins_y);
    assert!(added_x >= min_added_x, EMIN_X_TOTAL);
    assert!(added_y >= min_added_y, EMIN_Y_TOTAL);

    let liquidity_delta = if (added_x < added_y) added_x else added_y;
    position.deposited_x = position.deposited_x + added_x;
    position.deposited_y = position.deposited_y + added_y;
    position.liquidity = position.liquidity + liquidity_delta;
    pool.total_liquidity = pool.total_liquidity + liquidity_delta;
    pool.total_fees_x = pool.total_fees_x + added_x * pool.fee_bps / 10000;
    pool.total_fees_y = pool.total_fees_y + added_y * pool.fee_bps / 10000;

    AddLiquidityReceipt {
        pool_id: sui::object::id(pool),
        position_id: sui::object::id(position),
        added_x,
        added_y,
        liquidity_delta,
        liquidity_after: position.liquidity,
        keep_position_open: true,
    }
}

public fun sync_manager<X, Y>(
    manager: &mut PoolManager<X, Y>,
    pool: &Pool<X, Y>,
    position: &Position<X, Y>,
): LiquiditySnapshot<X, Y> {
    assert!(manager.pool_id == sui::object::id(pool), EWRONG_MANAGER);
    assert!(position.pool_id == sui::object::id(pool), EWRONG_POOL);

    manager.last_position_id = option::some(sui::object::id(position));
    manager.last_liquidity = position.liquidity;
    manager.sync_count = manager.sync_count + 1;

    LiquiditySnapshot {
        pool_id: sui::object::id(pool),
        position_id: sui::object::id(position),
        reserve_x: sui::balance::value(&pool.reserve_x),
        reserve_y: sui::balance::value(&pool.reserve_y),
        pool_liquidity: pool.total_liquidity,
        position_liquidity: position.liquidity,
        manager_sync_count: manager.sync_count,
    }
}

fun join_coin_vector<T>(
    target: &mut sui::balance::Balance<T>,
    coins: vector<sui::coin::Coin<T>>,
): u64 {
    let mut coins = coins;
    let mut total = 0;
    while (!vector::is_empty(&coins)) {
        let coin = vector::pop_back(&mut coins);
        total = total + sui::coin::value(&coin);
        sui::balance::join(target, sui::coin::into_balance(coin));
    };
    vector::destroy_empty(coins);
    total
}

public fun pool_reserve_x<X, Y>(pool: &Pool<X, Y>): u64 {
    sui::balance::value(&pool.reserve_x)
}

public fun pool_reserve_y<X, Y>(pool: &Pool<X, Y>): u64 {
    sui::balance::value(&pool.reserve_y)
}

public fun pool_fee_bps<X, Y>(pool: &Pool<X, Y>): u64 {
    pool.fee_bps
}

public fun pool_active_positions<X, Y>(pool: &Pool<X, Y>): u64 {
    pool.active_positions
}

public fun pool_total_liquidity<X, Y>(pool: &Pool<X, Y>): u64 {
    pool.total_liquidity
}

public fun pool_next_position_index<X, Y>(pool: &Pool<X, Y>): u64 {
    pool.next_position_index
}

public fun pool_total_fees_x<X, Y>(pool: &Pool<X, Y>): u64 {
    pool.total_fees_x
}

public fun pool_total_fees_y<X, Y>(pool: &Pool<X, Y>): u64 {
    pool.total_fees_y
}

public fun position_pool_id<X, Y>(position: &Position<X, Y>): sui::object::ID {
    position.pool_id
}

public fun position_index<X, Y>(position: &Position<X, Y>): u64 {
    position.index
}

public fun position_lower_tick<X, Y>(position: &Position<X, Y>): u64 {
    position.lower_tick
}

public fun position_upper_tick<X, Y>(position: &Position<X, Y>): u64 {
    position.upper_tick
}

public fun position_liquidity<X, Y>(position: &Position<X, Y>): u64 {
    position.liquidity
}

public fun position_deposited_x<X, Y>(position: &Position<X, Y>): u64 {
    position.deposited_x
}

public fun position_deposited_y<X, Y>(position: &Position<X, Y>): u64 {
    position.deposited_y
}

public fun manager_pool_id<X, Y>(manager: &PoolManager<X, Y>): sui::object::ID {
    manager.pool_id
}

public fun manager_last_liquidity<X, Y>(manager: &PoolManager<X, Y>): u64 {
    manager.last_liquidity
}

public fun manager_sync_count<X, Y>(manager: &PoolManager<X, Y>): u64 {
    manager.sync_count
}

public fun manager_has_last_position<X, Y>(manager: &PoolManager<X, Y>): bool {
    option::is_some(&manager.last_position_id)
}

public fun manager_last_position_id<X, Y>(manager: &PoolManager<X, Y>): sui::object::ID {
    *option::borrow(&manager.last_position_id)
}

public fun receipt_pool_id<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): sui::object::ID {
    receipt.pool_id
}

public fun receipt_position_id<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): sui::object::ID {
    receipt.position_id
}

public fun receipt_added_x<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): u64 {
    receipt.added_x
}

public fun receipt_added_y<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): u64 {
    receipt.added_y
}

public fun receipt_liquidity_delta<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): u64 {
    receipt.liquidity_delta
}

public fun receipt_liquidity_after<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): u64 {
    receipt.liquidity_after
}

public fun receipt_keep_position_open<X, Y>(receipt: &AddLiquidityReceipt<X, Y>): bool {
    receipt.keep_position_open
}

public fun snapshot_pool_id<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): sui::object::ID {
    snapshot.pool_id
}

public fun snapshot_position_id<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): sui::object::ID {
    snapshot.position_id
}

public fun snapshot_reserve_x<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): u64 {
    snapshot.reserve_x
}

public fun snapshot_reserve_y<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): u64 {
    snapshot.reserve_y
}

public fun snapshot_pool_liquidity<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): u64 {
    snapshot.pool_liquidity
}

public fun snapshot_position_liquidity<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): u64 {
    snapshot.position_liquidity
}

public fun snapshot_manager_sync_count<X, Y>(snapshot: &LiquiditySnapshot<X, Y>): u64 {
    snapshot.manager_sync_count
}
