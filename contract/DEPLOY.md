# Deploying to testnet (near-cli-rs 0.31.1)

Run on 2026-11-10 (deploy, then reset). Live state and the pending goods upgrade: NOTES.md "Current state" and DEPLOY_GOODS.md.
Testnet only, no real money. Never put keys in the repo. Mainnet: MAINNET.md (docs only).

## Cost (NEAR, testnet)
Storage staking is about 1 NEAR per 100 KB, and the optimised wasm is 385 KB, so about 3.8 NEAR stays locked in the contract
account, plus the game state (up to about 1 NEAR near 300 players). The script funds:
- `sokokuu.$ACCOUNT` with 6 NEAR (3.8 locked for code, about 1 for state, rest spare),
- `relayer.$ACCOUNT` with 2 NEAR (gas only: an `act` burns about 0.002 NEAR at worst; its key allowance is 1.8 NEAR).
Total 8 NEAR plus under 0.05 NEAR of creation and deploy gas; a 10 NEAR parent keeps about 1.9. Each merchant account
`<m>.npc.sokokuu.$ACCOUNT` later needs about 0.1 NEAR from the parent.

## Build (the flag is required; without it panic messages and API error codes are lost, see NOTES.md)
```
RUSTFLAGS="--cfg near -C target-cpu=mvp" cargo build --release --target wasm32-unknown-unknown      # 476 KB
wasm-opt -Oz --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int --enable-mutable-globals \
  --signext-lowering --llvm-nontrapping-fptoint-lowering --llvm-memory-copy-fill-lowering --strip-debug --strip-producers \
  target/wasm32-unknown-unknown/release/sokokuu_contract.wasm -o target/sokokuu_contract.opt.wasm   # 385 KB
```
(`wasm-opt` from binaryen, e.g. `npm i binaryen` and use `node_modules/.bin/wasm-opt`.) The final file has no bulk-memory, sign-ext or sat-trunc instructions: `wasm-opt --mvp-features <file> -o /dev/null` validates it, and `wasm-dis` shows none. It passes all 3 sandbox tests (SHA-256 starts ed98a459bf9016e6).

## Steps
1. Make the relayer key the runner will hold, outside the repo, and keep only its public half for the script:
   `node -e "const {KeyPair}=require('@near-js/crypto');const k=KeyPair.fromRandom('ed25519');require('fs').writeFileSync(process.env.RELAYER_KEY_FILE,k.toString(),{mode:0o600});console.log(k.getPublicKey().toString())"`
2. `export ACCOUNT=sokokuu-ken.testnet KEY_FILE=~/.near-credentials/testnet/sokokuu-ken.testnet.json RELAYER_PUBKEY=ed25519:...`
3. Check syntax without changing anything: `DRY_RUN=2 ./deploy.sh` (or `DRY_RUN=1` to only print).
4. `./deploy.sh`. It: creates and funds the two sub-accounts (bootstrap keys saved by near-cli in `~/.near-credentials/testnet`, not the repo);
   deploys the wasm signed by the contract account; calls `new {chain_id:"testnet", seed, relayer}` signed by `$ACCOUNT`
   (so the owner, who can pause, is the parent); adds a function-call key for `RELAYER_PUBKEY` on the relayer, limited to
   receiver `sokokuu.$ACCOUNT` and methods `act,advance_clock,rebind_key`; deletes the relayer's bootstrap full-access key;
   reads `clock` and lists the relayer's keys.
5. Merchant accounts: create `npc.sokokuu.$ACCOUNT` then `<merchant>.npc.sokokuu.$ACCOUNT` (signed by the account above each),
   each with a function-call key limited to `decide,crank` on `sokokuu.$ACCOUNT`.
6. Give the runner the relayer private key through its env (never commit). The contract id for runner and app is
   `sokokuu.$ACCOUNT`: the signing domain includes it, so the app must be built with the same id.

The script has been run with `DRY_RUN=2` (every command's syntax accepted by near-cli-rs 0.31.1) but never for real.

## UPGRADE (redeploy new code to the existing account; state is kept)
The goods upgrade has its own exact runbook with post-checks and rollback: DEPLOY_GOODS.md.
Safe only when the stored struct layout is unchanged (the 2026-11-10 upgrade only adds views `world_snapshot` and
`world_hash`). Never call `new` again. Needs no extra funds: the new wasm is a few KB larger (about 0.05 NEAR more storage).
1. Rebuild with the same MVP flags (Build section above) and check the hash against NOTES.md.
2. Deploy as the contract account (its key is in near-cli's legacy keychain from the first deploy):
```
near contract deploy sokokuu.sokokuu-ken.testnet use-file contract/target/sokokuu_contract.opt.wasm without-init-call \
  network-config testnet sign-with-legacy-keychain send
```
3. Verify: `near contract call-function as-read-only sokokuu.sokokuu-ken.testnet clock json-args '{}' network-config testnet now`
   (day/phase must be unchanged), then `world_hash` and `world_snapshot` the same way, and `near account view-account-summary sokokuu.sokokuu-ken.testnet network-config testnet now` for the new code hash.
4. Roll back by deploying the previous wasm the same way.

## New views (runner sync)
- `world_snapshot()` returns the Borsh bytes of `econ::World` as a base64 string (JSON string, standard alphabet with padding;
  near `Base64VecU8`). Decode base64, then `borsh` decode as `econ::world::World`. About 2 KB at 1 player, 20 KB at 50, 83 KB raw
  (111 KB of JSON) at 300 players.
- `world_hash()` returns 32 hex chars: the first 16 bytes of sha256 of those same Borsh bytes. Compare it with the runner's own
  hash of its World to detect drift, and fetch the snapshot only on mismatch.

## RESET (clean world, same accounts; repeat right before submission)
Deletes ONLY `sokokuu.$ACCOUNT` (its balance returns to `$ACCOUNT`), recreates it with 6 NEAR, deploys the wasm and calls `new`
signed by `$ACCOUNT` (owner). The relayer account and its function-call key are untouched and stay valid (the key is tied to the
receiver id string). All players, trades and clock progress are erased: the world is day 0, dawn, no players.
```
export ACCOUNT=sokokuu-ken.testnet KEY_FILE=$HOME/.near-credentials/testnet/sokokuu-ken.testnet.json
DRY_RUN=2 ./reset.sh                      # syntax check only
EXPECT_SHA=60f88915 ./reset.sh            # real reset; refuses a wasm whose sha256 does not start with EXPECT_SHA
```
Costs about 0.01 NEAR of gas. After a reset, the runner must reload its world (`world_hash` then `world_snapshot`), clear its
per-player nonces and re-register guests, and the app's guest keys start from nonce 0 again. The old bootstrap key file for the
contract account is renamed to `*.json.deleted-<time>` in `~/.near-credentials/testnet` (the new key replaces it).
`sandbox/tests/decode.rs` can decode a fetched snapshot: `SNAPSHOT_FILE=<base64 file> cargo test --release --test decode -- --nocapture`.
