#!/usr/bin/env bash
# Reset the Soko Kuu world on testnet: delete ONLY sokokuu.$ACCOUNT (balance goes back to $ACCOUNT), recreate it, deploy the wasm,
# call new. The relayer account and its restricted key are untouched (still valid: the key is tied to the receiver id string).
# Required env: ACCOUNT (e.g. sokokuu-ken.testnet), KEY_FILE (its credentials JSON, outside the repo).
# Optional: WASM (default target/sokokuu_contract.opt.wasm), EXPECT_SHA (sha256 prefix to enforce), SEED (1), FUND_CONTRACT (6).
# DRY_RUN=1 prints commands only; DRY_RUN=2 appends --help to each (syntax check, changes nothing). Never prints keys.
set -euo pipefail
: "${ACCOUNT:?set ACCOUNT}"; : "${KEY_FILE:?set KEY_FILE}"
SEED="${SEED:-1}"; DRY_RUN="${DRY_RUN:-0}"; FUND_CONTRACT="${FUND_CONTRACT:-6}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WASM="${WASM:-$HERE/target/sokokuu_contract.opt.wasm}"
CONTRACT="sokokuu.$ACCOUNT"; RELAYER="relayer.$ACCOUNT"
NET=(network-config testnet); CREDS="$HOME/.near-credentials/testnet"
[ -f "$KEY_FILE" ] && [ -f "$WASM" ] || { echo "KEY_FILE or WASM missing"; exit 1; }
SHA="$(sha256sum "$WASM" | cut -d' ' -f1)"; echo "wasm sha256 $SHA"
[ -z "${EXPECT_SHA:-}" ] || case "$SHA" in "$EXPECT_SHA"*) ;; *) echo "wasm hash mismatch"; exit 1;; esac
[ "$DRY_RUN" != 0 ] || command -v near >/dev/null || { echo "near-cli-rs not installed"; exit 1; }
run() { echo "+ near $*"; case "$DRY_RUN" in 0) near "$@";; 2) near "$@" --help >/dev/null && echo "  syntax ok";; esac; }
bal() { [ "$DRY_RUN" != 0 ] || for a in "$ACCOUNT" "$CONTRACT" "$RELAYER"; do echo "$a: $(near account view-account-summary "$a" "${NET[@]}" now 2>&1 | grep 'Native account balance' | awk '{print $4, $5}')"; done; }
echo "== balances before"; bal
# 1. delete ONLY the contract sub-account; its own (bootstrap) key signs, funds go to ACCOUNT
run account delete-account "$CONTRACT" beneficiary "$ACCOUNT" "${NET[@]}" sign-with-legacy-keychain send
# the old key is dead now; move the stale credentials file aside so the new key can be saved
[ "$DRY_RUN" != 0 ] || { [ ! -e "$CREDS/$CONTRACT.json" ] || mv "$CREDS/$CONTRACT.json" "$CREDS/$CONTRACT.json.deleted-$(date +%s)"; }
# 2. recreate, deploy, init (owner = ACCOUNT)
run account create-account fund-myself "$CONTRACT" "${FUND_CONTRACT} NEAR" autogenerate-new-keypair save-to-legacy-keychain sign-as "$ACCOUNT" "${NET[@]}" sign-with-access-key-file "$KEY_FILE" send
run contract deploy "$CONTRACT" use-file "$WASM" without-init-call "${NET[@]}" sign-with-legacy-keychain send
run contract call-function as-transaction "$CONTRACT" new json-args "{\"chain_id\":\"testnet\",\"seed\":$SEED,\"relayer\":\"$RELAYER\"}" prepaid-gas '30 Tgas' attached-deposit '0 NEAR' sign-as "$ACCOUNT" "${NET[@]}" sign-with-access-key-file "$KEY_FILE" send
# 3. read-only checks
run contract call-function as-read-only "$CONTRACT" clock json-args '{}' "${NET[@]}" now
run contract call-function as-read-only "$CONTRACT" world_hash json-args '{}' "${NET[@]}" now
run account list-keys "$RELAYER" "${NET[@]}" now
echo "== balances after"; bal
echo "Reset done: $CONTRACT (code sha256 $SHA)"
