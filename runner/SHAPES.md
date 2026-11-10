# Soko Kuu runner: JSON shapes

Real field names and examples, captured from the Rust runner (`cargo test dump_shapes -- --ignored` regenerates them).
`docs/API.md` is the contract; this file is the exact payloads. All money is integer pts. Prices and the price index are
integers (index is in basis points: 10000 = 100% of the reference basket).

Envelope on every response: `{"ok":true,"data":...}` or `{"ok":false,"error":{"code","message","retry_after_s"?}}`.
HTTP status: 200 ok, 304 (reads with matching `If-None-Match`), 400 rule errors, 404 unknown pubkey/chama/route,
429 `RATE_LIMITED` (also sets `Retry-After`). Reads send `ETag` and `Cache-Control: private, no-cache`; responses are gzip
when the client sends `Accept-Encoding: gzip`.

## Signed writes

`POST /v1/act` body (the signed string is sent exactly as signed; nothing is re-encoded):
```json
{ "pubkey": "ed25519:...", "nonce": 3, "expires_ms": 1770000060000,
  "action_json": "{\"type\":\"buy\",\"merchant\":\"njeri\",\"good\":\"tomato\",\"qty\":3,\"max_unit_price\":3900}",
  "sig": "base64" }
```
Signed bytes: `sokokuu/v1|<chain_id>|<contract_id>|<pubkey>|<nonce>|<expires_ms>|<action_json>`.
Rules: nonce strictly greater than the last accepted nonce; `expires_ms` within 2 minutes of runner time; a rejected action
never consumes the nonce. Action fields: `buy{merchant,good,qty,max_unit_price}`, `sell{merchant,good,qty,min_unit_price?}`,
`haggle{merchant,good}`, `chama_create{}`, `chama_join{chama_id}`, `chama_vote{offer_id,vote:"yes"|"no"}`,
`credit_request{merchant,good,qty}`, `credit_repay{loan_id}`, `guarantee{borrower,loan_id}`, `invest{merchant,pts}`, `advance{}`.

Response (`data`):
```json
{ "tx_hash": "demo:1aa2612434fae879dfbd043c223adc30f9031315e561",
  "state": { "...full /v1/state object after the action..." },
  "state_delta": { "nonce": 3, "pts": 8280, "pts_change": -9720, "stock": {"tomato": 3}, "stock_change": {"tomato": 3} },
  "events": [ {"type":"info","text":"..."} ] }
```
`state` is authoritative. `state_delta` lists the changed top-level fields plus `pts_change` (signed) and `stock_change`
(signed per good). `tx_hash` is `demo:<hex>` in demo mode or a NEAR transaction hash.

Error example: `{"ok":false,"error":{"code":"PRICE_MOVED","message":"Action refused by market rules"}}`.

`POST /v1/act_batch` body `{"actions":[<same object as /v1/act>, ...]}` (1 to 10, run in order, stops at the first failure).
Always HTTP 200 when the batch was understood:
```json
{ "results": [ {"ok":true,"data":{"tx_hash":"...","state":{...},"state_delta":{...},"events":[]}},
               {"ok":false,"error":{"code":"NOT_ENOUGH_STOCK","message":"..."}} ],
  "completed": 1, "stopped_at": 1, "state": { "...state after the last successful action, or null..." } }
```
`stopped_at` is the index of the failed action, or `null` when all succeeded. Each action is verified, rate-limited and
relayed on its own (the contract has no batch method yet, so there is one chain call per action).

## Login
- `POST /v1/auth/guest` `{pubkey, age_confirmed:true}` -> `{"player_id":"p5fc0171d"}`. Without `age_confirmed:true`: `FORBIDDEN`.
  Idempotent per key. Guests stay off the personal leaderboard until game day 3 or until they verify an email.
- `POST /v1/auth/register` `{email, pubkey, consent:true}` -> `{"sent":true}` (plus `dev_token` only in demo mode with
  `DEV_RETURN_TOKEN=1`). Max 3 emails/hour per address (`EMAILS_PER_HOUR`) (`RATE_LIMITED` + `retry_after_s`).
- `POST /v1/auth/confirm` `{token, pubkey}` -> `{"player_id":"..."}`. Token: bound to the registering pubkey (other key:
  `BAD_SIG`), single use, 10 minutes, stored hashed (bad/used/expired: `EXPIRED`).
  A guest key upgrades its own player. A new key with an email that already has an account joins that same player; the
  older keys are revoked at once (`NOT_MEMBER`). On testnet the runner first calls the contract's relayer-only `rebind_key(old_pubkey, new_pubkey)`; if the contract refuses, the new key is not accepted. A guest that already has its own player cannot claim someone else's email.
- `DELETE /v1/auth/account` body `{pubkey, nonce, expires_ms, sig}`; signed with `action_json` = `{"type":"delete_account"}`.
  Forwarded to the contract (consumes a nonce); on success all keys and the email binding are removed -> `{"deleted":true,"player_id":"..."}`.

## GET /v1/state?pubkey=
```json
{ "player_id": "p5fc0171d", "nonce": 6, "day": 0, "phase": "midday", "next_phase_ms": null,
  "pts": 8280, "stock": {"fish": 1, "tomato": 3},
  "reputation": {"tier": "mgeni", "tier_index": 0, "score": 0},
  "credit": {"limit": 2132, "outstanding": 6868, "tier_limit": 9000},
  "loans": [ {"id": 2, "merchant": "njeri", "good": "fish", "qty": 1, "principal": 6480, "owed": 6868, "interest_pct": 6,
              "due_day": 5, "guarantor": null, "lender": "merchant", "lender_id": "njeri"} ],
  "chama_id": "c1" }
```
- `phase`: `dawn` | `midday` | `dusk`. `day` starts at 0. `nonce` is the last accepted nonce (next act sends a greater one).
- `next_phase_ms`: epoch ms when the relayer clock moves next, or `null` when no timer is configured (`PHASE_SECS`).
- `reputation.tier`: `mgeni`, `mfanyabiashara`, `mzoefu`, `mzee_wa_soko` (tier_index 0..3).
- `credit.limit` = tier limit minus outstanding. `loans[].lender` is `merchant` (6%) or `chama` (4%), `lender_id` its id; loans run 5 days.
- Unknown pubkey: HTTP 404, `NOT_MEMBER`.

## GET /v1/prices
```json
{ "day": 0, "phase": "midday", "price_index": 10025, "price_index_bp": 10025,
  "merchants": { "njeri": { "name": "Njeri", "voice": "Njeri: Karibuni sokoni!",
      "goods": { "tomato": { "ask": 3386, "bid": 2884, "stock": 37, "history": [3240, 3386],
                             "why": ["tomato is scarce at this stall, so the price is 4% above normal."] } } } },
  "items": [ {"merchant":"njeri","good":"tomato","ask":3386,"bid":2884,"stock":37,"history":[3240,3386],"why":["..."]} ] }
```
Merchants: njeri, otieno, wanjiru, hassan. Goods: tomato, maize, sukuma, onion, fish, charcoal. `history` is up to 30 daily
asks, oldest first; the last entry is the live ask. `voice` is a fixed template (`LLM_PROVIDER=none`). `items` repeats the same data flat.
Server-side cached for 3 s (cache is dropped on any state change).

## GET /v1/news
`{"items":[{"text":"Soko Kuu imefunguliwa. Karibuni sokoni!","day":0,"kind":"festival"}]}`, newest first, max 50.
`kind`: `ukame` `fuel` `road` `festival` `harvest` `glut`.

## GET /v1/chamas (discovery)
`{"items":[{"id":"c1","members":4,"max_members":8,"join_share":2000,"cash":8000,"open_offer":true}],"join_share":2000}`
Lists chamas with room. Public, no signature.

## GET /v1/chama/{id} (public for any existing chama; unknown id: 404 `NOT_MEMBER`)
```json
{ "id": "c1", "members": ["p04e06fca","p21d3f1fc","p5fc0171d","pacce94df"],
  "shares": {"p04e06fca": 2000, "p21d3f1fc": 2000, "p5fc0171d": 2000, "pacce94df": 2000}, "cash": 8000,
  "offer": { "id": 3, "borrower": "p5fc0171d", "merchant": "njeri", "good": "sukuma", "qty": 6, "cost": 7776, "owed": 8087,
             "deadline_day": 1, "votes": {"p21d3f1fc": "yes"} },
  "votes": {"p21d3f1fc": "yes"}, "deadline_day": 1 }
```
Chama flow (all via `POST /v1/act`, any phase): `{"type":"chama_create"}` -> state.chama_id `"c1"` (creator pays the 2000 join share);
others `{"type":"chama_join","chama_id":"c1"}` (max 8 members; the list `GET /v1/chamas` shows only chamas with room, `[]` before any exists).
An offer opens on its own when a `credit_request` at midday exceeds the player's personal credit limit and the chama has the cash
(needs about 4 members); `/v1/chamas` item then has `open_offer:true`. Members other than the borrower send
`{"type":"chama_vote","offer_id":<offer.id>,"vote":"yes"|"no"}`; `offer.votes` fills as `{player_id:"yes"}`, and once a majority of the
other members decide the offer becomes `null` and, if approved, a 4% `lender:"chama"` loan appears in the borrower's `/v1/state`.
Errors: second vote `ALREADY_VOTED`; borrower voting `WRONG_PHASE`; no chama `NOT_MEMBER` ("You need to be in a chama for that");
unknown chama id on join `NOT_MEMBER` ("unknown chama"); unknown merchant `NOT_MEMBER` ("unknown merchant"; midday only, as the phase is checked first).
`offer`, `votes` and `deadline_day` are `null`/empty when no offer is open. The borrower cannot vote; a majority of the other members decides.

## GET /v1/ledger?pubkey=&day=
```json
{ "day": 0, "entries": [ {"day":0,"phase":"midday","kind":"buy","delta":-9720,"cause":"bought 3 tomato from njeri at 3240","balance":8280} ] }
```
`kind`: `onboard` `buy` `sell` `haggle` `chama` `credit` `repay` `guarantee` `invest` `advance` `settlement` (daily
allowance, repayments, contributions). `day` defaults to today.

## GET /v1/report?pubkey=
```json
{ "day": 0, "window": "season", "faucets": {"daily_allowance": 0}, "sinks": {"fees_and_rent": 0}, "treasury": 0,
  "price_index": 10025, "price_index_bp": 10025, "money_supply": 560000, "target_supply": 560000, "drift_bp": 0,
  "merchants": [ {"id":"njeri","name":"Njeri","cash":129720,"solvent":true,"stock":{"tomato":37}} ], "solvent_merchants": 4,
  "score": {"net_worth": 14912, "best": 20000, "reputation": 0} }
```
`score` is `null` unless `pubkey` is given and known. `drift_bp` is supply drift versus target in basis points.

## GET /v1/leaderboard
`{"personal":[{"player_id":"p04e06fca","best_net_worth":20000}],"chamas":[{"chama_id":"c1","members":4,"score":76912}]}` (top 20 each;
no global cash-style board; unverified guests hidden for their first 3 game days).

## GET /v1/health
`{"version":"0.2.0","chain_id":"testnet","contract_id":"sokokuu.testnet","mode":"demo","degraded":null,"llm_provider":"none","day":0,"phase":"midday","next_phase_ms":null,"paused":false,"relayer_balance_alarm":null,"chain_drift":null}`
`mode` is `testnet` or `demo`; `degraded` is a message when testnet fell back to demo; `relayer_balance_alarm` is a message when the relayer's NEAR balance is below `MIN_BALANCE_NEAR` (default 5), else `null`. `chain_drift` is a message (testnet only) when the contract's balance for a player differed from the runner's mirror after a relayed act, else `null`.

## GET /v1/events?since=<id> (long-poll, 25 s; `EVENTS_WAIT_MS` overrides)
```json
{ "events": [ {"id":1,"kind":"phase","day":0,"data":{"day":0,"phase":"midday","price_index":10000}} ],
  "last_id": 1, "day": 0, "phase": "midday" }
```
Kinds: `phase` (clock moved), `news` (data = a news item), `chama_vote` (`{chama_id,offer_id,player_id}`),
`loan_reminder` (`{player_id,loan_id,due_day,owed}`, sent when a loan is due within a day). Returns at once if there are
events with `id > since`, otherwise waits up to the limit and returns an empty list. Send `last_id` as the next `since`.

## POST /v1/sim `{seed, days, events:[{day,kind,magnitude}]}`
`days` 1..120; `magnitude` 1..100 percent; `kind` one of the six news kinds. Same input gives the same output. Frames come
straight from the econ crate (basis points):
`{"seed":1,"days":2,"frames":[{"day":1,"supply":717494,"drift_bp":-34,"price_index_bp":10118,"minted":336,"burned":2842,"treasury":31000,"solvent_merchants":4,"open_loans":0,"defaults":0,"events":[]}]}`

## Clock and relayer rules
- The relayer owns the clock. `PHASE_SECS=n` runs a timer that advances one phase every n seconds (demo and testnet);
  `POST /v1/admin/advance` (header `x-admin-token`, env `ADMIN_TOKEN`) advances once. Both call the contract's relayer-only
  `advance_clock()` on testnet.
- Testnet: a player-signed `advance` is rejected with `FORBIDDEN` and does not consume the nonce. Demo: players may advance,
  with a per-player cooldown (`ADVANCE_COOLDOWN_MS`, default 1500; `RATE_LIMITED`).
- Kill switch: `POST /v1/admin/pause` `{paused:true|false}` (same admin header). While paused every write returns `FORBIDDEN`.
- Trading (`buy` `sell` `haggle` `credit_request` `invest`) works only at `midday` (`WRONG_PHASE` otherwise).

## Limits
60 writes/min per pubkey, 120 requests/min per IP (`IP_RPM`; `TRUST_PROXY=1` reads the last `X-Forwarded-For`),
20 sign-in calls/min per IP, 3 emails/hour per address, 300 players, and `MAX_NEW_ACCOUNTS_PER_DAY` (default 100) new accounts per UTC day (guest or verified; `RATE_LIMITED` + `retry_after_s` until midnight UTC). All return `RATE_LIMITED` with `retry_after_s`.
