# Soko Kuu API v1 (contract between the app and the runner)

Android and web apps talk ONLY to this HTTPS JSON API. They never call NEAR directly.
The runner verifies, submits to the NEAR contract, pays gas, and returns state.
Status: DRAFT. Changes need agreement from `app` and `runner` owners.

## Conventions
- Base URL from build config (`API_BASE`). CORS must allow the Pages origin and localhost.
- Money is integer points (`pts`), never floats. Prices are integer pts per trade unit.
- Every response: `{ "ok": true, "data": ... }` or `{ "ok": false, "error": { "code", "message" } }`.
- Error codes: `BAD_SIG`, `BAD_NONCE`, `EXPIRED`, `NOT_ENOUGH_PTS`, `NOT_ENOUGH_STOCK`,
  `CREDIT_DENIED`, `NOT_MEMBER`, `ALREADY_VOTED`, `WRONG_PHASE`, `PRICE_MOVED`, `FORBIDDEN`, `RATE_LIMITED`, `INTERNAL`.
  `FORBIDDEN`: the caller is not allowed to do this (e.g. a player-signed `advance` on testnet).
  `PRICE_MOVED`: the quote moved past the player's `max_unit_price` (buy) or `min_unit_price` (sell).
- A rejected action does not consume the nonce.
- Exact JSON field names and example payloads for every read are in `runner/SHAPES.md`.

## Login (no wallet)
Guest first, email later. A new player can play immediately; email is asked only when they want to save progress,
join a chama, or recover on another device.
1. App creates an ed25519 key and stores it (secure storage; IndexedDB on web = throwaway demo key).
2. `POST /v1/auth/guest` `{ pubkey, age_confirmed: true }` -> `{ player_id }`. 18+ gate happens before this call.
   The first act by a new key registers the player with 20,000 pts (the only starting grant).
3. Upgrade: `POST /v1/auth/register` `{ email, pubkey, consent: true }` -> magic link. The link token is bound to
   that exact `pubkey`, single use, expires in 10 minutes, and is stored hashed.
4. `POST /v1/auth/confirm` `{ token, pubkey }` -> `{ player_id }`. Fails with `BAD_SIG` if pubkey differs from step 3.
5. Lost or new device: register the new pubkey with the same email via the magic link. The old key is revoked at once.
6. `DELETE /v1/auth/account` removes the email binding and personal data. Body `{ pubkey, nonce, expires_ms, sig }`;
   the signature covers the normal signed bytes with `action_json` = `{"type":"delete_account"}`. It consumes a nonce
   and is forwarded to the contract as a signed no-op, so the runner and contract nonces stay aligned.

## Reads (no signature)
| Method | Path | Returns |
|---|---|---|
| GET | `/v1/health` | version, chain id, contract id, mode (`testnet` or `demo`) |
| GET | `/v1/state?pubkey=` | `player_id`, `nonce` (last accepted; the next act must send a greater nonce; nonce + 1 is the normal case), day, phase (`dawn` `midday` `dusk`), `next_phase_ms` (when the relayer will advance the clock), pts, stock, `reputation {tier, score}`, credit limit, open loans (each with interest and due day), chama id |
| GET | `/v1/prices` | per merchant and good: ask, bid, stock, `why[]` (factor breakdown sentences) |
| GET | `/v1/news` | Radio Soko items: text, day, kind (`ukame` `fuel` `road` `festival` `harvest` `glut`) |
| GET | `/v1/chama/{id}` | members, shares, cash, open offer, votes, deadline |
| GET | `/v1/ledger?pubkey=&day=` | itemised day ledger with causes |
| GET | `/v1/report?pubkey=` | season / week Soko Report: faucets, sinks, price index, merchant solvency, score |
| GET | `/v1/leaderboard` | personal best and chama rankings (no global cash-style board) |

## Writes: one endpoint
`POST /v1/act`
```json
{ "pubkey": "ed25519:...", "nonce": 42, "expires_ms": 1770000000000,
  "action_json": "{\"type\":\"buy\",\"merchant\":\"njeri\",\"good\":\"tomato\",\"qty\":3,\"max_unit_price\":3900}",
  "sig": "base64" }
```
Signed bytes = UTF-8 of: `sokokuu/v1|<chain_id>|<contract_id>|<pubkey>|<nonce>|<expires_ms>|<action_json>`.
`action_json` is a STRING: the app signs the exact bytes it sends and the contract parses those same bytes. No
canonicalisation step, so no ambiguity. The contract re-verifies with `env::ed25519_verify`.

Replay and ordering rules:
- `nonce` must be strictly greater than the last accepted nonce for that pubkey (the contract stores it).
- `expires_ms` must be within 2 minutes of the contract's block time (or runner time in demo mode).
- Signature domain includes chain id and contract id, so a testnet signature is useless anywhere else.

Action types and fields:
- `buy` `{ merchant, good, qty, max_unit_price }`
- `sell` `{ merchant, good, qty, min_unit_price? }` (`min_unit_price` optional)
- `haggle` `{ merchant, good }`
- `chama_create` `{}`, `chama_join` `{ chama_id }`, `chama_vote` `{ offer_id, vote: "yes"|"no" }`
- `credit_request` `{ merchant, good, qty }`, `credit_repay` `{ loan_id }`
- `guarantee` `{ borrower, loan_id }`, `invest` `{ merchant, pts }`
- `advance` `{}` (move to next phase): on testnet the relayer drives the clock; a player-signed `advance` is rejected
  with `FORBIDDEN` and does not consume the nonce. In `demo` mode players may advance (with a cooldown).

Every price-affecting action carries a slippage bound (`max_unit_price` or `min_unit_price`); the contract rejects
with `PRICE_MOVED` if the live quote is worse.

Phases: `buy`, `sell`, `haggle`, `credit_request` and `invest` only work at `midday` (otherwise `WRONG_PHASE`).
Chama actions, `credit_repay` and `guarantee` work in any phase.
Credit: a loan runs 5 days; interest is 6% from a merchant and 4% from a chama.

Response: `{ tx_hash, state, events[] }`, where `state` is the full `/v1/state` object after the action (the app may
still apply it optimistically and reconcile on the next `/v1/events` tick).

`POST /v1/act_batch` (optional, build last) takes up to 10 signed actions in order (e.g. a whole dawn shopping list) as one request, one
relayer submission, one gas bill. Each action is verified separately; the batch stops at the first failure.

## Limits, caching and updates
- Rate limits: 60 writes/min per pubkey and 120 requests/min per IP. Exceeding returns `RATE_LIMITED` with `retry_after_s`.
- Reads send `ETag`; the app sends `If-None-Match` and gets `304` when nothing changed. `/v1/prices` and `/v1/news`
  are cached for 3 s server-side. Responses are gzip-compressed.
- `GET /v1/events?since=<id>` (long-poll, 25 s) returns new news, price changes, chama votes and loan reminders in
  one call, so the app does not poll every endpoint. SSE may replace this later; the payload stays the same.
- The app applies the `state` returned by `/v1/act` optimistically and reconciles on the next `/v1/events` tick. Do not block the UI on
  chain finality.

## Simulation and demo
- `POST /v1/sim` `{ seed, days, events:[{day,kind,magnitude}] }` -> frames for fast-forward animation.
- Same API in `mode: demo`: runner backed by an in-memory fake ledger, seeded, deterministic. Used by `make demo`
  and as the fallback when testnet or relayer is down.

## Rules the app must respect
- No cash-out, withdraw, transfer or buy-points endpoints exist. Do not add them.
- Never show the words wallet, token, stake, odds, jackpot. Currency name is "pointi (pts)".
- 18+ gate on first run, before any key or account is created.
- Human error messages: the app maps every error `code` to one plain sentence in English and Swahili.
