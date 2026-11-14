# contract notes

## Current state (checked 2026-11-14, read-only RPC)
- LIVE on testnet: `sokokuu.sokokuu-ken.testnet`, code sha256 `60f88915...6ecd2` (base58 `7XXwp4LaAPREriPkDBtSRWQUnPuYFSux93h7wPgkWBZK`,
  390,652 bytes) = `target/sokokuu_contract.opt.wasm`. This is the snapshot-view build WITHOUT goods tokens: only `pts` is a NEP-245 id,
  `mt_transfer` panics `NON_TRANSFERABLE: pts cannot be transferred`, `mt_metadata_contract` is `MethodNotFound`, `mt_supply tomato` is `null`.
  World: day 172+, 2 players. Account: 5.997 NEAR, storage_usage 395,158-395,177 bytes (about 3.95 NEAR locked), one full-access key.
  Relayer key allowance 1.656 NEAR (was 1.8 on 2026-11-10).
- NOT deployed: the goods build `target/sokokuu_contract.goods.wasm`, sha256 `766ea8c2...cbee1` (base58 `8yJybwzyYjRQ3wUukuMwwQQkiFKLbT8kH6cRCwqxXcXA`).
  Runbook: DEPLOY_GOODS.md (Ken runs it). Rehearsed in the sandbox (old wasm, then goods over it, rollback, re-upgrade): state, clock and world_hash kept.
- Reproducible: the goods build from git (commit `02b32aa` = HEAD for contract/ and econ/, rebuilt 2026-11-14 from a clean export: identical).
  The live build is NOT reproducible from any commit (`d456e6e` builds `2be6b0bf...`; the 2026-11-10 working tree was never committed).
- Tests 2026-11-14: committed source 46/46 unit tests pass (clean `git archive` export). In the working tree, 45/46: `buy_at_dawn_rejected` fails
  because of "pending econ change A" (uncommitted econ edits drop the midday-only trading rule). Not a contract bug; contract logic and that test
  are unchanged on purpose: both wasm builds enforce midday-only trading. If change A lands, the test, the wasm hash and the on-chain rules
  must be updated together (new build, new deploy), or the runner's rules and the contract's rules will disagree (dawn/dusk trades: WRONG_PHASE on chain).
- Mainnet: not planned for the hackathon; see MAINNET.md.

## First-hour check (done)
`near-sdk-contract-tools` 4.0.0 compiles against near-sdk 5.30.1 (lockfile; Cargo.toml asks `5.18`+, features `legacy`).
No pin or hand-written NEP-245 needed. We use its Nep245Controller (mint/burn/balance/supply) and a TransferHook
(`DenyTransfer`) that panics, so no internal or external transfer can ever succeed. We did NOT use
`#[derive(MultiToken)]`: it would expose real `mt_transfer`/resolve methods. Instead `mt_transfer` and
`mt_batch_transfer` are hand-written and always panic `NON_TRANSFERABLE`; standard views `mt_balance_of`,
`mt_batch_balance_of`, `mt_supply` are exposed. Goods build only (not live yet): also `mt_token`, `mt_batch_supply`, `mt_metadata`, `mt_metadata_base_by_token_id`, `mt_metadata_contract`. NEP-245 mint/burn events come from the controller.
Token ids: `pts`; the goods build adds one per good (`tomato maize sukuma onion fish charcoal` = econ good ids). Stakes stay in the econ `World`.

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
- Deployed to testnet since 2026-11-10 (see Current state). `overflow-checks` on in release.
- Events are plain log lines, not NEP-297 JSON.
- Goods mirror PLAYER-held stock only; merchant stock stays in the World (not tokenised). Goods tokens are NOT deployed (see Goods tokens).

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

## First deploy (testnet, 2026-11-10; code superseded the same day by the reset below)
Contract `sokokuu.sokokuu-ken.testnet` (code sha256 ed98a459bf9016e6..., 385 KB), owner `sokokuu-ken.testnet`, relayer
`relayer.sokokuu-ken.testnet` (only key: function-call on the contract, methods act/advance_clock/rebind_key; bootstrap
full-access key deleted). Chain id `testnet`, seed 1. Live check: advance_clock 2.4 Tgas (0.00021 NEAR), first buy by a new
guest key via the relayer 4.3 Tgas (0.0004 NEAR); the signature came from near-api-js.
Gotcha: sign expiry must be within 2 min of chain time; compute `expires_ms` in real milliseconds.

## World snapshot views (added 2026-11-10; deployed by the reset below, live)
`world_snapshot()` (base64 Borsh of econ::World) and `world_hash()` (sha256[..16] hex). Pure views. Tested in the sandbox:
decodes with the econ crate, re-encodes to identical bytes, matches clock, supply and per-player pts, and the hash changes with state.
Size (JSON response): 2.1 KB at 1 player, 19.9 KB at 50, 111 KB at 300. Cost when run as a transaction (upper bound for view gas, limit 300 Tgas):
snapshot 2.1 / 5.5 / 23.6 Tgas, hash 2.1 / 4.5 / 17.4 Tgas at 1 / 49 / 297 players; both fit the view limit.
New wasm (390,652 bytes, MVP-only): sha256 60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2.
(At the time the deployed wasm was the older ed98a459bf9016e6 build; the reset replaced it.) All 4 sandbox tests and 42 unit tests pass on the new file.

## Reset to clean world (2026-11-10) and current deployment
`reset.sh` deleted and recreated `sokokuu.sokokuu-ken.testnet`, deployed the snapshot-view wasm (on-chain code sha256
60f889152edbf6acf55c924bae57cbb98d6a0be4d6ee29376f337dc77486ecd2), `new(testnet, seed 1, relayer.sokokuu-ken.testnet)`.
World: day 0, dawn, 0 players; `world_hash` 9ffd75fef7e625cc0088f9aca605eef0 (decoded snapshot, 1,026 bytes, matches).

## Goods tokens (2026-11-11, NOT deployed as of 2026-11-14; runbook DEPLOY_GOODS.md)
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
  Hash was built with the recipe in JUDGES.md (binaryen 130 from npm). Second build on 2026-11-14 from a clean `git archive HEAD` export
  in another directory (with the path remap): byte-identical.
- Tests: 46 unit (42 + 4 new) and 6 sandbox (adds goods mirror/events/non-transfer and a holders gas test) pass.
- Gas (sandbox): act 4.8/7.8/24.3 Tgas at 1/49/297 players (was 3.9/6.9/23.3); advance_clock 2.7/6.1/24.8; with 49 players all holding
  goods and all changing, advance_clock peaks at 40.5 Tgas, with 100 holders 42.9 (capped by the event budget).
- `sandbox/` needs `SIGNER_DIR` with `sign.mjs`; it was rebuilt this session outside the repo (seed 1..32 -> 9C6h..., matches the app key).
- Panic text on this build: `NON_TRANSFERABLE: pts and goods cannot be transferred` (the live build says `pts cannot be transferred`).
- Upgrade rehearsal (2026-11-14, scratch near-workspaces test, not in the repo; Rust-signed throwaway keys): deploy of the goods wasm over the
  old wasm's state by the contract account: 30.0 Tgas (on chain storage grows by the file size difference, +20,780 bytes), `clock`/`world_hash`/`supply`/`pts_of`/`nonce_of` unchanged; new views
  answer; pre-upgrade goods minted at the holder's next act (5.7 Tgas); rollback keeps state (goods balances freeze), re-upgrade heals them.
- Storage per player on the goods build (same rehearsal): 674 bytes for a new player holding one good (world entry, nonce, id, pts and one
  goods balance), plus 174 bytes per extra good held; worst case 6 goods = about 1,544 bytes (0.015 NEAR). At the 300 cap about 463 KB.
