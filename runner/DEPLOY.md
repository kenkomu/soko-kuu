# Deploying the runner against the real testnet

No secret goes in the repo. The key lives in a file outside the repo; the runner is given only the file path.

For a VPS, the ready-made kit is in `deploy/` (systemd unit, nginx server block, env template, `install.sh`, `CHECKLIST.md`); the sections below explain the same steps.

## 1. What the user must supply
- A deployed contract account (`CONTRACT_ID`), initialised with the relayer account as `relayer` (see `contract/`).
- A funded testnet relayer account (`RELAYER_ACCOUNT_ID`) and its key. Best: a function-call key limited to
  `CONTRACT_ID` with methods `act,advance_clock,rebind_key`. Save the secret as a one-line file (`ed25519:...`),
  or use the near-cli credentials JSON as is (its `private_key` field is read).
  `install -m 600 /dev/null ~/secrets/relayer.key`, then put the key in it with an editor.
- The Pages origin, e.g. `https://YOURUSER.github.io` (scheme and host only).

## 2. Run
```
export RELAYER_ACCOUNT_ID=sokokuu-relayer.testnet
export RELAYER_KEY_FILE=$HOME/secrets/relayer.key     # a path, never the key itself
export CONTRACT_ID=sokokuu.testnet
export CORS_ORIGINS=https://YOURUSER.github.io        # comma separated, exact match; localhost always allowed
export ADMIN_TOKEN=$(openssl rand -hex 24)            # kill switch and manual clock
export PHASE_SECS=600                                  # optional automatic clock
cd runner && make testnet
```
`make testnet` refuses to start if the account, key file or contract is missing. Optional: `NEAR_RPC_URL`
(default `https://rpc.testnet.near.org`), `GAS_TGAS`, `MIN_BALANCE_NEAR`, `MAIL_WEBHOOK_URL`, `PUBLIC_CONFIRM_URL`.
`RELAYER_PRIVATE_KEY` (the value) still works as a fallback for a host secret store.

Verify: `curl -s $API/v1/health` must show `"mode":"testnet"` and `"degraded":null`. If it says `demo` with a
`degraded` reason, the key, account or RPC was wrong and the runner fell back to demo on purpose. Then run
`runner/scripts/cors_check.sh https://YOURUSER.github.io` and a fetch from the Pages site's console.

Status: the testnet adapter compiles and reads the key file, but has not run against a real chain or a local
sandbox. Treat the first run as the test: watch `degraded` and the runner log.

### Verified against the live testnet contract (2026-11-10)
Env that worked: `RELAYER_ACCOUNT_ID=relayer.sokokuu-ken.testnet`, `RELAYER_KEY_FILE=<path to the key file>`,
`CONTRACT_ID=sokokuu.sokokuu-ken.testnet`, `DEMO_SEED=1` (must equal the contract's seed), `ADMIN_TOKEN`, `PHASE_SECS` (optional),
`MIN_BALANCE_NEAR` (default 0.5), `NEAR_RPC_URL` default works.
Works: health (testnet, no degraded), guest login, signed buy relayed with a real tx hash, nonce re-sync from chain,
admin and `PHASE_SECS` clock calling `advance_clock`, player `advance` -> FORBIDDEN, WRONG_PHASE at dawn, local clock
synced from the contract's `clock` view at start.
World sync: once the contract has the `world_hash` and `world_snapshot` views, the runner loads the contract's world at
start and, after every relayed act or clock step, compares hashes and replaces its local world from the snapshot on any
difference (log line `resync:`; `chain_drift` in `/v1/health` is set only while out of sync). In testnet mode player ids
are the contract's ids (64 hex chars of the key). Against an older contract without the views the runner is only a mirror:
only the player balance is checked and `chain_drift` reports a mismatch.

### Runner-only state and the single-instance rule
The contract does not hold ledger history, hashed email bindings and revoked keys, guests that have not acted yet, pending
login links, the new-accounts-per-day counter, the event feed or personal bests. In testnet mode the runner keeps them in
`DATA_DIR` (default `./data`; `/var/lib/sokokuu` under systemd) as `state.json`, mode 600, directory 700. It writes
temp-then-rename about one second after a change (and once more on SIGTERM), and loads it at start, before it loads the
contract snapshot. Emails are never stored, only their SHA-256 hashes. A missing file means a fresh start; a damaged one
is logged, copied to `state.json.corrupt` and ignored, never a crash. Back up `DATA_DIR` if you care about it.
**Run exactly ONE runner instance against a contract.** Two instances each hold their own copy of this state and each relays
with the same relayer key: their mirrors go stale (refusals such as PRICE_MOVED, then a resync) and nonces and guests diverge.
Before starting a new instance (or `make testnet` by hand on a laptop) stop the old one.

### Contract build flag and the clock
- Build the contract with `RUSTFLAGS="--cfg near"`. Without it rejections are bare traps with no code text (the runner
  then reports chain trouble, not a game error). With it the failure text is `Smart contract panicked: CODE: msg`, which
  the runner maps to the API error codes.
- The game starts at dawn. buy, sell, haggle, credit_request and invest need midday, and the relayer calls
  `advance_clock` to move the phase. Set `PHASE_SECS`, or right after deploy call
  `curl -X POST $API/v1/admin/advance -H "x-admin-token: $ADMIN_TOKEN"` once to reach midday.

## 3. HTTPS
The Pages site is https, so the API must be too (browsers block mixed content). Pick one.

A. Tunnel, fastest (no domain, no open ports; lives while the process runs):
```
cloudflared tunnel --url http://localhost:8787
```
Use the printed `https://....trycloudflare.com` as the app's `API_BASE`. A quick tunnel URL changes on restart; for a
stable URL use a named tunnel on your own domain. Set `TRUST_PROXY=1` so rate limits see the real client IP.

B. VPS that already runs nginx (this deployment: app.chukua.xyz). DNS A record `app` -> VPS IPv4 in Namecheap Advanced DNS
(TTL Automatic; check with `dig +short app.chukua.xyz @dns1.registrar-servers.com`). Add ONE new file,
`deploy/nginx-app.chukua.xyz.conf`, as `/etc/nginx/sites-available/app.chukua.xyz` with a symlink into `sites-enabled`;
run `sudo nginx -t` before `sudo systemctl reload nginx`; get the certificate with
`sudo certbot --nginx -d app.chukua.xyz` (`sudo apt install certbot python3-certbot-nginx` if absent). The runner deployment
must never change the other sites' config; compare their `server_name` list and `curl -sI` answers before and after
(exact commands in `deploy/CHECKLIST.md`).
The file proxies to `127.0.0.1:8787`, disables buffering and compression for the `/v1/events` long-poll, limits bodies to
64k and adds no CORS headers (the runner sets them). Check `ss -ltn | grep 8787` first; if the port is taken, set `PORT` in
the env file and change both `proxy_pass` lines. Run the runner under systemd (`deploy/sokokuu-runner.service`, key at
`/etc/sokokuu/relayer.key`, owner = service user, mode 600), the runner binds `127.0.0.1` by default in testnet mode (`BIND_ADDR`; demo/dev defaults to `0.0.0.0`), keep 8787 closed in the firewall too, set `TRUST_PROXY=1`.

## 4. CORS_ORIGINS
Exactly the Pages origin: for a project site that is `https://YOURUSER.github.io` (the repo path is not part of an
origin). Several origins are comma separated. A wrong value appears in the browser as a CORS error while `curl` works.

## 5. Secrets hygiene
`.env`, `*.key`, `*.pem`, credentials JSON and `secrets/` are git-ignored (`runner/.gitignore`, `runner/rs/.gitignore`).
Keep the key file outside the repo anyway. Rotate: add a new access key, restart with the new file, delete the old key.
