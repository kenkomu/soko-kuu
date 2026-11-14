# Keeping the hosted demo alive until 25 Nov 2026

Goal: `https://app.chukua.xyz` stays in `testnet` mode until Wed 25 Nov 23:59 UTC. The hard minimum is Wed 18 Nov 23:59 UTC.
Ken runs every command. "VPS" means run it on the server; "laptop" means run it anywhere. `API=https://app.chukua.xyz`.

## Snapshot: Sat 14 Nov, 06:45 UTC (read-only checks)
- Health: `mode testnet`, `degraded null`, `chain_drift null`, `relayer_balance_alarm null`, `paused false`, version 0.2.0,
  day 172 dawn. The clock steps every 10 minutes (`PHASE_SECS=600`).
- Relayer `relayer.sokokuu-ken.testnet` has a balance of **1.856 NEAR**. Its only key is a function-call key (receiver: the
  contract; methods: `act,advance_clock,rebind_key`) with an **allowance of 1.656 NEAR**. The relayer has no full-access key:
  `contract/deploy.sh` removed it on purpose.
- Both numbers have dropped by 0.144 NEAR since the 10 Nov deploy (they started at 2.0 and 1.8). That is about 0.038 NEAR/day,
  almost all of it the clock: 144 `advance_clock` calls/day at about 0.00027 NEAR each.
- Contract: 6.00 NEAR held, 395 KB of storage (391 KB of it is code), so about 2.0 NEAR is free for storage. The goods wasm
  (411 KB) needs about 0.21 NEAR more, which fits.
- The TLS certificate is valid until 8 Feb 2027 (certbot renews it). CORS allows `https://kenkomu.github.io` and refuses
  other origins.

## 1. Gas budget: watch the allowance, not the balance
The key's **allowance is the real limit**. When it reaches zero, every relay fails (`NotEnoughAllowance`) and the runner falls
back to demo mode, even if the account still holds NEAR. The relayer has no full-access key, so nobody can raise this key's
allowance. The balance stays 0.2 NEAR above the allowance, so the balance never runs out first.

| Clock only (~0.039 NEAR/day) | When |
|---|---|
| Spent by 18 Nov 23:59 | 0.18 NEAR |
| Spent by 25 Nov 23:59 | 0.46 NEAR (about 1.20 allowance left) |
| `relayer_balance_alarm` fires (balance < 0.5, allowance then ~0.3) | about 18 Dec |
| Allowance runs out | about 26 Dec |

Player actions come on top of the clock. `contract/DEPLOY.md` puts a worst-case `act` at 0.002 NEAR. The spare allowance up to
25 Nov therefore covers at least ~450 actions before the alarm fires and ~600 before the key stops. So far, real play has been
too light to show up in the burn rate.

**Daily check** (laptop). Write the number down each day; the burn is yesterday's number minus today's.
```
curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"view_access_key_list","finality":"final","account_id":"relayer.sokokuu-ken.testnet"}}' \
 | python3 -c 'import sys,json;k=json.load(sys.stdin)["result"]["keys"][0]["access_key"]["permission"]["FunctionCall"];print("allowance %.3f NEAR"%(int(k["allowance"])/1e24))'
```
A burn under 0.1 NEAR/day is fine: the key then lasts past 25 Nov with margin. If the burn is higher, or the allowance drops
below 0.5:
1. Slow the clock. On the VPS, set `PHASE_SECS=1800` in `/etc/sokokuu/runner.env`, then run
   `sudo systemctl restart sokokuu-runner`. The clock then costs 0.013 NEAR/day, and a game day takes 90 minutes instead of 30.
2. If spam is the cause, use the kill switch (section 3, step 2). It stops player writes; the clock keeps running.
3. Ask the contract owner to add an owner-only `set_relayer` in a code upgrade. Then create a new relayer account (keep a
   full-access key on it this time, stored offline), give it a function-call key, update `RELAYER_ACCOUNT_ID` and
   `RELAYER_KEY_FILE`, and restart. Last resort: `contract/DEPLOY.md` RESET with a new relayer, which wipes the world.

**Topping up.** Sending NEAR to the relayer does not extend the current key, because the allowance stays the same. It also
clears the balance alarm, which then stops warning about the allowance. Top up the contract account (storage) or a new relayer
only, and if you ever top up the relayer, raise `MIN_BALANCE_NEAR` by the same amount. The parent account holds 1.98 NEAR.
```
near tokens sokokuu-ken.testnet send-near <receiver> '0.5 NEAR' network-config testnet sign-with-legacy-keychain send
```

## 2. Daily health check (laptop, 5 seconds)
```
curl -s https://app.chukua.xyz/v1/health | python3 -c 'import sys,json,time;d=json.load(sys.stdin)["data"];print(d["mode"],"degraded=",d["degraded"],"drift=",d["chain_drift"],"alarm=",d["relayer_balance_alarm"],"paused=",d["paused"],"day",d["day"],d["phase"],"next step in %.0f min"%((d["next_phase_ms"]-time.time()*1000)/60000))'
```
Good output: `testnet degraded= None drift= None alarm= None paused= False day N <phase> next step in 0..10 min`. The day goes up
by about 48 per real day.

| Field | Bad value | What to do |
|---|---|---|
| `mode` / `degraded` | `demo` / any text | Section 4 |
| `chain_drift` | any text | Restart (section 3, step 4). If it comes back, the runner and the contract were built from different `econ` code: rebuild the runner from the deployed contract's commit |
| `relayer_balance_alarm` | any text | Section 1 |
| `paused` | `true` | Someone used the kill switch. Unpause (section 3, step 6) |
| next step | below -10 min | The clock is stuck. Run `sudo journalctl -u sokokuu-runner -n 50 --no-pager \| grep 'clock advance failed'`, then check the contract's `is_paused` and `relayer` views |
| HTTP 502/504 | runner down | Check `systemctl status sokokuu-runner` and the journal, then restart |

Optional: a free uptime monitor (for example an UptimeRobot keyword monitor) on `$API/v1/health` that alerts when the body does
not contain `"degraded":null`.

## 3. Contract upgrade (goods) and restarting the runner
The goods commit (`02b32aa`) changes only `contract/`. It changes neither the state layout nor `econ`. So the runner binary
needs **no rebuild**, only a restart so it reloads the contract's world. Commands for the VPS:
```
API=https://app.chukua.xyz
ADMIN_TOKEN=$(sudo sed -n 's/^ADMIN_TOKEN=//p' /etc/sokokuu/runner.env)
# 1. note day/phase; back up the runner-only state
curl -s $API/v1/health
sudo cp -a /var/lib/sokokuu/state.json /var/lib/sokokuu/state.json.bak-$(date -u +%Y%m%dT%H%M)
# 2. pause player writes (the clock keeps running; a restart clears the pause)
curl -s -X POST $API/v1/admin/pause -H "x-admin-token: $ADMIN_TOKEN" -d '{"paused":true}'
```
3. From the laptop, deploy the wasm as described in `contract/DEPLOY.md` "UPGRADE" and run its verify step: the clock is
   unchanged and `world_hash` answers.
```
# 4. restart and read the start-up lines
sudo systemctl restart sokokuu-runner
sudo journalctl -u sokokuu-runner -n 20 --no-pager   # expect "clock synced from contract" and "world loaded from contract snapshot"; no WARN
# 5. run the section 2 check: testnet, degraded None, drift None, paused False
```
6. Make one buy at midday in the app. It should return a real `tx_hash` on testnet.nearblocks.io, and `chain_drift` should
   stay null. To unpause without a restart:
   `curl -s -X POST $API/v1/admin/pause -H "x-admin-token: $ADMIN_TOKEN" -d '{"paused":false}'`.

Rollback: redeploy `contract/target/sokokuu_contract.opt.wasm` (390,652 bytes, the live code) and restart the runner.

**If the econ bid fix ships too:** `econ` is compiled into both the contract and the runner, so both must come from the same
commit, and `make test` in `runner/` must pass on that commit. Build the runner first, while the old one keeps serving:
`git pull && sudo bash runner/deploy/install.sh`. That
installs the binary but does not restart it. Then pause, deploy the contract built with the same `econ`, restart right away,
and run the checks above. If the fix changes the `World` layout, the contract needs a migration; do not deploy until the
econ and contract owners confirm. A mismatch shows up as `WARN` at start or as `chain_drift`.

## 4. If health shows `degraded`
On any relayer or RPC error, the runner switches itself to demo mode (a local ledger with `demo:` tx hashes) and **stays there
until it is restarted**. The game still works for judges, but nothing reaches the chain, and moves made in demo mode are
dropped at the next restart, when the runner reloads the contract's world.
1. Read the reason: the `degraded` text in `curl -s $API/v1/health`, and
   `sudo journalctl -u sokokuu-runner -n 100 --no-pager | grep -E 'ALARM|WARN|error|failed'`.
2. Fix it:

| Reason contains | Cause | Fix |
|---|---|---|
| `testnet unavailable` | Bad config at start: key file, account, contract or RPC | Fix `/etc/sokokuu/runner.env` or the key file, then restart |
| `NotEnoughAllowance` | Key allowance used up | Use the levers in section 1. A restart alone does not help |
| `NotEnoughBalance`, `LackBalanceForState` | Relayer or contract out of NEAR | Top up that account (section 1), then restart |
| `InvalidNonce` | A second runner is using the relayer key | Stop the other one (for example a `make testnet` on the laptop), then restart |
| timeout, 429, connection | Public RPC trouble | Restart. If it repeats, set `NEAR_RPC_URL=https://rpc.testnet.fastnear.com` in the env file and restart |

3. Run `sudo systemctl restart sokokuu-runner`, then the section 2 check. If the cause cannot be fixed quickly, leave the
   runner as it is: demo mode is still a playable game.

About the RPC: on 14 Nov, measured from the laptop, a status call took ~3.4 s on `rpc.testnet.near.org` and ~0.7 s on
`rpc.testnet.fastnear.com`. Both run the same protocol version. The default stays because it works; switch only if errors
appear. Use only URLs without an API key: on an RPC error the runner copies the raw error text, URL included, into the public
`/v1/health` `degraded` field.

## 5. Do not
- Run a second runner against the contract. That includes `make testnet` on the laptop.
- Top up the relayer to silence the alarm (see section 1).
- RESET the contract before 25 Nov unless the world is broken. A reset erases every judge's progress.
- After 25 Nov, when you are done: `sudo systemctl disable --now sokokuu-runner`.
