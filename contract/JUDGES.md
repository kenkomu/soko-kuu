# Soko Kuu contract: one page for judges

Testnet only, no real money. Points ("pts") are a game score, not a currency.

| | |
|---|---|
| Contract | `sokokuu.sokokuu-ken.testnet` |
| Owner (can pause) | `sokokuu-ken.testnet` |
| Relayer | `relayer.sokokuu-ken.testnet` |
| Chain id (signing domain) | `testnet` |
| Code sha256 | `60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2` (390,652 bytes) |

## Methods and who may call them
| Method | Kind | Caller |
|---|---|---|
| `act(pubkey, nonce, expires_ms, action, sig)` | change | relayer only; the player's ed25519 signature is the real authority |
| `advance_clock()` | change | relayer only (players cannot move time; a signed `advance` is refused) |
| `rebind_key(old, new)` | change | relayer only (device recovery; the old key is revoked) |
| `decide(merchant, margin_bp)`, `crank(merchant)` | change | `<merchant>.npc.sokokuu.sokokuu-ken.testnet` only (relayer also accepted). Margin clamped to 2%..40%; the +-20%/day price move is enforced by the rule code |
| `pause()`, `unpause()` | change | owner only |
| `mt_transfer()`, `mt_batch_transfer()` | change | anyone; always panics `NON_TRANSFERABLE` |
| `mt_balance_of`, `mt_batch_balance_of`, `mt_supply`, `pts_of`, `nonce_of`, `clock`, `supply`, `is_paused`, `relayer`, `chain_id`, `world_hash`, `world_snapshot` | view | anyone |

Prices come from rule-based code (the `econ` crate), not an LLM.

## Non-transferable points: how to verify
1. No cash-out, withdraw, sale or payable method exists. The exported functions of the deployed code are exactly:
   `act advance_clock chain_id clock contract_source_metadata crank decide is_paused mt_balance_of mt_batch_balance_of mt_batch_transfer mt_supply mt_transfer new nonce_of pause pts_of rebind_key relayer supply unpause world_hash world_snapshot`
   (`new` is guarded: calling it again fails "The contract has already been initialized".) List them yourself, no extra tools:
   ```
   curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"view_code","finality":"final","account_id":"sokokuu.sokokuu-ken.testnet"}}' \
    | python3 -c "import sys,json,base64;open('c.wasm','wb').write(base64.b64decode(json.load(sys.stdin)['result']['code_base64']))"
   sha256sum c.wasm   # must equal the hash at the top
   wasm-tools print c.wasm | grep '(export'     # or: wasm-objdump -x -j Export c.wasm
   ```
2. `mt_transfer` and `mt_batch_transfer` always fail. Read-only proof, no account and no gas: the RPC runs a change method in view mode and returns the panic:
   ```
   curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"call_function","finality":"final","account_id":"sokokuu.sokokuu-ken.testnet","method_name":"mt_transfer","args_base64":"e30="}}'
   ```
   Result: `HostError(GuestPanic { panic_msg: "NON_TRANSFERABLE: pts and goods cannot be transferred" })`. Same with `"method_name":"mt_batch_transfer"`.
   As a real transaction from your own testnet account (costs a little gas, changes nothing; this one is for you to run, we did not):
   `near contract call-function as-transaction sokokuu.sokokuu-ken.testnet mt_transfer json-args '{}' prepaid-gas '30 Tgas' attached-deposit '0 NEAR' sign-as <you>.testnet network-config testnet sign-with-keychain send`
3. Internally a transfer hook on the NEP-245 controller also panics, so no code path moves pts between holders; only mint (earning) and burn (spending) exist. Unit tests `mt_transfer_method_panics` and `transfers_rejected` cover both (`cargo test` in `contract/`: 46 pass).
4. Read balances (read-only, `near-cli-rs`):
   `near contract call-function as-read-only sokokuu.sokokuu-ken.testnet mt_supply json-args '{"token_id":"pts"}' network-config testnet now` (returned `"948"` on 2026-11-10, before the final reset)
   `near contract call-function as-read-only sokokuu.sokokuu-ken.testnet pts_of json-args '{"pubkey":"ed25519:<player key>"}' network-config testnet now` (returns a decimal string; `"0"` for an unknown key)
   `mt_balance_of {"account_id":"<player hex account>","token_id":"pts"}`, `supply` (total world money, `"499943"` that day), and `clock`, `relayer`, `chain_id`, `is_paused`, `world_hash` with `'{}'`, `nonce_of {"pubkey":...}`. The same calls work through the curl form above (args base64 of the JSON).

Honest caveat: the account `sokokuu.sokokuu-ken.testnet` keeps one full-access key (used for upgrades and the pre-submission reset), so the guarantee is the code at the hash above, not a lock on the account. Check the hash with `near account view-account-summary sokokuu.sokokuu-ken.testnet network-config testnet now` (base58 `7XXwp4LaAPREriPkDBtSRWQUnPuYFSux93h7wPgkWBZK` = the sha256 above).

## Replay, expiry, nonce
The player signs the exact bytes `sokokuu/v1|<chain_id>|<contract_id>|<pubkey>|<nonce>|<expires_ms>|<action_json>` (ed25519).
- Wrong chain id or contract id, or any tampered field: `BAD_SIG`.
- Nonce must be strictly greater than the stored one: replay gives `BAD_NONCE`.
- `expires_ms` must not be in the past and at most 120 s ahead of chain time: otherwise `EXPIRED`.
- Any failure panics, which reverts state, so a rejected action never consumes the nonce.
- A key revoked by `rebind_key` is refused (`FORBIDDEN`).
Errors appear as `<CODE>: message` (codes in docs/API.md). Limits: 300 players, 100 new players per day.

## Pause switch
Owner `sokokuu-ken.testnet` calls `pause`; then `act`, `advance_clock`, `rebind_key`, `decide`, `crank` all fail `FORBIDDEN: contract is paused`. Views still work (`is_paused`). `unpause` reverses it.

## Relayer key permissions
`relayer.sokokuu-ken.testnet` has exactly one access key, function-call only, receiver `sokokuu.sokokuu-ken.testnet`, methods `act, advance_clock, rebind_key`, with a gas allowance (about 1.79 NEAR). It cannot transfer funds, deploy, or call `pause`. Verify:
`near account list-keys relayer.sokokuu-ken.testnet network-config testnet now`
Merchant keys (when created) may call only `decide, crank`.

## Reproducing the wasm (verified 2026-11-10: byte-identical to on-chain)
Toolchain used: rustc 1.97.1 (stable, 2026-07-14), cargo 1.97.1, target `wasm32-unknown-unknown`, `Cargo.lock` as committed (`--locked`), binaryen `wasm-opt` 130 from npm (`npm i binaryen@130`; npm 129, 131 and 132 give the same bytes; 123 to 128 and the Dart SDK's bundled wasm-opt 130 do NOT). Source: `contract/` and its sibling `econ/` (path dependency).
```
# from the directory that holds contract/ and econ/ (REPO)
cd contract
RUSTFLAGS="--cfg near -C target-cpu=mvp --remap-path-prefix=$REPO=/home/ken/Projects/soko-kuu" \
  cargo build --release --locked --target wasm32-unknown-unknown
wasm-opt -Oz --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int --enable-mutable-globals \
  --signext-lowering --llvm-nontrapping-fptoint-lowering --llvm-memory-copy-fill-lowering --strip-debug --strip-producers \
  target/wasm32-unknown-unknown/release/sokokuu_contract.wasm -o sokokuu_contract.opt.wasm
sha256sum sokokuu_contract.opt.wasm    # 60f88915...6ecd2
```
`--cfg near` is required so panic messages (API error codes) survive. The raw cargo output embeds source paths, so without `--remap-path-prefix` a checkout anywhere but `/home/ken/Projects/soko-kuu` gives a different hash (we saw this; with the remap a copy in another directory matched). Not tested: a different `CARGO_HOME` (registry paths); if your hash differs, also remap it (`--remap-path-prefix=$CARGO_HOME=/home/ken/.cargo`) or compare behaviour with the tests. Release profile: opt-level z, lto, strip, panic abort, overflow-checks on.

## What was verified how
- On-chain reads (RPC, 2026-11-10): code hash equals the hash above; export list in point 1; `mt_transfer` and `mt_batch_transfer` panic NON_TRANSFERABLE (view-mode call); `new` refuses re-init; `mt_supply`, `pts_of`, `supply`, `clock`, `relayer`, `chain_id`, `is_paused`, `world_hash` answer; relayer has one function-call key limited to `act, advance_clock, rebind_key`; contract account has one full-access key.
- Local rebuild: the documented recipe reproduces the on-chain bytes (above).
- Unit tests (`cargo test`, 46): transfer rejection, owner-only pause, relayer-only methods, nonce/expiry rules. Sandbox tests (near-workspaces, 4): signature compatibility with near-api-js, replay/expiry/chain-id/contract-id rejection, pause, rebind, merchant calls, gas table. The sandbox tests do not call `mt_transfer`; that is covered by the on-chain read above and the unit tests.
- Judge must run themselves: the wasm export listing, the rebuild and hash comparison, the `mt_transfer` transaction, and `near account list-keys` (we saw the key list over RPC only).
- Not verified anywhere: behaviour under load beyond the sandbox gas table; a malicious owner redeploying code (see the full-access key caveat).

## Gas (Tgas, measured in a local sandbox; per-call limit 300; 1 Tgas is about 0.0001 NEAR)
| players | act | advance_clock | decide | rebind_key |
|---|---|---|---|---|
| 1 | 3.9 | 2.7 | 2.3 | 3.2 |
| 49 | 6.9 | 5.9 | 5.2 | 6.2 |
| 297 | 23.3 | 22.5 | 21.1 | 22.6 |
On testnet: `advance_clock` 2.4 Tgas, first `buy` by a new guest 4.3 Tgas. `world_hash` / `world_snapshot` views fit the view gas limit at 300 players.

## Goods are NEP-245 tokens too (pending deploy of the build below)
Token ids: `pts`, `tomato`, `maize`, `sukuma`, `onion`, `fish`, `charcoal`. A player's goods balance equals their stock in the rule engine:
buying mints, selling burns, spoilage and daily consumption burn (`mt_mint` / `mt_burn` NEP-245 events with `memo: "sync"`). Goods cannot be
transferred either (`mt_transfer` panics `NON_TRANSFERABLE`). Views: `mt_balance_of`, `mt_batch_balance_of`, `mt_supply`, `mt_batch_supply`,
`mt_token`, `mt_metadata`, `mt_metadata_contract`. Limits: merchants' own stock is not tokenised; after a day roll a holder's goods balance
can lag until their next action if more than 40 holders changed in the same step (`world_snapshot` is always exact).
Candidate build: sha256 `766ea8c248cd779af5bdc438b0ca1bd1f30da1fde8c8e2b479dec78ac8dbcee1` (411,432 bytes). The hash and export list at the top of
this page refer to the build currently deployed until that is replaced; update both after the upgrade.
