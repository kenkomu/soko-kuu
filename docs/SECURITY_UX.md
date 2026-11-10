# Security, made simple

Principle: players see no passwords, seed phrases, wallets or popups. Security lives in 8 rules the system enforces
for them. Testnet, no real money; this is a checklist, not an audit.

## The 8 rules (all must ship)
| # | Rule | What it stops | Owner |
|---|---|---|---|
| 1 | Every action is signed. Signed bytes = `sokokuu/v1`, chain id, contract id, pubkey, nonce, expiry, and the exact `action_json` string. Nonce must be higher than the last; expiry 2 min. | Replay, tampering, cross-chain reuse | app, contract |
| 2 | **The contract is the referee.** It re-checks signature, price bound, stock, credit limit and reputation on every action. The app and runner can ask, never decide. Integer maths only. | A modified app or a buggy runner | contract, econ |
| 3 | **Points never leave.** `mt_transfer` panics for `pts` and player ids; no withdraw or transfer route exists. | Breaking the closed-loop and no-cash-out claim | contract |
| 4 | Relayer guard: relays only `act`, gas cap per call, 60 writes/min per pubkey, 120 requests/min per IP, one kill switch. | Gas drain and spam | runner |
| 5 | Login without passwords. Guest first. Magic link is bound to the requesting key, single use, 10 min, stored hashed. New device: new key, old key revoked at once. | Link theft, account takeover | runner |
| 6 | Secrets and transport: nothing secret in git (`.env.example` only, secret scan in CI), HTTPS, exact CORS origin, merchant keys scoped to `decide` and `crank`. | Key leaks, cross-site abuse | all |
| 7 | AI is boxed in: off by default, never sees player text, returns only bounded JSON the contract clamps. | Prompt injection, price manipulation | runner |
| 8 | Minimal personal data: email only, consent, delete route, 18+ gate before any account, emails hashed in logs. | Privacy and Data Protection Act exposure | runner, app |

## Skipped on purpose (cost more than they protect on testnet)
- 24 h key cool-down, account-per-day caps, guest leaderboard delay: add after the hackathon.
- Nonce gap windows and per-action risk scoring.
- Hardware-backed web keys: web keys are throwaway demo keys, and the app says so.
- Full audit and formal verification: say "not audited" in the README.

## Cheap extras (do only if each takes under 30 minutes)
- `cargo audit` and `flutter pub outdated` in CI.
- Guarantor loses reputation if the borrower defaults.
- Owner-only pause on write methods.

## Easy to use, by design
- No password, seed phrase, wallet or popup. Ever.
- Guest play in about 20 seconds; email only to save progress or join a chama.
- One tap to act. Confirm only for large trades. Slippage bound is automatic, not a setting.
- Every error is one friendly sentence in English and Swahili, with what to do next.
- Guests lose progress if they clear app data; the app says so once.
- Home screen line: "Points are for play only. They can't be cashed out."

## Efficient by design
- Reads come from the runner's in-memory copy; the chain is written to only on actions.
- ETag/304 and 3 s cache on prices and news; gzip; one `/v1/events` call instead of many polls.
- App shows the result at once (`state_delta`) and confirms in the background.
- Offline demo mode, so a slow network or testnet outage never blocks a judge.

## Seven tests for day 1
1. Replay a signed action: rejected. Change one byte of `action_json`: rejected.
2. Use the signature against another contract id: rejected.
3. Send 100 requests in 10 s from one pubkey: rate limited; relayer balance unchanged after.
4. Call `mt_transfer` on `pts`: panics. Search routes for withdraw or transfer: none.
5. Magic link with a different pubkey: rejected. Second use: rejected.
6. Offline start loads in under 3 s on a mid-range Android phone.
7. A first-time player makes a first sale in under 90 s without reading anything.
