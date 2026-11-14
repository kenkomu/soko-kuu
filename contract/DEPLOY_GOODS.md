# Goods upgrade: runbook for Ken (testnet only)

One code upgrade of `sokokuu.sokokuu-ken.testnet`: no `new` call, no state change, no extra funding. Rehearsed on
2026-11-14 in a local sandbox with the exact two files: the old wasm with players and goods, then the goods wasm deployed
over it, then rolled back and re-upgraded (details at the end). Nothing here has been run on testnet yet.

| | Live today (old) | After this upgrade (goods) |
|---|---|---|
| File | `contract/target/sokokuu_contract.opt.wasm` | `contract/target/sokokuu_contract.goods.wasm` |
| sha256 (hex, as `view-account-summary` prints it) | `60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2` | `766ea8c248cd779af5bdc438b0ca1bd1f30da1fde8c8e2b479dec78ac8dbcee1` |
| code_hash (base58, as RPC `view_account` prints it) | `7XXwp4LaAPREriPkDBtSRWQUnPuYFSux93h7wPgkWBZK` | `8yJybwzyYjRQ3wUukuMwwQQkiFKLbT8kH6cRCwqxXcXA` |
| Size | 390,652 bytes | 411,432 bytes (+20,780: about 0.21 NEAR more locked for storage) |
| Exported methods | 23 | 28 (adds `mt_batch_supply mt_metadata mt_metadata_base_by_token_id mt_metadata_contract mt_token`) |
| `mt_transfer` panic | `NON_TRANSFERABLE: pts cannot be transferred` | `NON_TRANSFERABLE: pts and goods cannot be transferred` |

Use the file that is already built. Do NOT rebuild it: the econ crate has uncommitted rule changes in the working tree today
("pending econ change A": market open in every phase, new dusk payout). A rebuild would give a different hash and put
different rules on chain. The goods file above was rebuilt from commit `02b32aa`/HEAD on 2026-11-14 (clean export, JUDGES.md
recipe) and came out byte-identical.

## 0. Before (read-only, about 1 minute)
Paste in a normal terminal (not with `!`), from the repo root:
```
cd ~/Projects/soko-kuu
sha256sum contract/target/sokokuu_contract.goods.wasm
# must print 766ea8c248cd779af5bdc438b0ca1bd1f30da1fde8c8e2b479dec78ac8dbcee1  (stop if not)
python3 -c "import json;print(json.load(open('$HOME/.near-credentials/testnet/sokokuu.sokokuu-ken.testnet.json'))['public_key'])"
# must print ed25519:DDMkfDRuQ8i13gUCySHWMAvwmyknUyAhvbJ2jSqXAVqd (the contract account's only full-access key; checked 2026-11-14)
chmod 600 ~/.near-credentials/testnet/*.json*   # optional but advised: these key files are group/world-readable (-rw-rw-r--) today
```
Load two read-only helpers into the same terminal (no keys, no gas):
```
C=sokokuu.sokokuu-ken.testnet; RPC=https://rpc.testnet.near.org
v() { a="${2:-}"; [ -n "$a" ] || a='{}'; curl -s "$RPC" -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"query\",\"params\":{\"request_type\":\"call_function\",\"finality\":\"final\",\"account_id\":\"$C\",\"method_name\":\"$1\",\"args_base64\":\"$(printf '%s' "$a" | base64 -w0)\"}}" | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or {};print(bytes(r["result"]).decode() if "result" in r else (r.get("error") or d.get("error")))'; }
acct() { curl -s "$RPC" -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"query\",\"params\":{\"request_type\":\"view_account\",\"finality\":\"final\",\"account_id\":\"$C\"}}" | python3 -c 'import sys,json;r=json.load(sys.stdin)["result"];print("code_hash",r["code_hash"],"storage_usage",r["storage_usage"],"balance_NEAR",int(r["amount"])/1e24)'; }
```
Note the values just before the deploy:
```
acct              # code_hash 7XXwp4La...  storage_usage ~395,160  balance_NEAR ~5.997
v clock           # e.g. [181,"dusk"]  (moves about every 10 min: the relayer runs advance_clock)
v world_hash      # 32 hex chars; changes whenever the clock moves or a player acts
v mt_supply '{"token_id":"pts"}'
```

## 1. Deploy (the one command; signs as the contract account, about 0.003 NEAR of gas)
```
near contract deploy sokokuu.sokokuu-ken.testnet use-file contract/target/sokokuu_contract.goods.wasm without-init-call network-config testnet sign-with-legacy-keychain send
```
You should see `Contract code has been successfully deployed.`, then `Transaction ID: ...` and an explorer link. The
syntax was checked on 2026-11-14 with `--help` (near-cli-rs 0.31.1); nothing was sent. Never add `with-init-call` and
never call `new`: the state is kept, and `new` would fail anyway ("already been initialized").

## 2. Post-checks (read-only, same terminal)
```
acct
# code_hash 8yJybwzyYjRQ3wUukuMwwQQkiFKLbT8kH6cRCwqxXcXA, storage_usage about 20,780 more than before (~415,940), balance about 0.003 NEAR lower
near account view-account-summary sokokuu.sokokuu-ken.testnet network-config testnet now
# "Local Contract (SHA-256 checksum hex)  766ea8c248cd779af5bdc438b0ca1bd1f30da1fde8c8e2b479dec78ac8dbcee1", 1 full access key

v clock           # same day/phase as before (or one phase later if the relayer ticked in between)
v world_hash      # same as before unless the clock moved or a player acted in between (the deploy itself does not change it)
v chain_id        # "testnet"
v relayer         # "relayer.sokokuu-ken.testnet"
v is_paused       # false
v mt_supply '{"token_id":"pts"}'      # same as before the deploy

# new NEP-245 views answer (before the upgrade these said MethodResolveError(MethodNotFound))
v mt_metadata_contract
# {"spec":"mt-1.0.0","name":"Soko Kuu","symbol":"SOKO"}
v mt_token '{"token_ids":["pts","tomato","nope"]}'
# [{"token_id":"pts","owner_id":null},{"token_id":"tomato","owner_id":null},null]
v mt_metadata '{"token_ids":["pts","tomato"]}'
# [{"title":"Soko pts","description":"Game score. Not money; never transferable.","transferable":false},{"title":"Tomatoes",...,"transferable":false}]

# goods supply: "0" for each good until a player who holds that good acts (old build: null). Unknown id: null.
v mt_supply '{"token_id":"tomato"}'
v mt_batch_supply '{"token_ids":["pts","tomato","maize","sukuma","onion","fish","charcoal","nope"]}'
# ["<pts supply>","0","0","0","0","0","0",null] right after the deploy (both live players held no goods on 2026-11-14)

# transfers still impossible; note the new wording
v mt_transfer
v mt_batch_transfer
# wasm execution failed with error: HostError(GuestPanic { panic_msg: "NON_TRANSFERABLE: pts and goods cannot be transferred" })
```
Then one live write path: let the relayer tick once (about 10 minutes) and check `v clock` moved; or play one buy in the
app and check the goods mirror (the player id is the 64-hex form of the player's public key):
```
v mt_balance_of '{"account_id":"<64 hex player id>","token_id":"tomato"}'   # equals that player's tomato stock
curl -s https://app.chukua.xyz/v1/health                                     # "mode":"testnet", "degraded":null
```
The runner and the app need no change or restart: the API, the signed bytes and the `world_snapshot` format are unchanged,
and the runner already maps `NON_TRANSFERABLE` to `INTERNAL`.

## 3. Rollback (only if a post-check fails)
Roll back if `clock`/`world_hash` error out (for example "Cannot deserialize the contract state"), if `advance_clock` or
every `act` starts failing, or if `/v1/health` turns `degraded`. One command, the same shape:
```
sha256sum contract/target/sokokuu_contract.opt.wasm   # 60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2
near contract deploy sokokuu.sokokuu-ken.testnet use-file contract/target/sokokuu_contract.opt.wasm without-init-call network-config testnet sign-with-legacy-keychain send
acct              # code_hash 7XXwp4LaAPREriPkDBtSRWQUnPuYFSux93h7wPgkWBZK
```
State is kept both ways. After a rollback, any goods balances minted meanwhile stay in storage but freeze (the old code
never updates them; its `mt_supply` then shows the stale goods supply instead of `null`). pts and the game carry on
normally. A later re-upgrade heals each player's goods balance at their next action. All of this was rehearsed.
If you roll back, revert the JUDGES.md "After the goods upgrade" wording too.

## After a successful upgrade, docs to flip (the lead does this)
- `contract/JUDGES.md`: top table "Live build" -> the goods row; export list -> 28 methods; `mt_transfer` text -> "pts and goods".
- `contract/NOTES.md`: "Current state" -> goods build live, with the date.
- `README.md` lines saying "goods are not yet NEP-245 token ids" (lead's file).

## What the rehearsal showed (local sandbox, near-workspaces 0.22, 2026-11-14; scratch test, not in the repo)
- Old wasm, `new`, 2 players (one bought 2 tomatoes), then the goods wasm deployed by the contract account itself
  (`without-init-call` equivalent): success, 30.0 Tgas (about 0.003 NEAR). code_hash became `8yJy...`, and `clock`, `world_hash`, `supply`, `pts_of`,
  `nonce_of` and `mt_supply pts` were unchanged. (The sandbox's absolute storage_usage is not meaningful for a patched account;
  the +20,780 bytes expected on chain is the size difference of the two files, since a deploy replaces the old code's bytes.)
- New views returned exactly the outputs quoted above. `mt_transfer` as a real transaction failed with
  `Smart contract panicked: NON_TRANSFERABLE: pts and goods cannot be transferred`.
- That player's first action after the upgrade (5.7 Tgas) minted the 2 pre-upgrade tomatoes, then the 1 bought now, as
  NEP-245 `mt_mint` events (`EVENT_JSON:{"standard":"nep245","version":"1.0.0","event":"mt_mint",...,"memo":"sync"}`):
  balance 3, `mt_supply tomato` "3". `advance_clock` worked (2.2 Tgas).
- Rollback to the old wasm kept `world_hash`; `act` and `advance_clock` worked on the old code; goods balances froze.
  Re-upgrade, then one action: the balance healed to the world stock.
