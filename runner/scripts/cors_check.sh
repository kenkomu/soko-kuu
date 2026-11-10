#!/usr/bin/env bash
# Day-1 CORS test: start the runner with CORS_ORIGINS=<pages origin>, then act like a browser from
# that origin (preflight + real POST) and from an origin that is NOT listed (must get no CORS headers).
#   usage: scripts/cors_check.sh [https://youruser.github.io]
set -u
PAGES_ORIGIN="${1:-${PAGES_ORIGIN:-https://example-user.github.io}}"
BAD_ORIGIN="https://not-listed.example"
PORT="${PORT:-8791}"
BIN="$(dirname "$0")/../rs/target/debug/sokokuu-runner"
[ -x "$BIN" ] || (cd "$(dirname "$0")/../rs" && cargo build -q) || exit 2

MODE=demo PORT="$PORT" CORS_ORIGINS="$PAGES_ORIGIN" "$BIN" >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for _ in $(seq 1 50); do curl -s "localhost:$PORT/v1/health" >/dev/null && break; sleep 0.2; done

URL="http://localhost:$PORT"
fail=0
check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi
}
hdr() { grep -i "^$2:" <<<"$1" | tr -d '\r' | cut -d' ' -f2-; }

# 1. preflight from the Pages origin
PRE=$(curl -si -X OPTIONS "$URL/v1/act" -H "Origin: $PAGES_ORIGIN" \
  -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type")
[ "$(hdr "$PRE" access-control-allow-origin)" = "$PAGES_ORIGIN" ]; check "preflight allowed for $PAGES_ORIGIN" $?
hdr "$PRE" access-control-allow-methods | grep -q POST; check "preflight allows POST" $?
hdr "$PRE" access-control-allow-headers | grep -qi content-type; check "preflight allows content-type" $?

# 2. real POST from the Pages origin (guest sign-up needs only a pubkey; this key is throwaway)
PK="ed25519:11111111111111111111111111111111"
RES=$(curl -si -X POST "$URL/v1/auth/guest" -H "Origin: $PAGES_ORIGIN" -H "Content-Type: application/json" \
  -d "{\"pubkey\":\"$PK\",\"age_confirmed\":true}")
[ "$(hdr "$RES" access-control-allow-origin)" = "$PAGES_ORIGIN" ]; check "POST response carries allow-origin for the Pages origin" $?
grep -q '"ok":true' <<<"$RES"; check "POST succeeded (body ok)" $?

# 3. an origin that is not in CORS_ORIGINS gets no allow-origin header, on preflight or on the real request
PRE2=$(curl -si -X OPTIONS "$URL/v1/act" -H "Origin: $BAD_ORIGIN" -H "Access-Control-Request-Method: POST")
[ -z "$(hdr "$PRE2" access-control-allow-origin)" ]; check "preflight REFUSED for $BAD_ORIGIN (no allow-origin)" $?
RES2=$(curl -si "$URL/v1/health" -H "Origin: $BAD_ORIGIN")
[ -z "$(hdr "$RES2" access-control-allow-origin)" ]; check "GET from $BAD_ORIGIN gets no allow-origin (browser blocks it)" $?

# 4. localhost stays open for development
LOC=$(curl -si "$URL/v1/health" -H "Origin: http://localhost:5173")
[ "$(hdr "$LOC" access-control-allow-origin)" = "http://localhost:5173" ]; check "localhost dev origin allowed" $?

[ "$fail" -eq 0 ] && echo "CORS OK" || echo "CORS FAILED"
exit "$fail"
