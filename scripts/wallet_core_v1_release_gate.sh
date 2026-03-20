#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hashi_package_path="${1:-/tmp/hashi_inspect/packages/hashi}"
output_dir="${2:-/tmp/wallet_core_v1_release_gate}"

skip_cetus_live="${WALLET_CORE_V1_SKIP_CETUS_LIVE:-0}"
cetus_rpc_url="${WALLET_CORE_V1_CETUS_RPC_URL:-}"
cetus_package_id="${WALLET_CORE_V1_CETUS_PACKAGE_ID:-0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb}"
cetus_module="${WALLET_CORE_V1_CETUS_MODULE:-pool}"
cetus_function="${WALLET_CORE_V1_CETUS_FUNCTION:-add_liquidity_fix_coin}"
cetus_global_config_selector="${WALLET_CORE_V1_CETUS_GLOBAL_CONFIG_SELECTOR:-cetus_clmm_global_config_mainnet}"

for cmd in bash jq zig; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd is required" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"

echo "== wallet-core v1 release gate =="
echo "repo_root: $repo_root"
echo "hashi_package_path: $hashi_package_path"
echo "output_dir: $output_dir"

(
    cd "$repo_root"
    zig build test --summary all
    zig build move-fixture-test
)

bash "$repo_root/scripts/hashi_publish_smoke.sh" \
    "$hashi_package_path" \
    "$output_dir/hashi_publish" >/dev/null

bash "$repo_root/scripts/hashi_finish_publish_smoke.sh" \
    "$hashi_package_path" \
    "$output_dir/hashi_finish_publish" >/dev/null

bash "$repo_root/scripts/hashi_deposit_smoke.sh" \
    "$hashi_package_path" \
    "$output_dir/hashi_deposit" >/dev/null

if [[ "$skip_cetus_live" == "1" ]]; then
    echo "Skipping Cetus live sanity because WALLET_CORE_V1_SKIP_CETUS_LIVE=1."
else
    if [[ -z "$cetus_rpc_url" ]]; then
        echo "WALLET_CORE_V1_CETUS_RPC_URL is required unless WALLET_CORE_V1_SKIP_CETUS_LIVE=1." >&2
        exit 1
    fi

    cetus_abi_json="$output_dir/cetus_normalized_function.json"
    cetus_global_config_json="$output_dir/cetus_global_config_summary.json"

    (
        cd "$repo_root"
        zig build run -- rpc sui_getNormalizedMoveFunction \
            "[\"$cetus_package_id\",\"$cetus_module\",\"$cetus_function\"]" \
            --rpc "$cetus_rpc_url" > "$cetus_abi_json"

        zig build run -- object get "$cetus_global_config_selector" \
            --summarize \
            --rpc "$cetus_rpc_url" > "$cetus_global_config_json"
    )

    jq -e '.result.parameters | length >= 1' "$cetus_abi_json" >/dev/null
    jq -e '.shared_object_input_select_token != null' "$cetus_global_config_json" >/dev/null

    echo "Cetus live sanity succeeded."
    echo "  normalized function: $cetus_abi_json"
    echo "  global config summary: $cetus_global_config_json"
fi

echo "wallet-core v1 release gate succeeded."
echo "  hashi publish: $output_dir/hashi_publish"
echo "  hashi finish_publish: $output_dir/hashi_finish_publish"
echo "  hashi deposit: $output_dir/hashi_deposit"
