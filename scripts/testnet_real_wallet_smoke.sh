#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gas_budget="${GAS_BUDGET:-2000000}"
split_amount="${SPLIT_AMOUNT:-1000000}"
auto_faucet="${AUTO_FAUCET:-0}"
allow_send="${ALLOW_SEND:-0}"
allow_non_testnet="${ALLOW_NON_TESTNET:-0}"
signer_selector="${SIGNER_SELECTOR:-}"
address="${1:-}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

if ! command -v sui >/dev/null 2>&1; then
    echo "sui CLI is required" >&2
    exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
    echo "zig is required" >&2
    exit 1
fi

active_env="$(sui client active-env)"
if [[ "$active_env" != "testnet" && "$allow_non_testnet" != "1" ]]; then
    echo "refusing to run outside testnet; active env is '$active_env'" >&2
    echo "set ALLOW_NON_TESTNET=1 only if you intentionally want another network" >&2
    exit 1
fi

if [[ -z "$address" ]]; then
    address="$(sui client active-address)"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

commands_json="$tmpdir/self_transfer_commands.json"
printf '[{"kind":"SplitCoins","coin":"GasCoin","amounts":[%s]},{"kind":"TransferObjects","objects":[{"Result":0}],"address":"%s"}]\n' \
    "$split_amount" \
    "$address" > "$commands_json"

echo "active_env=$active_env"
echo "address=$address"
echo "gas_budget=$gas_budget"
echo "split_amount=$split_amount"

gas_json="$(sui client gas --json "$address")"
gas_count="$(printf '%s\n' "$gas_json" | jq 'length')"

if [[ "$gas_count" == "0" && "$auto_faucet" == "1" ]]; then
    echo "no gas coins found; requesting testnet faucet"
    sui client faucet --json --address "$address"
    sleep 5
    gas_json="$(sui client gas --json "$address")"
    gas_count="$(printf '%s\n' "$gas_json" | jq 'length')"
fi

if [[ "$gas_count" == "0" ]]; then
    echo "no gas coins found for $address" >&2
    echo "rerun with AUTO_FAUCET=1 or fund the address first" >&2
    exit 1
fi

echo
echo "== sui client gas =="
printf '%s\n' "$gas_json" | jq .

echo
echo "== account resources =="
(
    cd "$repo_root"
    zig build run -- account resources "$address" \
        --coin-type '0x2::sui::SUI' \
        --struct-type '0x2::coin::Coin<0x2::sui::SUI>' \
        --json
)

dry_run_cmd=(
    zig build run -- tx dry-run
    --commands "@$commands_json"
    --sender "$address"
    --from-keystore
    --gas-budget "$gas_budget"
    --auto-gas-payment
    --summarize
)

if [[ -n "$signer_selector" ]]; then
    dry_run_cmd+=(--signer "$signer_selector")
fi

echo
echo "== tx dry-run =="
(
    cd "$repo_root"
    "${dry_run_cmd[@]}"
)

if [[ "$allow_send" != "1" ]]; then
    echo
    echo "dry-run completed; set ALLOW_SEND=1 to broadcast the same self-transfer on testnet"
    exit 0
fi

send_cmd=(
    zig build run -- tx send
    --commands "@$commands_json"
    --sender "$address"
    --from-keystore
    --gas-budget "$gas_budget"
    --auto-gas-payment
    --summarize
)

if [[ -n "$signer_selector" ]]; then
    send_cmd+=(--signer "$signer_selector")
fi

echo
echo "== tx send =="
(
    cd "$repo_root"
    "${send_cmd[@]}"
)
