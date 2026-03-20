#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_path="${1:-/tmp/hashi_inspect/packages/hashi}"
output_dir="${2:-/tmp/hashi_finish_publish_smoke}"

rpc_url="${SUI_RPC_URL:-http://127.0.0.1:19000}"
sui_config="${SUI_CONFIG:-/tmp/sui_hashi_localnet/client.yaml}"
sui_keystore="${SUI_KEYSTORE:-/tmp/sui_hashi_localnet/sui.keystore}"
bitcoin_chain_id="${HASHI_BITCOIN_CHAIN_ID:-0x0000000000000000000000000000000000000000000000000000000000000001}"
coin_registry_object_id="${HASHI_COIN_REGISTRY_OBJECT_ID:-0x000000000000000000000000000000000000000000000000000000000000000c}"
publish_gas_budget="${HASHI_PUBLISH_GAS_BUDGET:-500000000}"
finish_gas_budget="${HASHI_FINISH_PUBLISH_GAS_BUDGET:-100000000}"
gas_price="${HASHI_GAS_PRICE:-1000}"

for cmd in jq sui zig; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd is required" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"

build_json="$output_dir/hashi_build.json"
publish_commands_json="$output_dir/hashi_publish_commands.json"
publish_response_json="$output_dir/hashi_publish_response.json"
publish_confirm_json="$output_dir/hashi_publish_confirm.json"
finish_request_json="$output_dir/hashi_finish_publish_request.json"
finish_response_json="$output_dir/hashi_finish_publish_response.json"

sender="$(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- account list --json |
        jq -r '.accounts[0].address'
)"

if [[ -z "$sender" || "$sender" == "null" ]]; then
    echo "failed to resolve sender from keystore" >&2
    exit 1
fi

SUI_CONFIG="$sui_config" \
SUI_KEYSTORE="$sui_keystore" \
sui move build --dump-bytecode-as-base64 --path "$package_path" > "$build_json"

jq --arg sender "$sender" '[
  {kind:"Publish",modules:.modules,dependencies:.dependencies},
  {kind:"TransferObjects",objects:[{"Result":0}],address:$sender}
]' "$build_json" > "$publish_commands_json"

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- tx send \
        --commands "@$publish_commands_json" \
        --from-keystore \
        --gas-budget "$publish_gas_budget" \
        --gas-price "$gas_price" \
        --options '{"showEffects":true,"showObjectChanges":true}' \
        --rpc "$rpc_url" > "$publish_response_json"
)

publish_digest="$(
    jq -r '.result.digest // .digest' "$publish_response_json"
)"

if [[ -z "$publish_digest" || "$publish_digest" == "null" ]]; then
    echo "failed to resolve publish digest" >&2
    exit 1
fi

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- tx confirm "$publish_digest" \
        --rpc "$rpc_url" > "$publish_confirm_json"
)

package_id="$(
    jq -r '.result.objectChanges[] | select(.type=="published") | .packageId' \
        "$publish_response_json" | head -n 1
)"
hashi_object_id="$(
    jq -r --arg object_type "${package_id}::hashi::Hashi" \
        '.result.objectChanges[] | select(.type=="created" and .objectType==$object_type) | .objectId' \
        "$publish_response_json" | head -n 1
)"
upgrade_cap_id="$(
    jq -r '.result.objectChanges[] | select(.type=="created" and .objectType=="0x2::package::UpgradeCap") | .objectId' \
        "$publish_response_json" | head -n 1
)"

for value_name in package_id hashi_object_id upgrade_cap_id; do
    value="${!value_name}"
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "failed to resolve $value_name from publish response" >&2
        exit 1
    fi
done

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- move function "$package_id" hashi finish_publish \
        --object-arg-at 0 "$hashi_object_id" \
        --object-arg-at 1 "$upgrade_cap_id" \
        --arg-at 2 "$bitcoin_chain_id" \
        --object-arg-at 3 "$coin_registry_object_id" \
        --sender "$sender" \
        --emit-template preferred-send-request \
        --rpc "$rpc_url" > "$finish_request_json"
)

tmp_finish_request="$output_dir/hashi_finish_publish_request.exec.json"
jq --argjson gas_budget "$finish_gas_budget" '.gasBudget = $gas_budget' \
    "$finish_request_json" > "$tmp_finish_request"
mv "$tmp_finish_request" "$finish_request_json"

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- tx send \
        --request "@$finish_request_json" \
        --rpc "$rpc_url" > "$finish_response_json"
)

echo "Hashi finish_publish smoke succeeded."
echo "  sender: $sender"
echo "  package_id: $package_id"
echo "  hashi_object_id: $hashi_object_id"
echo "  upgrade_cap_id: $upgrade_cap_id"
echo "  publish_response: $publish_response_json"
echo "  finish_request: $finish_request_json"
echo "  finish_response: $finish_response_json"
jq '{status, status_error, gas_summary}' "$finish_response_json"
