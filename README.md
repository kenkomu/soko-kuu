# Soko Kuu

A closed-loop market game set in a Kenyan open-air market (soko), built for the NEAR Hackathon, Games track.
You trade produce with market-stall merchants, join a chama (a savings group that buys in bulk together), build a
repayment record and take small credit. Everything is played with **points (pts)**, a game score.

- Testnet only. No real money, no token, no prize, no cash-out. Points cannot be sent to other players.
- Prices come from plain, rule-based code (the `econ` crate), never from an AI. An optional language model may write
  short flavour lines only, and it is **off** in the deployed build (`LLM_PROVIDER=none`).
- The player never sees a wallet, seed phrase or gas prompt. Play starts as a guest after an 18+ confirmation.

## What NEAR does here

A NEAR testnet contract, `sokokuu.sokokuu-ken.testnet`, holds the whole game world and is the single source of truth.
A relayer pays gas, so players never need a wallet. Each player signs every action with their own ed25519 key. The
contract verifies the signature, nonce and expiry itself, so the relayer cannot forge or replay a move. Points are a
NEAR NEP-245 multi-token (`pts`) that is deliberately non-transferable.

| | |
|---|---|
| Contract | `sokokuu.sokokuu-ken.testnet` |
| Relayer account | `relayer.sokokuu-ken.testnet` |
| Chain id (part of the signed bytes) | `testnet` |
| Live runner API | `https://app.chukua.xyz` (`/v1/health`) |

Status note: goods are not yet NEP-245 token ids. Only `pts` is a token today; goods live in the contract's world
state. See "Known gaps" below.

## Try it in 90 seconds

You need nothing but the app. No account, no wallet and no email.

1. Open the app (Android APK or web build) and tap **I am 18 or older. Start**. Choose **Live market on NEAR** (the
   on-chain game), then **Play as a guest**. Expect: the Soko tab with today's prices and a banner saying points are
   for play only. (The other choice, **Play Soko Run**, is a quick 10-day offline run that never touches the chain.)
2. Tap a crop row. Expect: a "Why this price" explanation for the ask and bid.
3. At midday, tap **Buy**, then **Sell**. Expect: the result at once, with profit or loss shown.
4. Open **Duka** (your stall), **Chama**, **Deni** (credit) and **Ripoti** (report).
5. In **Ripoti**, run **What if? Fast-forward**: 30 days, **Drought**. Expect: a preview of prices and money. Your real
   game does not change.

The app opens in an offline demo when no runner address is built in. Step-by-step with screenshots: `app/DEMO.md`.

Run it from source (needs the Flutter SDK):

```
cd app
flutter run -d chrome --dart-define=DEMO=true                              # offline demo
flutter run -d chrome --dart-define=API_BASE=https://app.chukua.xyz        # live testnet runner
```

## Check the chain yourself (read-only, no account, no gas)

```
# runner health: expect "mode":"testnet" and "degraded":null
curl -s https://app.chukua.xyz/v1/health

# the game clock, straight from the contract
curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"call_function","finality":"final","account_id":"sokokuu.sokokuu-ken.testnet","method_name":"clock","args_base64":"e30="}}'

# points cannot be transferred: the call panics with NON_TRANSFERABLE
curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"call_function","finality":"final","account_id":"sokokuu.sokokuu-ken.testnet","method_name":"mt_transfer","args_base64":"e30="}}'
```

More checks (exported method list, code hash, replay and expiry rules): `contract/JUDGES.md`.

## The game loop

- **Every 30 seconds:** read a price and its "Why this price" lines, decide, buy or sell, see the result at once.
- **Every 5 to 10 minutes:** the market phase moves on (dawn, midday, dusk). Haggle with a merchant, join or vote in a
  chama, repay a loan. Radio Soko headlines (drought, rains, a festival) shift prices.
- **Every session:** read the day report (Ripoti) for faucets, sinks and your result, beat your personal best, grow your
  credit tier by repaying on time.

## How it is built

| Folder | What | Notes |
|---|---|---|
| `econ/` | Rust crate: pricing curve, events, chama and credit rules | No NEAR dependency. A 100-seed, 60-day stability simulation keeps total money within +-15% (worst measured drift is about 1%). `econ/JUDGES.md` |
| `contract/` | NEAR contract (near-sdk) | Signed `act`, non-transferable pts, uses `econ`. 46 unit tests plus local sandbox tests. `contract/JUDGES.md` |
| `runner/` | Rust (axum) relayer and API | Email login, merchant decision loop, `/v1/sim`, demo mode. 55 tests. `runner/JUDGES.md` |
| `app/` | Flutter (Android and web) | Talks only to the runner API. Offline demo mode. 31 tests. `app/JUDGES.md` |
| `docs/` | `API.md` (app-to-runner contract), `SECURITY_UX.md` | |

## Run the tests

```
cd econ     && cargo test --release                      # includes the 100-seed stability simulation
cd contract && cargo test                                 # 46 unit tests
cd runner   && make test                                  # API, signing, rate limits, CORS, sim
cd app      && flutter pub get && flutter analyze && flutter test
```

Build the contract with `cargo near build` (or `RUSTFLAGS="--cfg near"`). Without that flag, rejections lose their error
codes. Deploying the runner to a VPS: `runner/DEPLOY.md`.

## What the game never does

- No wallet shown to the player, no seed phrase, no gas prompt.
- No cash-out, no withdrawal, no token sale, no prize, no paid chance. 18+ gate before anything else.
- No transfer of points between players.
- No AI-set prices.

## Known gaps (honest list)

- Goods are not NEP-245 token ids yet; only `pts` is. This is being worked on.
- The offline demo uses a simplified chama (computer-controlled members, fixed pot). Against the live runner, chama loans
  and votes are real.
- Email magic-link sign-in needs a mail webhook that is not set up on the demo server, and the app has no deep-link page
  for it. Guest play is the supported path.
- The web build draws to a canvas; a text description of each screen is in `app/DEMO.md` and screenshots are in
  `app/screenshots/`.

## Dependencies and AI assistance

- Rust: near-sdk, near-sdk-contract-tools, axum, tokio and others (see each `Cargo.lock`). Flutter and Dart packages are
  listed in `app/pubspec.yaml`. Testnet RPC: `https://rpc.testnet.near.org`.
- Most of the code, tests and documentation were written with AI assistance (Claude Code), directed and reviewed by the
  author. Design notes and research are in the author's reports, not in this repo.
- All code in this repository was written during the hackathon period (the earliest files date from 8 November 2026).

## License

MIT. See `LICENSE`.
