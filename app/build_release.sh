#!/usr/bin/env bash
# Release builds pointed at the public runner.
# Usage: PAGES_BASE_HREF=/soko-kuu/ ./build_release.sh [web] [apk] [appbundle]
#   No targets = web + apk. "appbundle" (.aab) is for the Play Store only.
#   API_BASE is overridable.
# APKs are split per CPU type (arm64-v8a, armeabi-v7a, x86_64), obfuscated, with
# debug symbols kept out of the app in build/debug-info (gitignored with build/;
# keep a copy to read crash stack traces). Share the arm64-v8a APK: almost every
# phone from the last few years takes it. Never share the debug APK.
set -euo pipefail
cd "$(dirname "$0")"
API_BASE="${API_BASE:-https://app.chukua.xyz}"
BASE_HREF="${PAGES_BASE_HREF:-/}"
TARGETS="${*:-web apk}"
case "$BASE_HREF" in /*/|/) ;; *) echo "PAGES_BASE_HREF must start and end with / (got $BASE_HREF)" >&2; exit 1;; esac
case "$API_BASE" in https://*) ;; *) echo "API_BASE must be https:// for a release (got $API_BASE)" >&2; exit 1;; esac
for t in $TARGETS; do
  case "$t" in web|apk|appbundle) ;; *) echo "Unknown target $t (use web, apk, appbundle)" >&2; exit 1;; esac
done
has() { [[ " $TARGETS " == *" $1 "* ]]; }
ANDROID_FLAGS=(--release --obfuscate --split-debug-info=build/debug-info --dart-define=API_BASE="$API_BASE")

if has web; then
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
fi

if has apk; then
  flutter build apk --split-per-abi "${ANDROID_FLAGS[@]}"
fi

if has appbundle; then
  flutter build appbundle "${ANDROID_FLAGS[@]}"
fi

echo
if has web; then
  echo "Web: $(pwd)/build/web ($(du -sh build/web | cut -f1)), base-href $BASE_HREF"
fi
if has apk; then
  for APK in build/app/outputs/flutter-apk/app-*-release.apk; do
    echo "APK: $(pwd)/$APK ($(du -h "$APK" | cut -f1))"
  done
fi
if has appbundle; then
  AAB=build/app/outputs/bundle/release/app-release.aab
  echo "AAB: $(pwd)/$AAB ($(du -h "$AAB" | cut -f1)), for the Play Store only"
fi
if has apk || has appbundle; then
  echo "Debug symbols: $(pwd)/build/debug-info (keep them to decode crash traces)"
fi
