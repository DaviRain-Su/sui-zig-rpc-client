module admin_upgrade_lab::admin_upgrade_lab;

const EWRONG_PACKAGE: u64 = 0;
const EWRONG_VERSION: u64 = 1;
const EWEAK_POLICY: u64 = 2;
const ETARGET_VERSION: u64 = 3;

public struct PUBLISHER_WITNESS has drop {}

public struct AdminCap has key, store {
    id: sui::object::UID,
}

public struct GovernancePolicy has key, store {
    id: sui::object::UID,
    package_id: sui::object::ID,
    required_policy: u8,
    expected_version: u64,
}

public struct UpgradePlan has copy, drop, store {
    policy: u8,
    digest: vector<u8>,
    target_version: u64,
}

public fun mint_admin_cap(ctx: &mut sui::tx_context::TxContext): AdminCap {
    AdminCap { id: sui::object::new(ctx) }
}

fun fresh_package_id(ctx: &mut sui::tx_context::TxContext): sui::object::ID {
    let uid = sui::object::new(ctx);
    let id = sui::object::uid_to_inner(&uid);
    sui::object::delete(uid);
    id
}

public fun publish_for_testing(
    _cap: &AdminCap,
    ctx: &mut sui::tx_context::TxContext,
): sui::package::UpgradeCap {
    sui::package::test_publish(fresh_package_id(ctx), ctx)
}

public fun mint_publisher_for_testing(
    ctx: &mut sui::tx_context::TxContext,
): sui::package::Publisher {
    sui::package::test_claim(PUBLISHER_WITNESS {}, ctx)
}

public fun create_policy(
    _cap: &AdminCap,
    upgrade_cap: &sui::package::UpgradeCap,
    required_policy: u8,
    ctx: &mut sui::tx_context::TxContext,
): GovernancePolicy {
    GovernancePolicy {
        id: sui::object::new(ctx),
        package_id: sui::package::upgrade_package(upgrade_cap),
        required_policy,
        expected_version: sui::package::version(upgrade_cap),
    }
}

public fun restrict_policy_to_additive(
    _cap: &AdminCap,
    policy: &mut GovernancePolicy,
    upgrade_cap: &mut sui::package::UpgradeCap,
) {
    sui::package::only_additive_upgrades(upgrade_cap);
    policy.required_policy = sui::package::additive_policy();
}

public fun restrict_policy_to_dep_only(
    _cap: &AdminCap,
    policy: &mut GovernancePolicy,
    upgrade_cap: &mut sui::package::UpgradeCap,
) {
    sui::package::only_dep_upgrades(upgrade_cap);
    policy.required_policy = sui::package::dep_only_policy();
}

public fun new_plan(
    policy: u8,
    digest: vector<u8>,
    target_version: u64,
): UpgradePlan {
    UpgradePlan {
        policy,
        digest,
        target_version,
    }
}

public fun authorize_with_policy(
    _cap: &AdminCap,
    policy: &GovernancePolicy,
    upgrade_cap: &mut sui::package::UpgradeCap,
    plan: UpgradePlan,
): sui::package::UpgradeTicket {
    assert!(sui::package::upgrade_package(upgrade_cap) == policy.package_id, EWRONG_PACKAGE);
    assert!(sui::package::version(upgrade_cap) == policy.expected_version, EWRONG_VERSION);
    assert!(plan.policy >= policy.required_policy, EWEAK_POLICY);
    assert!(plan.target_version == policy.expected_version + 1, ETARGET_VERSION);

    let UpgradePlan {
        policy: requested_policy,
        digest,
        target_version: _,
    } = plan;
    sui::package::authorize_upgrade(upgrade_cap, requested_policy, digest)
}

public fun commit_upgrade_with_policy(
    _cap: &AdminCap,
    policy: &mut GovernancePolicy,
    upgrade_cap: &mut sui::package::UpgradeCap,
    ticket: sui::package::UpgradeTicket,
) {
    let receipt = sui::package::test_upgrade(ticket);
    sui::package::commit_upgrade(upgrade_cap, receipt);
    policy.package_id = sui::package::upgrade_package(upgrade_cap);
    policy.expected_version = sui::package::version(upgrade_cap);
}

public fun publisher_matches_lab_package(publisher: &sui::package::Publisher): bool {
    sui::package::from_package<PUBLISHER_WITNESS>(publisher)
}

public fun publisher_matches_lab_module(publisher: &sui::package::Publisher): bool {
    sui::package::from_module<PUBLISHER_WITNESS>(publisher)
}

public fun policy_package_id(policy: &GovernancePolicy): sui::object::ID {
    policy.package_id
}

public fun policy_required_policy(policy: &GovernancePolicy): u8 {
    policy.required_policy
}

public fun policy_expected_version(policy: &GovernancePolicy): u64 {
    policy.expected_version
}
