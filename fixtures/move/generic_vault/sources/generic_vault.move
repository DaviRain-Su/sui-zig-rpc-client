module generic_vault::generic_vault;

const EDEPOSIT_TOO_SMALL: u64 = 0;
const EMIN_AFTER: u64 = 1;
const EWITHDRAW_GATE: u64 = 2;

public struct GOLD has drop, store {}
public struct SILVER has drop, store {}

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct Vault<phantom T> has key, store {
    id: sui::object::UID,
    balance: sui::balance::Balance<T>,
    manager: address,
    min_deposit: u64,
    withdraw_gate: option::Option<u64>,
}

public struct VaultConfig<phantom T> has copy, drop, store {
    manager: address,
    min_deposit: u64,
    withdraw_gate: option::Option<u64>,
}

public struct DepositReceipt<phantom T> has copy, drop, store {
    vault_id: sui::object::ID,
    deposited: u64,
    after: u64,
    min_deposit: u64,
    withdraw_gate: option::Option<u64>,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

public fun new_config<T>(
    manager: address,
    min_deposit: u64,
    withdraw_gate: option::Option<u64>,
): VaultConfig<T> {
    VaultConfig {
        manager,
        min_deposit,
        withdraw_gate,
    }
}

#[allow(lint(self_transfer))]
public fun create_vault<T>(
    _cap: &AdminCap,
    config: VaultConfig<T>,
    seed_balance: sui::balance::Balance<T>,
    ctx: &mut sui::tx_context::TxContext,
): sui::object::ID {
    let vault = Vault {
        id: sui::object::new(ctx),
        balance: seed_balance,
        manager: config.manager,
        min_deposit: config.min_deposit,
        withdraw_gate: config.withdraw_gate,
    };
    let vault_id = sui::object::id(&vault);
    sui::transfer::public_transfer(vault, sui::tx_context::sender(ctx));
    vault_id
}

public fun deposit_coin<T>(
    vault: &mut Vault<T>,
    coin: sui::coin::Coin<T>,
    min_after: option::Option<u64>,
): DepositReceipt<T> {
    let deposited = sui::coin::value(&coin);
    assert!(deposited >= vault.min_deposit, EDEPOSIT_TOO_SMALL);

    let after = sui::balance::join(&mut vault.balance, sui::coin::into_balance(coin));
    if (option::is_some(&min_after)) {
        assert!(after >= *option::borrow(&min_after), EMIN_AFTER);
    };

    DepositReceipt {
        vault_id: sui::object::id(vault),
        deposited,
        after,
        min_deposit: vault.min_deposit,
        withdraw_gate: vault.withdraw_gate,
    }
}

public fun reconfigure<T>(_cap: &AdminCap, vault: &mut Vault<T>, config: VaultConfig<T>) {
    vault.manager = config.manager;
    vault.min_deposit = config.min_deposit;
    vault.withdraw_gate = config.withdraw_gate;
}

public fun withdraw_coin<T>(
    _cap: &AdminCap,
    vault: &mut Vault<T>,
    amount: u64,
    ctx: &mut sui::tx_context::TxContext,
): sui::coin::Coin<T> {
    if (option::is_some(&vault.withdraw_gate)) {
        assert!(amount >= *option::borrow(&vault.withdraw_gate), EWITHDRAW_GATE);
    };
    sui::coin::from_balance(sui::balance::split(&mut vault.balance, amount), ctx)
}

public fun balance_value<T>(vault: &Vault<T>): u64 {
    sui::balance::value(&vault.balance)
}

public fun manager<T>(vault: &Vault<T>): address {
    vault.manager
}

public fun min_deposit<T>(vault: &Vault<T>): u64 {
    vault.min_deposit
}

public fun has_withdraw_gate<T>(vault: &Vault<T>): bool {
    option::is_some(&vault.withdraw_gate)
}

public fun withdraw_gate_value<T>(vault: &Vault<T>): u64 {
    *option::borrow(&vault.withdraw_gate)
}

public fun receipt_vault_id<T>(receipt: &DepositReceipt<T>): sui::object::ID {
    receipt.vault_id
}

public fun receipt_deposited<T>(receipt: &DepositReceipt<T>): u64 {
    receipt.deposited
}

public fun receipt_after<T>(receipt: &DepositReceipt<T>): u64 {
    receipt.after
}

public fun receipt_min_deposit<T>(receipt: &DepositReceipt<T>): u64 {
    receipt.min_deposit
}

public fun receipt_has_withdraw_gate<T>(receipt: &DepositReceipt<T>): bool {
    option::is_some(&receipt.withdraw_gate)
}

public fun receipt_withdraw_gate_value<T>(receipt: &DepositReceipt<T>): u64 {
    *option::borrow(&receipt.withdraw_gate)
}
