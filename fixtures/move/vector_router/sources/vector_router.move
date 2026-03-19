module vector_router::vector_router;

const EPRIMARY_TOO_SMALL: u64 = 0;
const EREBATE_TOO_SMALL: u64 = 1;

public struct GOLD has drop, store {}
public struct SILVER has drop, store {}

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct RouteTag has key, store {
    id: sui::object::UID,
    weight: u64,
}

public struct Router<phantom T> has key, store {
    id: sui::object::UID,
    primary_balance: sui::balance::Balance<T>,
    rebate_balance: sui::balance::Balance<T>,
    routed_tag_count: u64,
    routed_packet_count: u64,
    routed_packet_bytes: u64,
}

public struct ObjectRouteReceipt has copy, drop, store {
    router_id: sui::object::ID,
    tag_count: u64,
    total_weight: u64,
    packet_count: u64,
    packet_bytes: u64,
}

public struct CoinRouteReceipt<phantom T> has copy, drop, store {
    router_id: sui::object::ID,
    primary_total: u64,
    rebate_total: u64,
    primary_after: u64,
    rebate_after: u64,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

#[allow(lint(self_transfer))]
public fun create_router<T>(_cap: &AdminCap, ctx: &mut sui::tx_context::TxContext): sui::object::ID {
    let router = Router {
        id: sui::object::new(ctx),
        primary_balance: sui::balance::zero<T>(),
        rebate_balance: sui::balance::zero<T>(),
        routed_tag_count: 0,
        routed_packet_count: 0,
        routed_packet_bytes: 0,
    };
    let router_id = sui::object::id(&router);
    sui::transfer::public_transfer(router, sui::tx_context::sender(ctx));
    router_id
}

public fun mint_tag(weight: u64, ctx: &mut sui::tx_context::TxContext): RouteTag {
    RouteTag {
        id: sui::object::new(ctx),
        weight,
    }
}

public fun route_objects<T>(
    router: &mut Router<T>,
    tags: vector<RouteTag>,
    packets: vector<vector<u8>>,
): ObjectRouteReceipt {
    let mut tags = tags;
    let mut tag_count = 0;
    let mut total_weight = 0;
    while (!vector::is_empty(&tags)) {
        let RouteTag { id, weight } = vector::pop_back(&mut tags);
        total_weight = total_weight + weight;
        tag_count = tag_count + 1;
        sui::object::delete(id);
    };
    vector::destroy_empty(tags);

    let packet_count = vector::length(&packets);
    let mut packet_bytes = 0;
    let mut i = 0;
    while (i < packet_count) {
        packet_bytes = packet_bytes + vector::length(vector::borrow(&packets, i));
        i = i + 1;
    };

    router.routed_tag_count = router.routed_tag_count + tag_count;
    router.routed_packet_count = router.routed_packet_count + packet_count;
    router.routed_packet_bytes = router.routed_packet_bytes + packet_bytes;

    ObjectRouteReceipt {
        router_id: sui::object::id(router),
        tag_count,
        total_weight,
        packet_count,
        packet_bytes,
    }
}

public fun route_coin_vectors<T>(
    router: &mut Router<T>,
    primary: vector<sui::coin::Coin<T>>,
    rebate: vector<sui::coin::Coin<T>>,
    min_primary_total: u64,
    min_rebate_total: u64,
): CoinRouteReceipt<T> {
    let primary_total = join_coin_vector(&mut router.primary_balance, primary);
    let rebate_total = join_coin_vector(&mut router.rebate_balance, rebate);
    assert!(primary_total >= min_primary_total, EPRIMARY_TOO_SMALL);
    assert!(rebate_total >= min_rebate_total, EREBATE_TOO_SMALL);

    CoinRouteReceipt {
        router_id: sui::object::id(router),
        primary_total,
        rebate_total,
        primary_after: sui::balance::value(&router.primary_balance),
        rebate_after: sui::balance::value(&router.rebate_balance),
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

public fun primary_balance_value<T>(router: &Router<T>): u64 {
    sui::balance::value(&router.primary_balance)
}

public fun rebate_balance_value<T>(router: &Router<T>): u64 {
    sui::balance::value(&router.rebate_balance)
}

public fun routed_tag_count<T>(router: &Router<T>): u64 {
    router.routed_tag_count
}

public fun routed_packet_count<T>(router: &Router<T>): u64 {
    router.routed_packet_count
}

public fun routed_packet_bytes<T>(router: &Router<T>): u64 {
    router.routed_packet_bytes
}

public fun object_receipt_router_id(receipt: &ObjectRouteReceipt): sui::object::ID {
    receipt.router_id
}

public fun object_receipt_tag_count(receipt: &ObjectRouteReceipt): u64 {
    receipt.tag_count
}

public fun object_receipt_total_weight(receipt: &ObjectRouteReceipt): u64 {
    receipt.total_weight
}

public fun object_receipt_packet_count(receipt: &ObjectRouteReceipt): u64 {
    receipt.packet_count
}

public fun object_receipt_packet_bytes(receipt: &ObjectRouteReceipt): u64 {
    receipt.packet_bytes
}

public fun coin_receipt_router_id<T>(receipt: &CoinRouteReceipt<T>): sui::object::ID {
    receipt.router_id
}

public fun coin_receipt_primary_total<T>(receipt: &CoinRouteReceipt<T>): u64 {
    receipt.primary_total
}

public fun coin_receipt_rebate_total<T>(receipt: &CoinRouteReceipt<T>): u64 {
    receipt.rebate_total
}

public fun coin_receipt_primary_after<T>(receipt: &CoinRouteReceipt<T>): u64 {
    receipt.primary_after
}

public fun coin_receipt_rebate_after<T>(receipt: &CoinRouteReceipt<T>): u64 {
    receipt.rebate_after
}
