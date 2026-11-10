#!/usr/bin/env bash
# Release builds (web + APK) pointed at the public runner.
# Usage: PAGES_BASE_HREF=/soko-kuu/ ./build_release.sh      (API_BASE overridable)
set -euo pipefail
cd "$(dirname "$0")"
API_BASE="${API_BASE:-https://app.chukua.xyz}"
BASE_HREF="${PAGES_BASE_HREF:-/}"
case "$BASE_HREF" in /*/|/) ;; *) echo "PAGES_BASE_HREF must start and end with / (got $BASE_HREF)" >&2; exit 1;; esac
case "$API_BASE" in https://*) ;; *) echo "API_BASE must be https:// for a release (got $API_BASE)" >&2; exit 1;; esac

flutter build web --release --no-web-resources-cdn \
  --base-href "$BASE_HREF" --dart-define=API_BASE="$API_BASE"

# Tighten the CSP in the built page only (source keeps localhost for debug runs).
python3 - "$API_BASE" <<'PY'
import re, sys
api = sys.argv[1].rstrip('/')
p = 'build/web/index.html'
s = open(p, encoding='utf-8').read()
n, k = re.subn(r"connect-src [^;]*;", f"connect-src 'self' {api};", s)
if k != 1: sys.exit('CSP connect-src not found exactly once')
open(p, 'w', encoding='utf-8').write(n)
PY
grep -o "connect-src[^;]*" build/web/index.html

flutter build apk --release --dart-define=API_BASE="$API_BASE"

echo
echo "Web: $(pwd)/build/web ($(du -sh build/web | cut -f1)), base-href $BASE_HREF"
APK=build/app/outputs/flutter-apk/app-release.apk
echo "APK: $(pwd)/$APK ($(du -h "$APK" | cut -f1))"
