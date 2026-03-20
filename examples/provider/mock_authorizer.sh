#!/bin/sh
set -eu

profile="${1:-passkey}"

# Consume the structured request from stdin so the script matches the real authorizer contract.
cat >/dev/null

case "$profile" in
  passkey)
    sender="0x1111111111111111111111111111111111111111111111111111111111111111"
    kind="passkey"
    session_id="passkey-example-approved"
    signature="sig-passkey-example"
    ;;
  remote_signer)
    sender="0x4444444444444444444444444444444444444444444444444444444444444444"
    kind="remote_signer"
    session_id="remote-signer-example-approved"
    signature="sig-remote-signer-example"
    ;;
  zklogin)
    sender="0x2222222222222222222222222222222222222222222222222222222222222222"
    kind="zklogin"
    session_id="zklogin-example-approved"
    signature="sig-zklogin-example"
    ;;
  multisig)
    sender="0x3333333333333333333333333333333333333333333333333333333333333333"
    kind="multisig"
    session_id="multisig-example-approved"
    signature="sig-multisig-example"
    ;;
  *)
    echo "unknown provider profile: $profile" >&2
    exit 1
    ;;
esac

printf '{"sender":"%s","signatures":["%s"],"session":{"kind":"%s","sessionId":"%s"},"supportsExecute":true}\n' \
  "$sender" \
  "$signature" \
  "$kind" \
  "$session_id"
