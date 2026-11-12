# Soko Kuu app (Flutter, Android + web)

Run offline demo (no runner needed; also the default when API_BASE is empty):
    flutter run -d chrome --dart-define=DEMO=true
Against a runner:
    flutter run -d chrome --dart-define=API_BASE=https://app.chukua.xyz
Tests: `flutter test` (includes the near-api-js signature vector in test/signing_test.dart).
Builds: `flutter build web --release --base-href /<repo>/`, `flutter build apk --debug`.

Note: the offline demo uses a simplified group-buy chama (NPC members, fixed pot) and does not open chama loan offers or votes on credit requests, unlike the real runner.

## Deploy to GitHub Pages
Build with the runner's HTTPS origin baked in (the app reads `API_BASE` at build time; without it the app runs the offline demo):

    flutter build web --release --no-web-resources-cdn \
      --base-href /<repo>/ --dart-define=API_BASE=https://app.chukua.xyz

For a project page the base href is `/<repo>/` (leading and trailing slash). Copy everything inside `build/web/` to the
Pages branch or `docs/` folder (index.html, main.dart.js, flutter.js, flutter_bootstrap.js, canvaskit/, assets/, icons/,
manifest.json, favicon*.png). `./build_release.sh` builds web and APK in one go (`PAGES_BASE_HREF=/<repo>/ ./build_release.sh`; `API_BASE` defaults to https://app.chukua.xyz) and rewrites the built page's CSP so `connect-src` is only `'self'` plus the runner origin. The source `web/index.html` keeps localhost for debug runs.
The runner must answer CORS for the Pages origin (`https://<user>.github.io`).

### Point the app at a runner
`API_BASE` is fixed at build time. To change runner, rebuild with a new `--dart-define=API_BASE=https://app.chukua.xyz`
and redeploy. The runner needs `CORS_ORIGINS=https://<user>.github.io` (exact origin, no path). Check with
`runner/scripts/cors_check.sh https://<user>.github.io`.
Release APKs: `./build_release.sh apk` builds one obfuscated APK per CPU type (about 16-21 MB each; share
`app-arm64-v8a-release.apk`, which fits almost every recent phone) with debug symbols in `build/debug-info`.
`./build_release.sh appbundle` makes the Play Store `.aab`. Debug signing; sideload only. Never share the debug APK (about 200 MB).

## Screenshots (offline demo, phone width, English unless noted)
Captured from a local profile web build in demo mode (`--dart-define=DEMO=true`) with headless Chromium.
- `screenshots/01-age-gate.png` age gate and plain rules
- `screenshots/02-market-board.png` market board (Soko) with today's prices
- `screenshots/03-buy-sheet-why-this-price.png` buy sheet with "Why this price"
- `screenshots/04-stall-duka.png` stall (Duka)
- `screenshots/05-chama.png` chama with pooled price and group vote
- `screenshots/06-credit-deni.png` credit (Deni)
- `screenshots/07-report-fast-forward.png` report with the "What if? Fast-forward" card after a preview
- `screenshots/08-market-kiswahili.png` market board after switching to Kiswahili in Settings

For judges: see `JUDGES.md`.
