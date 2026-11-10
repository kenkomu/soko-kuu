# Soko Kuu runner

Relayer for the Soko Kuu app. It implements `docs/API.md` (payload shapes: `SHAPES.md`): verifies signed actions,
applies the econ rules, submits to the NEAR contract and pays the gas. Rust (axum). Rules come from the `../econ` crate.
Prices are rule-based code; the LLM, if ever enabled, may only write voice lines (`LLM_PROVIDER=none` by default).

```
runner/
  Makefile        delegates to rs/
  SHAPES.md       exact JSON shapes of every endpoint
  scripts/cors_check.sh
  rs/             the Cargo project (src/, tests/, .env.example)
```

## Run

| Command | What it does |
|---|---|
| `make demo` | Demo mode on `:8787` (or `PORT=...`): in-memory seeded ledger, same API, no chain, no relayer. |
| `make test` | All tests (55, plus 2 ignored; the junk-input bounds test takes about 70 s): signatures, errors, limits, rollback, rebind, events, CORS, sim, 100-seed money drift. |
| `make build` | Release binary at `rs/target/release/sokokuu-runner`. |

Demo mode returns the magic-link token in the register response when `DEV_RETURN_TOKEN=1` (set by `make demo`), so the
app can log in without email. If testnet or the relayer is down the runner falls back to demo and says so in `/v1/health`
(`mode`, `degraded`).

## Day-1 CORS test (Pages origin to runner)

```
runner/scripts/cors_check.sh https://YOURUSER.github.io
```
It starts the runner with `CORS_ORIGINS=<that origin>`, then behaves like a browser: a preflight (`OPTIONS /v1/act` with
`Origin`, `Access-Control-Request-Method: POST`, `Access-Control-Request-Headers: content-type`) and a real
`POST /v1/auth/guest` from the Pages origin, and checks the response carries `Access-Control-Allow-Origin` equal to that
origin. It then repeats both from `https://not-listed.example` and checks that no `Access-Control-Allow-Origin` header is
returned, which is what makes a browser block the call. It also checks that `http://localhost:*` stays allowed for dev.
Prints `CORS OK` and exits 0 when all eight checks pass. Origins must match exactly (scheme, host, port); there are no wildcards.

Against a deployed runner, test the real thing from the browser console on the Pages site:
`fetch(API_BASE + '/v1/health').then(r => r.json()).then(console.log)`.

## Configuration

All settings are environment variables. The complete, commented list is `rs/.env.example`. Copy it to `rs/.env`
(git-ignored) or set the variables in your host's secret store. Key ones:

| Variable | Meaning |
|---|---|
| `MODE` | `demo` (default) or `testnet`. |
| `PORT` | Listen port (default 8787). |
| `BIND_ADDR` | Listen address. Default `127.0.0.1` when `MODE=testnet`, `0.0.0.0` otherwise (demo/dev). |
| `CHAIN_ID`, `CONTRACT_ID` | Part of the signed bytes; must equal the contract's chain id and account. |
| `CORS_ORIGINS` | Exact allowed origins, comma separated (the GitHub Pages origin). Localhost always allowed. |
| `PHASE_SECS` | Relayer clock: advance one phase every N seconds. `0` = manual only. |
| `ADMIN_TOKEN` | Secret for `POST /v1/admin/advance` and `POST /v1/admin/pause` (header `x-admin-token`). Unset disables admin. |
| `RELAYER_ACCOUNT_ID`, `RELAYER_KEY_FILE`, `NEAR_RPC_URL` | Testnet only. The relayer account signs and pays gas. `RELAYER_KEY_FILE` is a path to the key file, never the key itself. |
| `GAS_TGAS`, `MIN_BALANCE_NEAR` | Gas cap per call (default 100, max 300); balance alarm threshold (default 0.5 NEAR). |
| `IP_RPM`, `TRUST_PROXY`, `EMAILS_PER_HOUR`, `MAX_NEW_ACCOUNTS_PER_DAY` | Limits (defaults 120, off, 3, 100). |
| `MAIL_WEBHOOK_URL`, `PUBLIC_CONFIRM_URL` | Magic-link email: POST `{to,subject,text}` to the webhook; link prefix. Unset = the link is logged to stdout. |

## Deploy checklist (testnet)

1. **Contract.** Deploy it and initialise with the relayer account as `relayer` (see `contract/`). Note `CONTRACT_ID`.
2. **Relayer account.** Create a testnet account used only for relaying (for example `sokokuu-relayer.testnet`) and fund
   it from the testnet faucet. Add a **function-call access key** limited to `CONTRACT_ID` with methods `act`,
   `advance_clock`, `rebind_key`, and save that key's secret to a file outside the repo; point `RELAYER_KEY_FILE` at it
   (a full-access key also works but is riskier). The runner only ever calls those three methods. Full steps: `DEPLOY.md`.
3. **Secrets.** Provide the `RELAYER_KEY_FILE` path (see `DEPLOY.md`), `ADMIN_TOKEN` and `MAIL_WEBHOOK_URL` through the host's environment or
   secret store. They are never committed (`.env` is in `.gitignore`; the repo only has `.env.example` with empty values).
   Rotate the relayer key by adding a new access key, restarting with it, then deleting the old one.
4. **Run** with `make testnet` behind HTTPS (options in `DEPLOY.md`): `CORS_ORIGINS=https://YOURUSER.github.io
   PHASE_SECS=... ./sokokuu-runner`. Set `TRUST_PROXY=1` only if a trusted proxy sets `X-Forwarded-For`.
5. **Health check.** `GET /v1/health` returns `{"ok":true,"data":{"mode":"testnet","degraded":null,
   "relayer_balance_alarm":null,"paused":false,...}}`. Alert if `mode` is `demo` while you expect testnet (then
   `degraded` says why), or if `relayer_balance_alarm` is not `null`. Use it as the load balancer / uptime probe.
6. **Kill switch.** `curl -X POST $API/v1/admin/pause -H "x-admin-token: $ADMIN_TOKEN" -d '{"paused":true}'`
   stops all writes (`FORBIDDEN`) until you send `{"paused":false}`. Reads keep working.
7. **Clock.** Either set `PHASE_SECS`, or advance by hand with `POST /v1/admin/advance` and the same header.
8. **Smoke test.** `scripts/cors_check.sh https://YOURUSER.github.io` against a local build, then open the Pages site and
   play a guest session.

State (players, nonces, ledgers) is held in memory; a restart resets demo state. On testnet the contract keeps the
authoritative balances and nonces (the runner re-syncs a player's nonce from `nonce_of` when they sign in).

## Security notes

Signed acts are verified here and again by the contract (domain `sokokuu/v1|chain|contract|pubkey|nonce|expiry|action_json`).
Only `act`, `advance_clock` and `rebind_key` are ever relayed. Rate limits: 60 writes/min per key, 120 requests/min per
IP, 3 emails/hour per address, 100 new accounts per day. Tokens are single use, bound to the registering key, valid
10 minutes and stored hashed; emails are stored only as hashes and masked in logs. There are no cash-out, transfer or
buy-points routes. See `docs/SECURITY_UX.md`.
