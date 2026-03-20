#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_path="${1:-/tmp/hashi_inspect/packages/hashi}"
output_path="${2:-/tmp/hashi_publish_tx_block.json}"

sender="0x1111111111111111111111111111111111111111111111111111111111111111"
gas_payment='[{"objectId":"0x9999999999999999999999999999999999999999999999999999999999999999","version":"1","digest":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

build_json="$tmpdir/hashi_build.json"
commands_json="$tmpdir/hashi_publish_commands.json"

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

sui move build --dump-bytecode-as-base64 --path "$package_path" > "$build_json"
jq '[{kind:"Publish",modules:.modules,dependencies:.dependencies}]' "$build_json" > "$commands_json"

(
    cd "$repo_root"
    zig build run -- tx build programmable \
        --commands "@$commands_json" \
        --sender "$sender" \
        --gas-budget 100000000 \
        --gas-price 1000 \
        --gas-payment "$gas_payment" \
        --emit-tx-block > "$output_path"
)

echo "Hashi publish tx block written to: $output_path"
jq '{inputs:(.inputs|length),commands:(.commands|map(.kind)),gasBudget:.gasData.budget}' "$output_path"
