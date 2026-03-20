#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_path="${1:-/tmp/hashi_inspect/packages/hashi}"
output_dir="${2:-/tmp/hashi_deposit_smoke}"

rpc_url="${SUI_RPC_URL:-http://127.0.0.1:19000}"
sui_config="${SUI_CONFIG:-/tmp/sui_hashi_localnet/client.yaml}"
sui_keystore="${SUI_KEYSTORE:-/tmp/sui_hashi_localnet/sui.keystore}"
deposit_amount_sats="${HASHI_DEPOSIT_AMOUNT_SATS:-546}"
deposit_vout="${HASHI_DEPOSIT_VOUT:-0}"
deposit_gas_budget="${HASHI_DEPOSIT_GAS_BUDGET:-100000000}"
derivation_path="${HASHI_DEPOSIT_DERIVATION_PATH:-}"

for cmd in jq zig bash od tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd is required" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"

setup_dir="$output_dir/setup"
commands_json="$output_dir/hashi_deposit_commands.json"
summary_json="$output_dir/hashi_object_summary.json"
deposit_response_json="$output_dir/hashi_deposit_response.json"

bash "$repo_root/scripts/hashi_finish_publish_smoke.sh" "$package_path" "$setup_dir" >/dev/null

publish_response_json="$setup_dir/hashi_publish_response.json"

sender="$(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- account list --json |
        jq -r '.accounts[0].address'
)"

package_id="$(
    jq -r '.result.objectChanges[] | select(.type=="published") | .packageId' \
        "$publish_response_json" | head -n 1
)"
hashi_object_id="$(
    jq -r --arg object_type "${package_id}::hashi::Hashi" \
        '.result.objectChanges[] | select(.type=="created" and .objectType==$object_type) | .objectId' \
        "$publish_response_json" | head -n 1
)"

for value_name in sender package_id hashi_object_id; do
    value="${!value_name}"
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "failed to resolve $value_name" >&2
        exit 1
    fi
done

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- object get "$hashi_object_id" \
        --summarize \
        --rpc "$rpc_url" > "$summary_json"
)

hashi_token="$(
    jq -r '.mutable_shared_object_input_select_token' "$summary_json"
)"

if [[ -z "$hashi_token" || "$hashi_token" == "null" ]]; then
    echo "failed to resolve mutable Hashi shared token" >&2
    exit 1
fi

txid_hex="0x$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"

if [[ -n "$derivation_path" ]]; then
    jq -n \
        --arg pkg "$package_id" \
        --arg hashi "$hashi_token" \
        --arg txid "$txid_hex" \
        --arg clock 'select:{"kind":"object_preset","name":"clock"}' \
        --arg derivation "$derivation_path" \
        --argjson vout "$deposit_vout" \
        --argjson amount "$deposit_amount_sats" \
        '[
          {
            kind: "MoveCall",
            package: $pkg,
            module: "utxo",
            function: "utxo_id",
            arguments: [$txid, $vout]
          },
          {
            kind: "MoveCall",
            package: $pkg,
            module: "utxo",
            function: "utxo",
            arguments: [{"Result":0}, $amount, $derivation]
          },
          {
            kind: "MoveCall",
            package: $pkg,
            module: "deposit_queue",
            function: "deposit_request",
            arguments: [{"Result":1}, $clock]
          },
          {
            kind: "MoveCall",
            package: "0x2",
            module: "coin",
            function: "zero",
            typeArguments: [
              {
                Struct: {
                  address: "0x2",
                  module: "sui",
                  name: "SUI",
                  typeParams: []
                }
              }
            ],
            arguments: []
          },
          {
            kind: "MoveCall",
            package: $pkg,
            module: "deposit",
            function: "deposit",
            arguments: [$hashi, {"Result":2}, {"Result":3}]
          }
        ]' > "$commands_json"
else
    jq -n \
        --arg pkg "$package_id" \
        --arg hashi "$hashi_token" \
        --arg txid "$txid_hex" \
        --arg clock 'select:{"kind":"object_preset","name":"clock"}' \
        --argjson vout "$deposit_vout" \
        --argjson amount "$deposit_amount_sats" \
        '[
          {
            kind: "MoveCall",
            package: $pkg,
            module: "utxo",
            function: "utxo_id",
            arguments: [$txid, $vout]
          },
          {
            kind: "MoveCall",
            package: $pkg,
            module: "utxo",
            function: "utxo",
            arguments: [{"Result":0}, $amount, null]
          },
          {
            kind: "MoveCall",
            package: $pkg,
            module: "deposit_queue",
            function: "deposit_request",
            arguments: [{"Result":1}, $clock]
          },
          {
            kind: "MoveCall",
            package: "0x2",
            module: "coin",
            function: "zero",
            typeArguments: [
              {
                Struct: {
                  address: "0x2",
                  module: "sui",
                  name: "SUI",
                  typeParams: []
                }
              }
            ],
            arguments: []
          },
          {
            kind: "MoveCall",
            package: $pkg,
            module: "deposit",
            function: "deposit",
            arguments: [$hashi, {"Result":2}, {"Result":3}]
          }
        ]' > "$commands_json"
fi

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- tx send \
        --commands "@$commands_json" \
        --from-keystore \
        --gas-budget "$deposit_gas_budget" \
        --rpc "$rpc_url" \
        --options '{"showEffects":true,"showEvents":true}' > "$deposit_response_json"
)

request_id="$(
    jq -r '.result.events[] | select(.type | endswith("::deposit::DepositRequestedEvent")) | .parsedJson.request_id' \
        "$deposit_response_json" | head -n 1
)"

if [[ -z "$request_id" || "$request_id" == "null" ]]; then
    echo "failed to resolve DepositRequestedEvent.request_id" >&2
    exit 1
fi

echo "Hashi deposit smoke succeeded."
echo "  sender: $sender"
echo "  package_id: $package_id"
echo "  hashi_object_id: $hashi_object_id"
echo "  txid: $txid_hex"
echo "  request_id: $request_id"
echo "  commands: $commands_json"
echo "  response: $deposit_response_json"
jq '{digest:.result.digest,event_count:(.result.events|length),request_id:([.result.events[] | select(.type | endswith("::deposit::DepositRequestedEvent")) | .parsedJson.request_id] | .[0])}' \
    "$deposit_response_json"
