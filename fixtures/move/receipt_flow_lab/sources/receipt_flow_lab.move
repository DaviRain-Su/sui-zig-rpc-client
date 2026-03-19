module receipt_flow_lab::receipt_flow_lab;

const EWRONG_RESERVE: u64 = 0;
const EINSUFFICIENT_REPAY: u64 = 1;

public struct GOLD has drop, store {}
public struct SILVER has drop, store {}

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct Reserve<phantom T> has key, store {
    id: sui::object::UID,
    available: sui::balance::Balance<T>,
    collected_fees: sui::balance::Balance<T>,
    fee_bps: u64,
    active_loans: u64,
}

public struct BorrowReceipt<phantom T> has key, store {
    id: sui::object::UID,
    reserve_id: sui::object::ID,
    principal: u64,
    fee_due: u64,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

#[allow(lint(self_transfer))]
public fun create_reserve<T>(
    _cap: &AdminCap,
    seed_balance: sui::balance::Balance<T>,
    fee_bps: u64,
    ctx: &mut sui::tx_context::TxContext,
): sui::object::ID {
    let reserve = Reserve {
        id: sui::object::new(ctx),
        available: seed_balance,
        collected_fees: sui::balance::zero<T>(),
        fee_bps,
        active_loans: 0,
    };
    let reserve_id = sui::object::id(&reserve);
    sui::transfer::public_transfer(reserve, sui::tx_context::sender(ctx));
    reserve_id
}

public fun borrow<T>(
    reserve: &mut Reserve<T>,
    principal: u64,
    ctx: &mut sui::tx_context::TxContext,
): (sui::coin::Coin<T>, BorrowReceipt<T>) {
    let fee_due = principal * reserve.fee_bps / 10000;
    let borrowed = sui::coin::from_balance(
        sui::balance::split(&mut reserve.available, principal),
        ctx,
    );
    reserve.active_loans = reserve.active_loans + 1;

    (
        borrowed,
        BorrowReceipt {
            id: sui::object::new(ctx),
            reserve_id: sui::object::id(reserve),
            principal,
            fee_due,
        },
    )
}

public fun repay<T>(
    reserve: &mut Reserve<T>,
    receipt: BorrowReceipt<T>,
    payment: sui::coin::Coin<T>,
    ctx: &mut sui::tx_context::TxContext,
): sui::coin::Coin<T> {
    let BorrowReceipt {
        id,
        reserve_id,
        principal,
        fee_due,
    } = receipt;
    assert!(reserve_id == sui::object::id(reserve), EWRONG_RESERVE);

    let due = principal + fee_due;
    assert!(sui::coin::value(&payment) >= due, EINSUFFICIENT_REPAY);

    let mut payment_balance = sui::coin::into_balance(payment);
    let principal_balance = sui::balance::split(&mut payment_balance, principal);
    let fee_balance = sui::balance::split(&mut payment_balance, fee_due);
    sui::balance::join(&mut reserve.available, principal_balance);
    sui::balance::join(&mut reserve.collected_fees, fee_balance);
    reserve.active_loans = reserve.active_loans - 1;
    sui::object::delete(id);

    sui::coin::from_balance(payment_balance, ctx)
}

public fun claim_fees<T>(
    _cap: &AdminCap,
    reserve: &mut Reserve<T>,
    amount: u64,
    ctx: &mut sui::tx_context::TxContext,
): sui::coin::Coin<T> {
    sui::coin::from_balance(
        sui::balance::split(&mut reserve.collected_fees, amount),
        ctx,
    )
}

public fun available_value<T>(reserve: &Reserve<T>): u64 {
    sui::balance::value(&reserve.available)
}

public fun collected_fee_value<T>(reserve: &Reserve<T>): u64 {
    sui::balance::value(&reserve.collected_fees)
}

public fun fee_bps<T>(reserve: &Reserve<T>): u64 {
    reserve.fee_bps
}

public fun active_loans<T>(reserve: &Reserve<T>): u64 {
    reserve.active_loans
}

public fun receipt_reserve_id<T>(receipt: &BorrowReceipt<T>): sui::object::ID {
    receipt.reserve_id
}

public fun receipt_principal<T>(receipt: &BorrowReceipt<T>): u64 {
    receipt.principal
}

public fun receipt_fee_due<T>(receipt: &BorrowReceipt<T>): u64 {
    receipt.fee_due
}
