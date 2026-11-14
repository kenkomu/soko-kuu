# Soko Kuu contract: one page for judges

Testnet only, no real money. Points ("pts") are a game score, not a currency. Not audited.

| | |
|---|---|
| Contract | `sokokuu.sokokuu-ken.testnet` |
| Owner (can pause) | `sokokuu-ken.testnet` |
| Relayer | `relayer.sokokuu-ken.testnet` |
| Chain id (signing domain) | `testnet` |
| **Live build (checked 2026-11-14)** | sha256 `60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2` (390,652 bytes; base58 code_hash `7XXwp4LaAPREriPkDBtSRWQUnPuYFSux93h7wPgkWBZK`). Only `pts` is a token. |
| Goods upgrade (built and tested, NOT deployed as of 2026-11-14) | sha256 `766ea8c248cd779af5bdc438b0ca1bd1f30da1fde8c8e2b479dec78ac8dbcee1` (411,432 bytes; base58 `8yJybwzyYjRQ3wUukuMwwQQkiFKLbT8kH6cRCwqxXcXA`). Goods also become NEP-245 ids. |

Which one is on chain right now: check the code hash yourself (point 1 below). Everything on this page says which build
it applies to. If the hash is `7XXw...`/`60f88915...`, goods are NOT tokens yet.

## Methods and who may call them
| Method | Kind | Caller |
|---|---|---|
| `act(pubkey, nonce, expires_ms, action, sig)` | change | relayer only; the player's ed25519 signature is the real authority |
| `advance_clock()` | change | relayer only (players cannot move time; a signed `advance` is refused) |
| `rebind_key(old_pubkey, new_pubkey)` | change | relayer only (device recovery; the old key is revoked) |
| `decide(merchant, margin_bp)`, `crank(merchant)` | change | `<merchant>.npc.sokokuu.sokokuu-ken.testnet` only (relayer also accepted). Margin clamped to 2%..40%; the +-20%/day price move is enforced by the rule code |
| `pause()`, `unpause()` | change | owner only |
| `mt_transfer()`, `mt_batch_transfer()` | change | anyone; always panics `NON_TRANSFERABLE` |
| `mt_balance_of`, `mt_batch_balance_of`, `mt_supply`, `pts_of`, `nonce_of`, `clock`, `supply`, `is_paused`, `relayer`, `chain_id`, `world_hash`, `world_snapshot` | view | anyone (both builds) |
| `mt_batch_supply`, `mt_token`, `mt_metadata`, `mt_metadata_base_by_token_id`, `mt_metadata_contract` | view | anyone; **goods build only** (the live build answers `MethodNotFound`) |

Prices come from rule-based code (the `econ` crate), not an LLM.

## Non-transferable points: how to verify
1. No cash-out, withdraw, sale or payable method exists. The exported functions are exactly:
   - live build (23): `act advance_clock chain_id clock contract_source_metadata crank decide is_paused mt_balance_of mt_batch_balance_of mt_batch_transfer mt_supply mt_transfer new nonce_of pause pts_of rebind_key relayer supply unpause world_hash world_snapshot`
   - goods build (28): the same plus `mt_batch_supply mt_metadata mt_metadata_base_by_token_id mt_metadata_contract mt_token` (all views).

   (`new` is guarded: calling it again fails "The contract has already been initialized".) List them yourself, no extra tools:
   ```
   curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"view_code","finality":"final","account_id":"sokokuu.sokokuu-ken.testnet"}}' \
    | python3 -c "import sys,json,base64;open('c.wasm','wb').write(base64.b64decode(json.load(sys.stdin)['result']['code_base64']))"
   sha256sum c.wasm   # one of the two hashes at the top
   wasm-tools print c.wasm | grep '(export'     # or: wasm-objdump -x -j Export c.wasm
   ```
2. `mt_transfer` and `mt_batch_transfer` always fail. Read-only proof, no account and no gas: the RPC runs a change method in view mode and returns the panic:
   ```
   curl -s https://rpc.testnet.near.org -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"query","params":{"request_type":"call_function","finality":"final","account_id":"sokokuu.sokokuu-ken.testnet","method_name":"mt_transfer","args_base64":"e30="}}'
   ```
   Result on the live build (seen 2026-11-14): `HostError(GuestPanic { panic_msg: "NON_TRANSFERABLE: pts cannot be transferred" })`.
   On the goods build the text is `NON_TRANSFERABLE: pts and goods cannot be transferred` (seen in the sandbox). Same with `"method_name":"mt_batch_transfer"`.
   As a real transaction from your own testnet account (costs a little gas, changes nothing; this one is for you to run, we did not):
   `near contract call-function as-transaction sokokuu.sokokuu-ken.testnet mt_transfer json-args '{}' prepaid-gas '30 Tgas' attached-deposit '0 NEAR' sign-as <you>.testnet network-config testnet sign-with-keychain send`
3. Internally a transfer hook on the NEP-245 controller also panics, so no code path moves pts (or, on the goods build, goods) between holders; only mint (earning or buying) and burn (spending or selling) exist. Unit tests `mt_transfer_method_panics`, `transfers_rejected` and `goods_cannot_be_transferred` cover both (`cargo test` in `contract/`: 46 pass on the committed source, see "What was verified how").
4. Read balances (read-only, `near-cli-rs`):
   `near contract call-function as-read-only sokokuu.sokokuu-ken.testnet mt_supply json-args '{"token_id":"pts"}' network-config testnet now` (returned `"9454"` on 2026-11-14)
   `near contract call-function as-read-only sokokuu.sokokuu-ken.testnet pts_of json-args '{"pubkey":"ed25519:<player key>"}' network-config testnet now` (returns a decimal string; `"0"` for an unknown key)
   `mt_balance_of {"account_id":"<player hex account>","token_id":"pts"}`, `supply` (total world money, `"520256"` on 2026-11-14), and `clock`, `relayer`, `chain_id`, `is_paused`, `world_hash` with `'{}'`, `nonce_of {"pubkey":...}`. The same calls work through the curl form above (args base64 of the JSON).
   `mt_balance_of(pts)` mirrors the world lazily: it is exact after the player's own last action, and can lag after day rolls (chama dues, stipends); `pts_of` and `world_snapshot` read the world itself.

Honest caveat: the account `sokokuu.sokokuu-ken.testnet` keeps one full-access key (used for upgrades and the pre-submission reset), so the guarantee is the code at the hash you see, not a lock on the account. Check the hash with `near account view-account-summary sokokuu.sokokuu-ken.testnet network-config testnet now` (it prints the sha256 hex, `60f88915...` for the live build) or RPC `view_account` (base58 `code_hash`, `7XXw...` for the live build).

## Replay, expiry, nonce (both builds)
The player signs the exact bytes `sokokuu/v1|<chain_id>|<contract_id>|<pubkey>|<nonce>|<expires_ms>|<action_json>` (ed25519).
- Wrong chain id or contract id, or any tampered field: `BAD_SIG`.
- Nonce must be strictly greater than the stored one: replay gives `BAD_NONCE`.
- `expires_ms` must not be in the past and at most 120 s ahead of chain time: otherwise `EXPIRED`.
- Any failure panics, which reverts state, so a rejected action never consumes the nonce.
- A key revoked by `rebind_key` is refused (`FORBIDDEN`).
Errors appear as `<CODE>: message` (codes in docs/API.md). Limits: 300 players, 100 new players per day.

## Pause switch (both builds)
Owner `sokokuu-ken.testnet` calls `pause`; then `act`, `advance_clock`, `rebind_key`, `decide`, `crank` all fail `FORBIDDEN: contract is paused`. Views still work (`is_paused`). `unpause` reverses it.

## Relayer key permissions
`relayer.sokokuu-ken.testnet` has exactly one access key, function-call only, receiver `sokokuu.sokokuu-ken.testnet`, methods `act, advance_clock, rebind_key`, with a gas allowance (1.8 NEAR when added on 2026-11-10; 1.656 NEAR left on 2026-11-14). It cannot transfer funds, deploy, or call `pause`. Verify:
`near account list-keys relayer.sokokuu-ken.testnet network-config testnet now`
Merchant keys (when created) may call only `decide, crank`.

## Reproducing the wasm
Toolchain: rustc 1.97.1 (stable, 2026-07-14), cargo 1.97.1, target `wasm32-unknown-unknown`, `Cargo.lock` as committed (`--locked`), binaryen `wasm-opt` 130 from npm (`npm i binaryen@130`; npm 129, 131 and 132 give the same bytes; 123 to 128 and the Dart SDK's bundled wasm-opt 130 do NOT). Source: `contract/` and its sibling `econ/` (path dependency).
```
# from the directory that holds contract/ and econ/ (REPO), at the commit named below
cd contract
RUSTFLAGS="--cfg near -C target-cpu=mvp --remap-path-prefix=$REPO=/home/ken/Projects/soko-kuu" \
  cargo build --release --locked --target wasm32-unknown-unknown
wasm-opt -Oz --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int --enable-mutable-globals \
  --signext-lowering --llvm-nontrapping-fptoint-lowering --llvm-memory-copy-fill-lowering --strip-debug --strip-producers \
  target/wasm32-unknown-unknown/release/sokokuu_contract.wasm -o sokokuu_contract.opt.wasm
sha256sum sokokuu_contract.opt.wasm
```
- **Goods build `766ea8c2...`: reproducible from git.** Commit `02b32aa` (contract goods commit; `contract/src` and `econ/` unchanged up to the 2026-11-14 HEAD) rebuilt from a clean `git archive` export on 2026-11-14 gave byte-identical output (411,432 bytes, MVP-only checked with `wasm-opt --mvp-features`).
- **Live build `60f88915...`: NOT reproducible from any commit.** It was rebuilt byte-identically on 2026-11-10 from that day's working tree, but that exact source was never committed. The first commit `d456e6e` builds to `2be6b0bf0f70b48e...`: same size and the same 23 exports, different code bytes. Its behaviour is covered by the on-chain reads below, not by a hash match. Deploying the goods build closes this gap.

`--cfg near` is required so panic messages (API error codes) survive. The raw cargo output embeds source paths, so without `--remap-path-prefix` a checkout anywhere but `/home/ken/Projects/soko-kuu` gives a different hash (the goods rebuild above ran from another directory with the remap). Not tested: a different `CARGO_HOME` (registry paths); if your hash differs, also remap it (`--remap-path-prefix=$CARGO_HOME=/home/ken/.cargo`) or compare behaviour with the tests. Release profile: opt-level z, lto, strip, panic abort, overflow-checks on.

## What was verified how
- On-chain reads (RPC, 2026-11-14, live build): code hash `7XXw...` = sha256 `60f88915...`; `mt_transfer` and `mt_batch_transfer` panic `NON_TRANSFERABLE: pts cannot be transferred` (view-mode call); `mt_metadata_contract` gives `MethodNotFound` and `mt_supply {"token_id":"tomato"}` gives `null` (goods are not tokens on the live build); `clock` (day 172+), `world_hash`, `world_snapshot` (2 players), `supply`, `mt_supply pts`, `chain_id` `"testnet"`, `relayer`, `is_paused` `false` answer; the relayer has one function-call key limited to `act, advance_clock, rebind_key`; the contract account has one full-access key. Export lists: read 2026-11-14 from the two local files, whose sha256 equal the hashes at the top (the live one equals the on-chain code). `new` re-init refusal: read on chain 2026-11-10, same code hash.
- Local rebuild: goods build reproduced from git (above); live build matched on 2026-11-10 from the uncommitted tree only.
- Unit tests (`cargo test`, 46): transfer rejection (pts and goods), owner-only pause, relayer-only methods, nonce/expiry rules, goods mint/burn mirror and events. All 46 pass on the committed source (2026-11-14, clean export). Note for anyone running them in a working tree where `econ/` has uncommitted edits: `buy_at_dawn_rejected` checks the midday-only trading rule that both deployed builds enforce.
- Sandbox tests (near-workspaces, 6, on the goods build): signature compatibility with near-api-js, replay/expiry/chain-id/contract-id rejection, pause, rebind, merchant calls, gas tables, goods mirror/events/non-transfer. Plus an upgrade rehearsal (2026-11-14): the old wasm with players, then the goods wasm deployed over it, then rolled back and re-upgraded. State, clock and `world_hash` were kept, and pre-upgrade goods were minted at the player's next action (contract/DEPLOY_GOODS.md).
- Judge must run themselves: the wasm export listing, the rebuild and hash comparison, the `mt_transfer` transaction, and `near account list-keys` (we saw the key list over RPC only).
- Not verified anywhere: behaviour under load beyond the sandbox gas table; a malicious owner redeploying code (see the full-access key caveat).

## Gas (Tgas, measured in a local sandbox; per-call limit 300; 1 Tgas is about 0.0001 NEAR)
| players | act (live build) | act (goods build) | advance_clock (live / goods) | decide | rebind_key |
|---|---|---|---|---|---|
| 1 | 3.9 | 4.8 | 2.7 / 2.7 | 2.3 | 3.2 |
| 49 | 6.9 | 7.8 | 5.9 / 6.1 | 5.2 | 6.2 |
| 297 | 23.3 | 24.3 | 22.5 / 24.8 | 21.1 | 22.6 |
Goods build, worst case: with 49 or 100 holders whose goods all change in one step, `advance_clock` peaks at 40.5 / 42.9 Tgas (eager mirroring is capped by an event budget).
On testnet (live build): `advance_clock` 2.4 Tgas, first `buy` by a new guest 4.3 Tgas. `world_hash` / `world_snapshot` views fit the view gas limit at 300 players.

## Goods as NEP-245 tokens (goods build only; NOT live until the upgrade is deployed)
Token ids: `pts`, `tomato`, `maize`, `sukuma`, `onion`, `fish`, `charcoal`. A player's goods balance equals their stock in the rule engine:
buying mints, selling burns, spoilage and daily consumption burn (`mt_mint` / `mt_burn` NEP-245 events with `memo: "sync"`). Goods cannot be
transferred either (`mt_transfer` panics `NON_TRANSFERABLE: pts and goods cannot be transferred`). Views: `mt_balance_of`, `mt_batch_balance_of`, `mt_supply`, `mt_batch_supply`,
`mt_token`, `mt_metadata`, `mt_metadata_contract` (`transferable: false` in every token's metadata). Limits: merchants' own stock is not tokenised; goods a player held before the upgrade are minted at
that player's next action; after a day roll a holder's goods balance can lag until their next action if more than 40 holders changed in the same step (`world_snapshot` is always exact).
On the live build none of this exists: goods live only inside the world state (`world_snapshot`), and only `pts` is a token.
