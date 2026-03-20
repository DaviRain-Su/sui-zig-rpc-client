#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_path="${1:-/tmp/hashi_inspect/packages/hashi}"
output_dir="${2:-/tmp/hashi_request_withdrawal_smoke}"

rpc_url="${SUI_RPC_URL:-http://127.0.0.1:19000}"
sui_config="${SUI_CONFIG:-/tmp/sui_hashi_localnet/client.yaml}"
sui_keystore="${SUI_KEYSTORE:-/tmp/sui_hashi_localnet/sui.keystore}"
withdraw_gas_budget="${HASHI_WITHDRAW_GAS_BUDGET:-100000000}"
bitcoin_address_json="${HASHI_WITHDRAW_BITCOIN_ADDRESS_JSON:-[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}"

for cmd in jq zig bash; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd is required" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"

hashi_summary_json="$output_dir/hashi_object_summary.json"
btc_coin_summary_json="$output_dir/btc_coin_summary.json"
btc_coins_json="$output_dir/btc_coins.json"
withdraw_request_json="$output_dir/hashi_withdraw_request.json"
withdraw_response_json="$output_dir/hashi_withdraw_response.json"

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

package_id="${HASHI_PACKAGE_ID:-}"
hashi_object_id="${HASHI_HASHI_OBJECT_ID:-}"

for value_name in sender package_id hashi_object_id; do
    value="${!value_name}"
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "missing required $value_name" >&2
        echo "set HASHI_PACKAGE_ID and HASHI_HASHI_OBJECT_ID to an already published + initialized Hashi deployment before running this smoke." >&2
        exit 2
    fi
done

btc_coin_type="${package_id}::btc::BTC"
btc_coin_id="${HASHI_BTC_COIN_OBJECT_ID:-}"

if [[ -z "$btc_coin_id" ]]; then
    (
        cd "$repo_root"
        SUI_CONFIG="$sui_config" \
        SUI_KEYSTORE="$sui_keystore" \
        zig build run -- account coins "$sender" \
            --coin-type "$btc_coin_type" \
            --limit 1 \
            --json \
            --rpc "$rpc_url" > "$btc_coins_json"
    )
    btc_coin_id="$(
        jq -r '.result.data[0].coinObjectId // empty' "$btc_coins_json"
    )"
    if [[ -z "$btc_coin_id" ]]; then
        echo "no Coin<${btc_coin_type}> found for sender $sender" >&2
        echo "seed hBTC first, then rerun this smoke." >&2
        echo "suggested seed path: use Hashi localnet/e2e deposit confirm flow, or pass HASHI_BTC_COIN_OBJECT_ID." >&2
        exit 2
    fi
fi

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- object get "$hashi_object_id" \
        --summarize \
        --rpc "$rpc_url" > "$hashi_summary_json"
    zig build run -- object get "$btc_coin_id" \
        --summarize \
        --rpc "$rpc_url" > "$btc_coin_summary_json"
)

hashi_token="$(
    jq -r '.mutable_shared_object_input_select_token' "$hashi_summary_json"
)"
btc_coin_token="$(
    jq -r '.imm_or_owned_object_input_select_token' "$btc_coin_summary_json"
)"

if [[ -z "$hashi_token" || "$hashi_token" == "null" ]]; then
    echo "failed to resolve mutable Hashi shared token" >&2
    exit 1
fi
if [[ -z "$btc_coin_token" || "$btc_coin_token" == "null" ]]; then
    echo "failed to resolve Coin<BTC> owned token" >&2
    exit 1
fi

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- move function "$package_id" withdraw request_withdrawal \
        --object-arg-at 0 "$hashi_object_id" \
        --object-arg-at 2 "$btc_coin_id" \
        --arg-at 3 "$bitcoin_address_json" \
        --sender "$sender" \
        --emit-template preferred-send-request \
        --rpc "$rpc_url" > "$withdraw_request_json"
)

(
    cd "$repo_root"
    SUI_CONFIG="$sui_config" \
    SUI_KEYSTORE="$sui_keystore" \
    zig build run -- tx send \
        --request "@$withdraw_request_json" \
        --options '{"showEffects":true,"showEvents":true}' \
        --rpc "$rpc_url" > "$withdraw_response_json"
)

request_id="$(
    jq -r '.result.events[] | select(.type | endswith("::withdrawal_queue::WithdrawalRequestedEvent") or endswith("::withdraw::WithdrawalRequestedEvent")) | .parsedJson.request_id' \
        "$withdraw_response_json" | head -n 1
)"

if [[ -z "$request_id" || "$request_id" == "null" ]]; then
    echo "failed to resolve WithdrawalRequestedEvent.request_id" >&2
    exit 1
fi

echo "Hashi request_withdrawal smoke succeeded."
echo "  sender: $sender"
echo "  package_id: $package_id"
echo "  hashi_object_id: $hashi_object_id"
echo "  btc_coin_id: $btc_coin_id"
echo "  request_id: $request_id"
echo "  request: $withdraw_request_json"
echo "  response: $withdraw_response_json"
jq '{digest:.result.digest,event_count:(.result.events|length),request_id:([.result.events[] | select(.type | endswith("WithdrawalRequestedEvent")) | .parsedJson.request_id] | .[0])}' \
    "$withdraw_response_json"
