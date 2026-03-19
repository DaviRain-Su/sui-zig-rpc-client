#[test_only]
module admin_upgrade_lab::admin_upgrade_lab_tests;

use std::ascii;
use sui::package::UpgradeCap;
use admin_upgrade_lab::admin_upgrade_lab::{AdminCap, GovernancePolicy};

const ALICE: address = @0xA11CE;

fun setup_upgrade_objects(
    scenario: &mut sui::test_scenario::Scenario,
    required_policy: u8,
) {
    let cap = admin_upgrade_lab::admin_upgrade_lab::mint_admin_cap(sui::test_scenario::ctx(scenario));
    sui::transfer::public_transfer(cap, ALICE);
    sui::test_scenario::next_tx(scenario, ALICE);

    let cap = sui::test_scenario::take_from_sender<AdminCap>(scenario);
    let upgrade_cap = admin_upgrade_lab::admin_upgrade_lab::publish_for_testing(
        &cap,
        sui::test_scenario::ctx(scenario),
    );
    let policy = admin_upgrade_lab::admin_upgrade_lab::create_policy(
        &cap,
        &upgrade_cap,
        required_policy,
        sui::test_scenario::ctx(scenario),
    );
    sui::transfer::public_transfer(upgrade_cap, ALICE);
    sui::transfer::public_transfer(policy, ALICE);
    sui::test_scenario::return_to_sender(scenario, cap);
}

#[test]
fun admin_upgrade_lab_tracks_policy_and_version_across_upgrade() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    setup_upgrade_objects(&mut scenario, sui::package::compatible_policy());

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let mut upgrade_cap = sui::test_scenario::take_from_sender<UpgradeCap>(&scenario);
    let mut policy = sui::test_scenario::take_from_sender<GovernancePolicy>(&scenario);
    let original_package_id = admin_upgrade_lab::admin_upgrade_lab::policy_package_id(&policy);

    admin_upgrade_lab::admin_upgrade_lab::restrict_policy_to_additive(
        &cap,
        &mut policy,
        &mut upgrade_cap,
    );
    let ticket = admin_upgrade_lab::admin_upgrade_lab::authorize_with_policy(
        &cap,
        &policy,
        &mut upgrade_cap,
        admin_upgrade_lab::admin_upgrade_lab::new_plan(
            sui::package::dep_only_policy(),
            sui::hash::blake2b256(&b"admin-upgrade-v2"),
            2,
        ),
    );
    admin_upgrade_lab::admin_upgrade_lab::commit_upgrade_with_policy(
        &cap,
        &mut policy,
        &mut upgrade_cap,
        ticket,
    );

    assert!(admin_upgrade_lab::admin_upgrade_lab::policy_required_policy(&policy) == sui::package::additive_policy(), 0);
    assert!(admin_upgrade_lab::admin_upgrade_lab::policy_expected_version(&policy) == 2, 1);
    assert!(sui::package::version(&upgrade_cap) == 2, 2);
    assert!(sui::package::upgrade_policy(&upgrade_cap) == sui::package::additive_policy(), 3);
    assert!(admin_upgrade_lab::admin_upgrade_lab::policy_package_id(&policy) != original_package_id, 4);

    sui::test_scenario::return_to_sender(&scenario, upgrade_cap);
    sui::test_scenario::return_to_sender(&scenario, policy);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}

#[test]
fun admin_upgrade_lab_claims_local_publisher() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    let publisher = admin_upgrade_lab::admin_upgrade_lab::mint_publisher_for_testing(
        sui::test_scenario::ctx(&mut scenario),
    );

    assert!(admin_upgrade_lab::admin_upgrade_lab::publisher_matches_lab_package(&publisher), 0);
    assert!(admin_upgrade_lab::admin_upgrade_lab::publisher_matches_lab_module(&publisher), 1);
    assert!(sui::package::published_module(&publisher) == &ascii::string(b"admin_upgrade_lab"), 2);
    sui::package::burn_publisher(publisher);
    sui::test_scenario::end(scenario);
}

#[test]
fun admin_upgrade_lab_supports_dep_only_policy_flow() {
    let mut scenario = sui::test_scenario::begin(ALICE);
    setup_upgrade_objects(&mut scenario, sui::package::compatible_policy());

    sui::test_scenario::next_tx(&mut scenario, ALICE);
    let cap = sui::test_scenario::take_from_sender<AdminCap>(&scenario);
    let mut upgrade_cap = sui::test_scenario::take_from_sender<UpgradeCap>(&scenario);
    let mut policy = sui::test_scenario::take_from_sender<GovernancePolicy>(&scenario);

    admin_upgrade_lab::admin_upgrade_lab::restrict_policy_to_dep_only(
        &cap,
        &mut policy,
        &mut upgrade_cap,
    );
    let ticket = admin_upgrade_lab::admin_upgrade_lab::authorize_with_policy(
        &cap,
        &policy,
        &mut upgrade_cap,
        admin_upgrade_lab::admin_upgrade_lab::new_plan(
            sui::package::dep_only_policy(),
            sui::hash::blake2b256(&b"admin-upgrade-v3"),
            2,
        ),
    );
    admin_upgrade_lab::admin_upgrade_lab::commit_upgrade_with_policy(
        &cap,
        &mut policy,
        &mut upgrade_cap,
        ticket,
    );

    assert!(admin_upgrade_lab::admin_upgrade_lab::policy_required_policy(&policy) == sui::package::dep_only_policy(), 0);
    assert!(admin_upgrade_lab::admin_upgrade_lab::policy_expected_version(&policy) == 2, 1);
    assert!(sui::package::upgrade_policy(&upgrade_cap) == sui::package::dep_only_policy(), 2);
    assert!(sui::package::version(&upgrade_cap) == 2, 3);

    sui::test_scenario::return_to_sender(&scenario, upgrade_cap);
    sui::test_scenario::return_to_sender(&scenario, policy);
    sui::test_scenario::return_to_sender(&scenario, cap);
    sui::test_scenario::end(scenario);
}
