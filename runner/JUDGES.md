# Soko Kuu runner: notes for judges

API base: `https://app.chukua.xyz` (the runner, behind nginx/HTTPS). Contract on NEAR testnet: `sokokuu.sokokuu-ken.testnet`.
Full contract between app and runner: `docs/API.md`; exact JSON shapes: `runner/SHAPES.md`.

## What the runner is
A small Rust (axum) service between the Flutter app and the NEAR contract. Players sign each action with their own
ed25519 key in the app; the runner checks the signature, nonce and expiry, then pays the gas and relays the call.
It also serves reads (prices, news, ledger, reports) and runs the merchant decision loop and the game clock.

## What it does NOT do
- **No cash-out, withdrawal, transfer, token, prize or paid-randomness endpoints exist.** Points are non-transferable and
  have no money value. The full route list is below; there is nothing that moves value out of the game.
- **It relays only three contract methods:** `act` (a player's signed action), `advance_clock` (the game clock) and
  `rebind_key` (key recovery after email login). Nothing else is ever submitted with the relayer key. The relayer key
  should be a function-call key limited to those three methods on this one contract.
- **Prices are rule-based code** (the `econ` crate: pricing curve, events, chama and credit rules). The optional LLM may
  only write short voice lines. `LLM_PROVIDER=none` is the default and is what is deployed (`/v1/health` shows
  `"llm_provider":"none"`).
- **No plain emails stored.** Only SHA-256 hashes of emails are kept; login links are single use, expire in 10 minutes,
  are bound to the requesting public key and are stored hashed. `DELETE /v1/auth/account` removes the binding.
- **18+ gate:** a guest or email account is created only with `age_confirmed: true` (and `consent: true` for email).
- **Rate limits:** 60 writes/min per public key, 120 requests/min per IP, a cap on login emails per hour and on new
  accounts per day. Exceeding returns `RATE_LIMITED` with `retry_after_s`.
- A kill switch (`/v1/admin/pause`) and manual clock exist behind a secret admin token; they are not usable without it.

## Endpoints
| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/v1/health` | none | version, mode, contract id, clock, degraded and balance alarms |
| GET | `/v1/state?pubkey=` | none | one player's state (needs a pubkey from a guest login) |
| GET | `/v1/prices` | none | ask/bid/stock per merchant and good, with `why[]` explanations |
| GET | `/v1/news` | none | Radio Soko items |
| GET | `/v1/chamas`, `/v1/chama/{id}` | none | chama discovery and detail |
| GET | `/v1/ledger?pubkey=&day=` | none | itemised day ledger with causes |
| GET | `/v1/report?pubkey=` | none | economy report: faucets, sinks, price index, supply drift |
| GET | `/v1/leaderboard` | none | personal bests and chama ranking (no cash-style board) |
| GET | `/v1/events?since=` | none | 25 s long-poll of news, price, vote and loan events |
| POST | `/v1/auth/guest` | age gate | create a guest from a public key |
| POST | `/v1/auth/register`, `/v1/auth/confirm` | consent | email magic-link upgrade |
| DELETE | `/v1/auth/account` | signed | delete email binding and personal data |
| POST | `/v1/act`, `/v1/act_batch` | signed | the only write path; relayed to the contract |
| POST | `/v1/sim` | none | deterministic what-if simulation (changes nothing) |
| POST | `/v1/admin/advance`, `/v1/admin/pause` | admin token | operator only |

## Curl commands (read-only, safe to run)
Every reply is JSON `{"ok":true,"data":...}` or `{"ok":false,"error":{"code","message"}}`. Game errors use HTTP 400
(unknown player 404, rate limit 429). Verified locally against a demo-mode build of this exact binary (2026-11-10):
all commands below returned the outputs described. Not verifiable until deployed (run on the live domain): `"mode":"testnet"`
and `"degraded":null` in health, the real contract id, `tx_hash` values, and the HTTPS/CORS checks.
```
API=https://app.chukua.xyz

# health: expect "ok":true, "llm_provider":"none"; live: "mode":"testnet", "degraded":null (demo locally)
curl -s $API/v1/health

# prices with the explanation of each factor
curl -s $API/v1/prices

# Radio Soko news
curl -s $API/v1/news

# chamas, leaderboard, economy report (money supply vs target, drift in basis points)
curl -s $API/v1/chamas
curl -s $API/v1/leaderboard
curl -s $API/v1/report

# deterministic simulation: same input, same output; nothing is written anywhere
curl -s -X POST $API/v1/sim -H 'content-type: application/json' \
  -d '{"seed":1,"days":10,"events":[{"day":3,"kind":"ukame","magnitude":40}]}'

# the 18+ gate is enforced: refused with FORBIDDEN "Players must confirm they are 18 or older." (HTTP 400)
curl -s -X POST $API/v1/auth/guest -H 'content-type: application/json' \
  -d '{"pubkey":"ed25519:11111111111111111111111111111111","age_confirmed":false}'

# there is no cash-out: any such path is a 404
curl -s -o /dev/null -w '%{http_code}\n' $API/v1/withdraw

# admin endpoints refuse without the token (FORBIDDEN, "Bad admin token", HTTP 400)
curl -s -X POST $API/v1/admin/advance

# state of a player: an unknown pubkey gives NOT_MEMBER (HTTP 404); a pubkey from a guest login gives the state
# (locally: a guest got pts 20000, nonce 0, phase dawn)
curl -s "$API/v1/state?pubkey=PUBKEY_FROM_THE_APP"
```
Every relayed action returns a `tx_hash` that can be checked at `https://testnet.nearblocks.io/txns/<tx_hash>`. The contract's
views can be read straight from NEAR testnet RPC without the runner, for example `clock` and `world_hash`.
