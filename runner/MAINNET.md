# Moving the runner to NEAR mainnet (after judging; notes only)

Mainnet is not needed for the hackathon, and nothing here is implemented. On mainnet the operator pays gas in real NEAR. The
game itself does not change: points stay non-transferable, and there is still no cash-out, token, prize or paid randomness.

## 1. Config (env file, no code)
| Env | Testnet today | Mainnet |
|---|---|---|
| `CHAIN_ID` | `testnet` | `mainnet`. It is part of every signed message |
| `CONTRACT_ID` | `sokokuu.sokokuu-ken.testnet` | The new mainnet contract |
| `RELAYER_ACCOUNT_ID`, `RELAYER_KEY_FILE` | testnet relayer | The mainnet relayer and its function-call key file (section 3) |
| `NEAR_RPC_URL` | unset, so it defaults to `rpc.testnet.near.org` | Must be set: the default points at testnet. Use a provider with an API key (section 2.4) |
| `DEMO_SEED` | 1 | Must equal the seed the mainnet contract was initialised with |
| `GAS_TGAS` | 100 | Measure the largest `act` burn on mainnet, then set about 2x that |
| `PHASE_SECS` | 600 | Set it from the budget: every clock step is one paid transaction (section 4) |
| `MIN_BALANCE_NEAR` | 0.5 | About 7 days of spend |
| `MAX_NEW_ACCOUNTS_PER_DAY`, `IP_RPM` | 100, 120 | Lower at launch (section 5) |
| `CORS_ORIGINS`, `PUBLIC_CONFIRM_URL`, `MAIL_WEBHOOK_URL` | Pages, log-only mail | Production origin and a real mail provider |
| `MODE` | `testnet` | Stays `testnet`: in the code that name means "real chain" (section 2.3) |

## 2. Runner code changes
1. **Chain id check at start.** The signed bytes are `sokokuu/v1|<chain_id>|<contract_id>|<pubkey>|<nonce>|<expires_ms>|<action_json>`,
   built the same way in the app (`app/lib/core/signing.dart`), the runner (`rs/src/sig.rs`) and the contract. The app takes
   `chain_id` and `contract_id` from `/v1/health`, so it follows the runner, and a testnet signature cannot be replayed on
   mainnet. But if `CHAIN_ID` differs from the contract's `chain_id` view, every action fails with `BAD_SIG`. The runner
   should read that view at start and refuse to start on a mismatch.
2. **Fail closed, do not fall back to demo.** Today any relayer or RPC error switches the runner to demo mode (a local ledger
   with `demo:` tx hashes) until restart. That suits a judged testnet demo. On mainnet it would show players fake confirmations.
   Instead, the runner should refuse writes with a clear error, keep serving reads, retry the chain with backoff, and recover
   without a restart.
3. **Mode naming.** Real-chain mode is called `testnet` in `MODE`, in the cargo feature and in the `/v1/health` `mode` field.
   Add `mainnet`, or rename it to `chain`. The `mode` field is part of `docs/API.md`, so message `runner` and `app` first.
4. **RPC.** `rpc.mainnet.near.org` is rate-limited: a status call took ~3.7 s on 14 Nov, against ~0.7 s on
   `free.rpc.fastnear.com`. Support a primary URL plus a fallback list, and an API-key header if the provider needs one. The
   key goes in the env file only. **Fix this first:** today a transport error copies up to 120 characters of the raw error
   text, request URL included, into the public `/v1/health` `degraded` field (`rs/src/app.rs`, `submit` and its siblings).
   A key in the URL would therefore be published. Keep a fixed message in `degraded` and put the detail in the log only.
   The test `chain_outage_text_is_not_leaked_to_clients_or_health` covers this, but until econ change A it passed without
   reaching the chain, so it never really exercised the redaction.
5. **Spend guard.** Add a daily relayer spend cap (the sum of gas burnt, read from tx outcomes) that pauses player writes when
   it is reached, and a per-player daily write cap. Put the key allowance, contract storage headroom and today's spend in
   `/v1/health`; today it shows only the relayer balance.
6. **Throughput.** Today the runner uses one access key and `broadcast_tx_commit`, and holds one global lock across the chain
   call, so reads wait for an in-flight act (see the ignored test in `tests/hardening.rs`). That is about one transaction at a
   time, 1 to 3 s each. For real traffic: a pool of function-call keys (one nonce lane each), `send_tx` with `wait_until`, and
   no lock held across RPC calls.
7. **Explorer links.** Change `testnet.nearblocks.io` to `nearblocks.io` in the docs and the app.

## 3. Keys and permissions
- **Relayer hot key**: a function-call key only. Receiver: the contract. Methods: `act,advance_clock,rebind_key`. Allowance:
  about 2 weeks of spend, which caps what a stolen VPS key can burn. Unused prepaid gas is refunded to the allowance (on
  testnet the balance and the allowance fell by the same 0.144 NEAR).
- **Relayer cold key**: keep one full-access key for the relayer account offline, on a hardware wallet. On testnet that key
  was deleted, which turns the allowance into a hard cap: once it is used up the key can never be renewed. Keep the cold key so
  you can renew the allowance and rotate keys (add the new key, restart, delete the old key). Alternatively, give the contract
  an owner-only `set_relayer`.
- **Contract account**: keep the owner and upgrade key offline (or use a multisig). No contract keys go on the VPS. The owner
  `pause` exists as a second kill switch.
- **Key file**: `/etc/sokokuu/relayer.key`, mode 600, owned by the `sokokuu` user, never in git.
- **Merchant keys** (`decide`, `crank`): the runner relays neither today. If the merchant loop ever writes on mainnet, use
  separate function-call keys scoped to those methods only.
- **Admin token**: long and random, kept in the env file only. Also restrict `/v1/admin/*` to known IPs in nginx.

## 4. Funding and daily cost
Gas price on 14 Nov 2026 was 100,000,000 yoctoNEAR/gas on both networks: the protocol minimum, which is 0.0001 NEAR per Tgas
burnt. It rises when blocks are full, so budget 2x.
- Clock: about 0.00027 NEAR per `advance_clock`. At `PHASE_SECS=600` that is 144 calls/day, or 0.039 NEAR/day (~1.2 NEAR/month).
  At 1800 it is 0.013 NEAR/day.
- Player actions: up to about 0.002 NEAR each (the worst case in `contract/DEPLOY.md`). 1,000 actions/day comes to about 2 NEAR/day.
  The runner applies each action to its mirror before relaying, so most refusals cost nothing. A refusal that only the
  contract catches still burns gas.
- Rule of thumb: `NEAR/day = 0.039 x 600/PHASE_SECS + 0.002 x actions/day`, plus key rebinds.
- Measured on testnet: 0.144 NEAR over the first ~4 days (about 0.038 NEAR/day) with light play.
- Relayer: hold a balance of 30 days of spend, and set the allowance to about 14 days, renewed with the cold key.
- Contract storage (the contract owner funds it; this runner should monitor it): about 1 NEAR per 100 KB. The code is
  ~411 KB (~4.1 NEAR). The world grows ~0.28 KB per player (83 KB at the 300-player cap), plus per-player nonce and id maps.
  Fund at least 6 NEAR and watch the free balance.

## 5. Rate limits and abuse
On testnet, spam only burns testnet NEAR. On mainnet, every relayed action is paid for.
- Keep: 60 writes/min per key, 120 requests/min per IP, the kill switch, the new-accounts-per-day cap and the emails-per-hour cap.
- Add: a daily write cap per player (for example 200), the global spend cap with auto-pause (section 2.5), and a human check
  (a captcha, or a verified email before the first relayed write). Count each action in `act_batch` toward the caps.
- Why the spend cap is required: today's worst case is 100 new keys a day (the account cap), each making 60 writes/min from
  rotating IPs.

## 6. Monitoring
- An external uptime monitor on `/v1/health`. Alert unless the body contains `"degraded":null`, and on non-null
  `chain_drift`, a non-null `relayer_balance_alarm`, or `paused: true`.
- Alarms: relayer balance and key allowance (watch both), contract free storage balance, daily spend against the cap,
  failed-transaction rate, and clock lateness (`next_phase_ms` in the past).
- Logs: send the journald lines `ALARM`, `WARN`, `resync:` and `clock advance failed` somewhere that notifies a person.
- Weekly: back up `DATA_DIR` (`state.json`: ledgers and hashed emails), check certbot renewal, and run `cargo audit`.
- Personal data does not change: only email hashes are stored, the delete route and 18+ gate stay, and player ids on chain
  are derived from keys, not from people.

## 7. Order of the switch
1. Contract owner: deploy and initialise the mainnet contract (`chain_id: "mainnet"`, seed, relayer), then fund its storage.
2. Create the relayer account, add the function-call key with its allowance, store the full-access key offline, and fund it.
3. Runner: make the section 2 changes, write a new env file, and start it. Check that `/v1/health` shows `chain_id: mainnet`
   and the new contract id, and that the start-up chain-id check passes.
4. App: set a new `API_BASE` if the host changes, and update the explorer links. Signing does not change.
5. Soft launch with low caps, and watch spend for a week before raising them. Keep testnet running as the demo and backup.
