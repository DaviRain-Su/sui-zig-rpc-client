module dynamic_registry::dynamic_registry;

public struct GOLD has drop, store {}
public struct SILVER has drop, store {}

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct ShadowAnchor has key, store {
    id: sui::object::UID,
    kind: u64,
}

public struct Registry<phantom T> has key, store {
    id: sui::object::UID,
    shadow_anchor_id: sui::object::ID,
    featured_slot: u64,
    entry_count: u64,
}

public struct RegistryEntry<phantom T> has key, store {
    id: sui::object::UID,
    score: u64,
    label: vector<u8>,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

public fun mint_shadow_anchor(kind: u64, ctx: &mut sui::tx_context::TxContext): ShadowAnchor {
    ShadowAnchor {
        id: sui::object::new(ctx),
        kind,
    }
}

public fun mint_entry<T>(
    score: u64,
    label: vector<u8>,
    ctx: &mut sui::tx_context::TxContext,
): RegistryEntry<T> {
    RegistryEntry {
        id: sui::object::new(ctx),
        score,
        label,
    }
}

#[allow(lint(self_transfer))]
public fun create_registry<T>(
    _cap: &AdminCap,
    shadow_anchor: &ShadowAnchor,
    featured_slot: u64,
    ctx: &mut sui::tx_context::TxContext,
): sui::object::ID {
    let registry: Registry<T> = Registry {
        id: sui::object::new(ctx),
        shadow_anchor_id: sui::object::id(shadow_anchor),
        featured_slot,
        entry_count: 0,
    };
    let registry_id = sui::object::id(&registry);
    sui::transfer::public_transfer(registry, sui::tx_context::sender(ctx));
    registry_id
}

public fun add_entry<T>(
    _cap: &AdminCap,
    registry: &mut Registry<T>,
    slot: u64,
    entry: RegistryEntry<T>,
) {
    sui::dynamic_object_field::add(&mut registry.id, slot, entry);
    registry.entry_count = registry.entry_count + 1;
}

public fun bump_featured_score<T>(registry: &mut Registry<T>, delta: u64) {
    let entry = sui::dynamic_object_field::borrow_mut<u64, RegistryEntry<T>>(
        &mut registry.id,
        registry.featured_slot,
    );
    entry.score = entry.score + delta;
}

public fun remove_entry<T>(
    _cap: &AdminCap,
    registry: &mut Registry<T>,
    slot: u64,
): RegistryEntry<T> {
    let entry = sui::dynamic_object_field::remove<u64, RegistryEntry<T>>(&mut registry.id, slot);
    registry.entry_count = registry.entry_count - 1;
    entry
}

public fun shadow_anchor_id<T>(registry: &Registry<T>): sui::object::ID {
    registry.shadow_anchor_id
}

public fun featured_slot<T>(registry: &Registry<T>): u64 {
    registry.featured_slot
}

public fun entry_count<T>(registry: &Registry<T>): u64 {
    registry.entry_count
}

public fun featured_entry_score<T>(registry: &Registry<T>): u64 {
    let entry = sui::dynamic_object_field::borrow<u64, RegistryEntry<T>>(
        &registry.id,
        registry.featured_slot,
    );
    entry.score
}

public fun entry_id_by_slot<T>(
    registry: &Registry<T>,
    slot: u64,
): option::Option<sui::object::ID> {
    sui::dynamic_object_field::id(&registry.id, slot)
}

public fun shadow_anchor_kind(anchor: &ShadowAnchor): u64 {
    anchor.kind
}

public fun entry_score<T>(entry: &RegistryEntry<T>): u64 {
    entry.score
}

public fun entry_label_len<T>(entry: &RegistryEntry<T>): u64 {
    vector::length(&entry.label)
}

public fun destroy_entry<T>(entry: RegistryEntry<T>) {
    let RegistryEntry { id, score: _, label: _ } = entry;
    sui::object::delete(id);
}
