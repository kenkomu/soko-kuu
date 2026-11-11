# contract notes

## First-hour check (done)
`near-sdk-contract-tools` 4.0.0 compiles against near-sdk 5.30.1 (lockfile; Cargo.toml asks `5.18`+, features `legacy`).
No pin or hand-written NEP-245 needed. We use its Nep245Controller (mint/burn/balance/supply) and a TransferHook
(`DenyTransfer`) that panics, so no internal or external transfer can ever succeed. We did NOT use
`#[derive(MultiToken)]`: it would expose real `mt_transfer`/resolve methods. Instead `mt_transfer` and
`mt_batch_transfer` are hand-written and always panic `NON_TRANSFERABLE`; standard views `mt_balance_of`,
`mt_batch_balance_of`, `mt_supply` are exposed. Also exposed: `mt_token`, `mt_batch_supply`, `mt_metadata`, `mt_metadata_base_by_token_id`, `mt_metadata_contract`. NEP-245 mint/burn events come from the controller.
Token ids: `pts` plus one per good (`tomato maize sukuma onion fish charcoal` = econ good ids). Stakes stay in the econ `World`.

## Design
- `act` is relayer-only (predecessor == relayer), then verifies ed25519 over the exact signed string, expiry
  (not past, at most 120 s ahead), strictly increasing nonce. Any failure panics, which reverts the nonce bump:
  a rejected action never consumes the nonce. Panic text is `<API error code>: message`.
- Player-signed `advance` is FORBIDDEN; the relayer calls `advance_clock`.
- `delete_account` action is a nonce-only no-op (API.md).
- `decide(merchant, margin_bp)`: caller is `<merchant>.npc.<contract>` (or relayer); margin clamped 2%..40%.
  The +-20%/day price move is enforced inside econ (`ref_mid`). `crank(merchant)` is a state-neutral heartbeat.
  Function-call keys on merchant accounts must list only `decide,crank`.
- Owner-only `pause`/`unpause` blocks `act`, `advance_clock`, `decide`, `crank`.
- Events: `env::log_str("event|...")` and `ledger|pts|cause` lines, plus NEP-245 mint/burn logs. Not yet NEP-297 JSON.

## econ integration points
Path dep `../econ` (feature `borsh`). Uses `World::new/apply/advance/supply/merchant_idx`, `Action`, `Phase`,
`Config`. The whole `World` is one borsh blob in contract state (cap 300 players, 100 new/day).
Expect gas to grow with players; measure before deploy.

## Not done / risks
- Not deployed to testnet. Wasm builds and runs in the local sandbox (see below); `overflow-checks` on in release.
- Events are plain log lines, not NEP-297 JSON.
- Goods mirror PLAYER-held stock only; merchant stock stays in the World (not tokenised). NOT yet deployed (see Goods tokens).

## Build (IMPORTANT)
Build the wasm with `RUSTFLAGS="--cfg near" cargo build --release --target wasm32-unknown-unknown` (or `cargo near build`).
Without `--cfg near`, near-sdk-env 0.1.9 compiles `panic_str` to a plain Rust panic: every rejection becomes a bare
`unreachable` trap with no message, so the runner could not read the API error codes (found in the sandbox).
Size: 907 KB without `strip = true`; 476 KB with strip and `-C target-cpu=mvp`; 385 KB after `wasm-opt -Oz` with the lowering passes (DEPLOY.md).
The final file is MVP-only wasm (no bulk-memory, sign-ext, sat-trunc; checked with `wasm-opt --mvp-features`), tested at `target/sokokuu_contract.opt.wasm`.

## Local sandbox tests (contract/sandbox, near-workspaces 0.22, no testnet, no real keys)
Run: build the wasm as above, then `cd sandbox && SIGNER_DIR=<dir> cargo test --release -- --nocapture --test-threads=1`.
`SIGNER_DIR` holds `sign.mjs` + `node_modules/@near-js/crypto`, `bs58` (kept out of the repo; signs with near-api-js).
Verified on-chain: the app's near-api-js vector (seed 1..32, 9C6h...) verifies (rejected only as EXPIRED because its expiry is
in 2026-02) and fresh near-api-js signatures for that key are accepted; replay (BAD_NONCE), tampered action, wrong signed
contract id, wrong chain id (BAD_SIG), past and too-far expiry (EXPIRED), non-relayer caller and player-signed advance
(FORBIDDEN, nonce not consumed); advance_clock and rebind_key relayer-only, rebind moves nonce and pts and the old key is
refused; pause blocks act; decide/crank accepted from `<merchant>.npc.<contract>`, margin clamped, refused for other
merchants and the owner. Gotcha: buy/sell etc. need `midday`, so the relayer must advance_clock from dawn first.

## Gas (sandbox, Tgas; per-call limit 300; typical 1 Tgas is about 0.0001 NEAR)
Whole `World` is one borsh blob, so cost grows with players. Players = registered before the call.
| players | act | advance_clock (max of 3 phases, includes day roll) | decide | rebind_key |
|---|---|---|---|---|
| 1 | 3.9 | 2.7 | 2.3 | 3.2 |
| 49 | 6.9 | 5.9 | 5.2 | 6.2 |
| 297 | 23.3 | 22.5 | 21.1 | 22.6 |
(Measured on the final MVP-only file; lowering memory.copy costs some gas versus the bulk-memory build.)
`act` measured with chama_create by a new player (registration included); a `buy` by an existing player is about 3.9 at 1 player.
Even at the 300-player cap everything is under 8% of the per-call limit.

## Deployed (testnet, 2026-11-10)
Contract `sokokuu.sokokuu-ken.testnet` (code sha256 ed98a459bf9016e6..., 385 KB), owner `sokokuu-ken.testnet`, relayer
`relayer.sokokuu-ken.testnet` (only key: function-call on the contract, methods act/advance_clock/rebind_key; bootstrap
full-access key deleted). Chain id `testnet`, seed 1. Live check: advance_clock 2.4 Tgas (0.00021 NEAR), first buy by a new
guest key via the relayer 4.3 Tgas (0.0004 NEAR); the signature came from near-api-js.
Gotcha: sign expiry must be within 2 min of chain time; compute `expires_ms` in real milliseconds.

## World snapshot views (added 2026-11-10, NOT yet deployed)
`world_snapshot()` (base64 Borsh of econ::World) and `world_hash()` (sha256[..16] hex). Pure views. Tested in the sandbox:
decodes with the econ crate, re-encodes to identical bytes, matches clock, supply and per-player pts, and the hash changes with state.
Size (JSON response): 2.1 KB at 1 player, 19.9 KB at 50, 111 KB at 300. Cost when run as a transaction (upper bound for view gas, limit 300 Tgas):
snapshot 2.1 / 5.5 / 23.6 Tgas, hash 2.1 / 4.5 / 17.4 Tgas at 1 / 49 / 297 players; both fit the view limit.
New wasm (390,652 bytes, MVP-only): sha256 60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2.
Currently deployed wasm is the older ed98a459bf9016e6 build (385 KB). All 4 sandbox tests and 42 unit tests pass on the new file.

## Reset to clean world (2026-11-10) and current deployment
`reset.sh` deleted and recreated `sokokuu.sokokuu-ken.testnet`, deployed the snapshot-view wasm (on-chain code sha256
60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2), `new(testnet, seed 1, relayer.sokokuu-ken.testnet)`.
World: day 0, dawn, 0 players; `world_hash` 9ffd75fef7e625cc0088f9aca605eef0 (decoded snapshot, 1,026 bytes, matches).

## Goods tokens (2026-11-11, NOT deployed)
One NEP-245 id per econ good, minted/burned to equal each player's `World` stock. Goods tokens are created lazily on first
mint, so no `new` call and no state-layout change: it is a plain code upgrade (DEPLOY.md UPGRADE).
- `act`: after the action the actor's pts and goods are synced (buy mints, sell burns, haggle/credit/repay follow the stock).
  `ChamaVote` snapshots everyone's (pts, stock) in memory and syncs whoever changed (a vote can pay the borrower).
- `advance_clock`: spoilage, daily consumption and loan settlement change stock; changed holders are synced goods-only.
  Eager sync stops after 40 mint/burn events or 150 Tgas used (NEAR caps all log text of one call at 16 KiB: 100 holders
  all changing once hit that limit). Skipped holders are corrected at their next `act`. So a goods balance can lag the world
  by at most one `advance_clock` batch for a player who has not acted since; `world_snapshot` is always exact.
- pts are still synced lazily at the player's next act (weekly chama dues move every member's pts; ~1 Tgas each if eager).
  So `mt_balance_of(pts)` can lag the World after a day roll, as before.
- Transfers: hook and `mt_transfer`/`mt_batch_transfer` panic `NON_TRANSFERABLE: pts and goods cannot be transferred`.
- Events: real NEP-245 `EVENT_JSON` with the `event` field present (checked by eye on the wasm in the sandbox, issue #1680 not hit):
  `EVENT_JSON:{"standard":"nep245","version":"1.0.0","event":"mt_mint","data":[{"owner_id":"74e6...","token_ids":["tomato"],"amounts":["3"],"memo":"sync"}]}`
- Views: `mt_token`, `mt_batch_supply` (null for unknown ids, `"0"` for a good nobody holds), `mt_metadata` (= `mt_metadata_base_by_token_id`:
  title, description, transferable=false), `mt_metadata_contract`.
- New wasm: sha256 `766ea8c248cd779af5bdc438b0ca1bd1f30da1fde8c8e2b479dec78ac8dbcee1`, 411,432 bytes (target/sokokuu_contract.goods.wasm).
  Hash was built with the recipe in JUDGES.md, but with binaryen 130 from this machine's npm; not compared to a second build yet.
- Tests: 46 unit (42 + 4 new) and 6 sandbox (adds goods mirror/events/non-transfer and a holders gas test) pass.
- Gas (sandbox): act 4.8/7.8/24.3 Tgas at 1/49/297 players (was 3.9/6.9/23.3); advance_clock 2.7/6.1/24.8; with 49 players all holding
  goods and all changing, advance_clock peaks at 40.5 Tgas, with 100 holders 42.9 (capped by the event budget).
- `sandbox/` needs `SIGNER_DIR` with `sign.mjs`; it was rebuilt this session outside the repo (seed 1..32 -> 9C6h..., matches the app key).
