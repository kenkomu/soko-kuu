# Mainnet: what it would take (docs only; after judging, not before 18 Nov 2026)

Not needed for the hackathon. Nothing here has been run. Soko Kuu stays testnet-only until every item in the security checklist
is done. No cash-out, token sale, prize or paid randomness on mainnet either; points stay non-transferable and cannot be bought.

Protocol prices used below are the same on mainnet and testnet: storage 10^19 yoctoNEAR per byte (1 NEAR per 100 KB, locked
while the bytes exist), minimum gas price 10^8 yoctoNEAR per gas (1 Tgas = 0.0001 NEAR; the price rises only when blocks are full).
Gas and storage figures are from the goods build (`766ea8c2...`), measured in the local sandbox unless marked "testnet".

## 1. Accounts Ken creates and funds
| Role | Example name | Created by | Fund with | Keys |
|---|---|---|---|---|
| Owner (parent; can pause) | `<name>.near` | Ken, in a wallet | the whole budget, spent from here | Ken's own, offline or hardware wallet |
| Contract | `game.<name>.near` | owner, in ONE batch transaction (section 4) | 10 NEAR (section 2) | depends on the upgrade option (section 4) |
| Relayer | `relayer.<name>.near` | owner | 5 NEAR to start (about a week near the cap, months at today's traffic) | exactly one function-call key (section 3) |
| Merchants (optional) | `npc.game.<name>.near`, `<merchant>.npc.game.<name>.near` | the contract account (sub-accounts of it) | about 0.1 NEAR each | function-call keys limited to `decide,crank` |

Merchant accounts must be created while the contract account still has a full-access key. If merchant decisions stay
off-chain (as on testnet today: no merchant accounts exist), skip them. The relayer key does not include `decide`.

## 2. Storage cost (paid by the contract account; players never pay)
- Code: 411,432 bytes = **4.11 NEAR** locked (a mainnet build will be within a few KB of this).
- State per player (sandbox, 2026-11-14): 674 bytes for a new player holding one good (world entry, nonce, id map, pts
  balance, one goods balance), plus 174 bytes per extra good held. Worst case, all 6 goods: about **1,544 bytes = 0.015 NEAR**.
- At the hard cap of 300 players: about 463 KB = **4.6 NEAR**. Chamas, loans, investments and revoked keys (about 73 bytes
  per `rebind_key`) add a little. Players are never deleted (`delete_account` only consumes a nonce), so state only grows.
- Fund the contract account with **10 NEAR**: 4.1 for code, up to 4.7 for state, the rest as buffer. If the balance falls
  below what the stored bytes need, every write fails (`LackBalanceForState`), so alarm on it.
- The caps (`MAX_PLAYERS` 300, `MAX_NEW_PER_DAY` 100) are what keep this bounded. Raising them grows storage linearly, and
  gas too, because the whole `World` is one blob read and written on every call. Going far past 300 needs a storage redesign
  (per-player records), not a bigger cap.

## 3. Relayer key: limited to `act`, `advance_clock`, `rebind_key`
```
near account add-key relayer.<name>.near grant-function-call-access --allowance '5 NEAR' \
  --contract-account-id game.<name>.near --function-names 'act,advance_clock,rebind_key' \
  use-manually-provided-public-key ed25519:<runner key> network-config mainnet <sign with the relayer's bootstrap key> send
near account delete-keys relayer.<name>.near public-keys ed25519:<bootstrap key> network-config mainnet <sign> send
near account list-keys relayer.<name>.near network-config mainnet now      # exactly one FunctionCall key
```
(Same shape as `deploy.sh`, which was syntax-checked on near-cli-rs 0.31.1 for testnet.) The key cannot transfer funds,
deploy, pause, or call any other contract. An allowance cannot be raised in place: add a new key with a fresh allowance, move
the runner to it, then delete the old key. Keep the relayer balance near one or two weeks of gas, so a leaked key costs little.

## 4. Owner and upgrade path
How it works today: owner = whoever called `new`; it can only `pause`/`unpause`. There is no `owner()` view, no owner transfer,
no `upgrade` or `migrate` method, and the state is not versioned. Upgrades are plain redeploys with the contract account's
full-access key (JUDGES.md caveat).

**Init must be atomic on mainnet.** `new` is public until the first call. On testnet, deploy and `new` were separate
transactions (`deploy.sh`, `reset.sh`), so anyone could have called `new` in between and become owner with their own relayer.
On mainnet, do create, fund, deploy and init in one batch signed by the owner (so owner = the batch signer). The syntax below
was checked with `--help` (near-cli-rs 0.31.1); it was not sent:
```
near transaction construct-transaction <name>.near receiver-id game.<name>.near \
  add-action create-account \
  add-action transfer '10 NEAR' \
  add-action deploy-contract use-file target/sokokuu_contract.mainnet.wasm without-init-call \
  add-action function-call new json-args '{"chain_id":"mainnet","seed":<seed>,"relayer":"relayer.<name>.near"}' prepaid-gas '30 Tgas' attached-deposit '0 NEAR' \
  skip network-config mainnet sign-with-keychain send
```
For option A below, add `add-action add-key ... grant-full-access ...` with the upgrade key before `skip`. Afterwards:
`chain_id` view = `"mainnet"`, `relayer` view = the relayer, `new` again fails "already been initialized".

Upgrade options:
- **A. Keep one full-access key on the contract account**, held offline. Same honest caveat as testnet. This is the least work.
  The near-cli-rs on this machine has no `sign-with-ledger`, so use a wallet with hardware-wallet support or a near-cli
  built with the ledger feature.
- **B. Recommended before real users (code change, after judging):** owner-only `upgrade(code)` that deploys and calls
  `migrate()`, a state version field, an `owner()` view, and a two-step owner transfer (ideally to a multisig). Then delete
  every full-access key on the contract account, so only the owner can change code, and only through a visible call.
- **C. Lock it** (no keys, no upgrade method): strongest guarantee, but no bug fixes. Only after an external review.

Every upgrade: rehearse first in the sandbox on mainnet-like state (as in DEPLOY_GOODS.md), deploy a file built from a clean
commit (never a working tree), and record the hash. The live testnet build `60f88915...` is not reproducible from git for
exactly that reason (JUDGES.md).

## 5. Gas cost per day (paid by the relayer)
Per call (tokens burnt, roughly Tgas x 0.0001 NEAR):
| players | `act` (goods build) | `advance_clock` |
|---|---|---|
| 2 (testnet today) | 0.0005 NEAR | 0.00027 NEAR (testnet, measured) |
| 49 | 0.0008 | 0.0006 |
| 297 | 0.0024 | 0.0025 (peak 0.0043 when 100 holders' goods all change) |

The clock runs about every 10 minutes, so 144 calls a day:
| Scenario | clock / day | acts / day | total / day |
|---|---|---|---|
| Today's testnet (2 players) | 0.04 NEAR | ~0 | **~0.04 NEAR** (testnet: relayer allowance went 1.8 -> 1.656 NEAR in 4 days = 0.036/day) |
| 50 players, 20 actions each | 0.09 | 1,000 x 0.0008 = 0.8 | **~0.9 NEAR** |
| 300 players (cap), 20 actions each | 0.36 (up to 0.62) | 6,000 x 0.0024 = 14.4 | **~15 NEAR** |

Levers: a slower clock (`PHASE_SECS`) cuts the fixed part, and the per-act cost is the World-blob design (above). The runner
attaches `GAS_TGAS=100` per call. On testnet the allowance fell by about the burnt cost, not the prepaid 100 Tgas. Re-check
this with a few calls on mainnet before opening, in case refund rules differ.

## 6. Chain id "mainnet" in the signed bytes, and what the runner and app must change
The player signs `sokokuu/v1|mainnet|game.<name>.near|<pubkey>|<nonce>|<expires_ms>|<action_json>`. The contract uses the
`chain_id` string given to `new`; nothing checks it against the real network, so the operator must pass `"mainnet"`. A
testnet signature fails on mainnet with `BAD_SIG` (both the chain id and the contract id differ). The sandbox tests already
cover the wrong chain id and the wrong contract id.

Runner (`runner` owner):
- Env: `CHAIN_ID=mainnet`, `CONTRACT_ID=game.<name>.near`, `RELAYER_ACCOUNT_ID=relayer.<name>.near`, `RELAYER_KEY_FILE`,
  and `NEAR_RPC_URL` set explicitly to a mainnet RPC. It must be set: the code falls back to the testnet URL
  (`runner/rs/src/testnet.rs:35`). The public `rpc.mainnet.near.org` is rate-limited, so use a provider. Raise `MIN_BALANCE_NEAR`.
  `MODE=testnet` is the code's name for "on-chain mode" and stays as is (renaming is cosmetic). `GAS_TGAS=100` is enough.
- Code: at startup, compare the contract's `chain_id()` and `relayer()` views with `CHAIN_ID` and `RELAYER_ACCOUNT_ID`,
  and refuse to start on a mismatch (today `ping` only checks the key, `testnet.rs:88`). On mainnet, fail closed instead of
  silently dropping to demo mode when the chain is down. Start with an empty `DATA_DIR`, never testnet `state.json`.
  Alarm on the contract account's balance versus its storage, and on the relayer allowance.

App (`app` owner):
- The app signs with whatever `chain_id`/`contract_id` the runner's `/v1/health` returns (`app/lib/state/providers.dart:172`).
  For mainnet, pin the expected values at build time (`--dart-define`) and refuse to sign on a mismatch.
- `API_BASE` points to the mainnet runner. Remove any "testnet" wording; keep "Points are for play only. They can't be
  cashed out." Add a mainnet signing vector next to the testnet near-api-js vector (day-1 test).
- It is a new world: testnet progress and keys do not carry over, and nonces start at 0. Web keys are throwaway demo keys
  (SECURITY_UX.md); on mainnet that trade-off needs a fresh look.

## 7. Security review checklist (all before mainnet)
- [ ] External review of `contract/src/lib.rs` and `econ/` (both are the referee). Until then the README says "not audited".
- [ ] `cargo audit` on the contract and econ lockfiles; toolchain pinned; reproducible build from a clean commit; hash recorded.
- [ ] 46 unit tests, the sandbox tests and an upgrade rehearsal pass on the exact mainnet wasm, with `"mainnet"` as chain id in the sandbox signing tests.
- [ ] Built with `--cfg near`; one real rejection on mainnet returns its `<CODE>: message`.
- [ ] Atomic init (section 4); `chain_id`, `relayer` and `is_paused` views checked; re-init refused.
- [ ] Keys: `list-keys` on every account. Relayer: one function-call key (`act,advance_clock,rebind_key`, bounded allowance). Merchants: `decide,crank` only. Owner key offline. Contract account keys per the chosen upgrade option.
- [ ] Relayer trust stated: it owns the clock and ordering, can censor, and `rebind_key` lets it move any player's record to a new key without that player's signature (needed for lost devices). On mainnet: rebind only after the runner's email proof, rate-limited and logged; consider a delay or an owner co-sign.
- [ ] Storage: contract funded for code plus the capped state (section 2), with a balance alarm.
- [ ] Gas: worst case per call stays far below 300 Tgas at the cap (act 24 Tgas, `advance_clock` peak 43 Tgas); logs stay under the 16 KiB per-call limit (40-event cap in eager goods sync).
- [ ] Pause drill: `pause` makes `act` fail `FORBIDDEN`; `unpause` restores it.
- [ ] Non-transferability: `mt_transfer`/`mt_batch_transfer` panic, transfer hook panics, no payable method, `transferable:false` in all token metadata. Explorers and wallets may still list the ids as tokens: say clearly they are game points.
- [ ] Privacy: on mainnet, player ids (hex of public keys) and every action are public forever; say so in the consent text. Email stays off-chain and hashed.
- [ ] A Kenyan legal check before real NEAR is involved, even though points can't be bought, transferred or cashed out.
