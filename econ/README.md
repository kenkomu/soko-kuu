# econ

Soko Kuu economy rules as a pure Rust crate. Integer pts only, no NEAR deps, no wall clock, deterministic (seeded). `contract/` and `runner/` both run the same `World::apply`, so rules cannot drift between them.

## Modules
| Module | Contents |
|---|---|
| `pricing` | `GOODS` (6 goods), `quote`/`quote_ref` (stock factor, event modifiers, spread, mid capped at +-20% per day via `ref_mid`), haggle discount, fee, wholesale, `mul_div` (checked u128 maths) |
| `events` | `EventKind` (Ukame, Fuel, Road, Festival, Harvest, Glut), `Event`, `modifiers`, `maybe_spawn` |
| `credit` | tiers and limits, interest (merchant 6%, chama 4%), loan length (5 days), caps: 2 open guarantees, 5 open loans, 5 investments |
| `chama` | savings group (max 8), weekly contribution, loan offers with votes, `tally`, season payout |
| `action` | `Action` enum (the signed `act` payload), `ErrorCode`, `Phase`, `canonical_json` |
| `world` | `World`, `Config`, `Receipt`, `apply`, `advance` |
| `sim` | bot players, `simulate`, `stability`, `Frame` (used for `/v1/sim`) |
| `rng` | small seeded PRNG |

## Public API
- `World::new(Config)`; `Config { seed, players, merchants, start_pts, merchant_cash, stipend, random_events }`.
- `world.apply(player_id, &Action) -> Result<Receipt, ErrorCode>`: the single rule engine. On `Err` the world is unchanged. `Receipt` carries `pts_delta`, `ledger` lines (cause + pts) and event text.
- `world.advance()` (also `Action::Advance {}`): moves Dawn -> Midday -> Dusk -> next Dawn; the dusk step runs the daily tick (events, stall levy, townsfolk demand, restock, reference-mid roll, stipend, rent, loan defaults, investment maturity).
- `world.quote(merchant_idx, good) -> Option<Quote>` (`mid`, `ask`, `bid`, `stock`, `why` lines for the UI).
- Reads: `supply()`, `net_worth(pid)`, `outstanding(pid)`, `price_index_bp()`, `solvent_merchants()`.
- `sim::simulate(cfg, days, &scripted_events) -> (World, Vec<Frame>)`, `sim::stability(seeds, days) -> StabilityReport`.
- Feature `borsh`: Borsh derives on all state types (`World`, `Config`, `Merchant`, `Player`, `Loan`, ...). Serde is always on (JSON for the runner and `canonical_json`).

## Commands
```
cargo test                      # 32 tests
cargo test --features borsh     # 34 tests (adds Borsh round-trip and size report)
cargo run --release --bin econ_sim -- stability 100 60      # 100 seeds x 60 days, JSON report
cargo run --release --bin econ_sim -- sim <seed> <days> [events.json]   # daily frames as JSON; events.json = [{"day":3,"kind":"ukame","magnitude":80}] (kind is lowercase)
cargo run --release --example trace   # seed 3, no random events: stall index 2 cash, stock per good, treasury, active events on days 8-12, 16, 20
cargo run --release --example dist    # seed 3: players total, each stall cash, treasury, stock, price index at days 2,5,10,30,60
```
The test `hundred_seed_drift_within_15pct` runs the stability check and fails if any day drifts more than 1500 bp.

## Money rules
Closed loop. Total supply (players + stalls + chamas + treasury) is conserved except two explicit flows.
- Faucet (`minted`): daily stipend, thermostat-controlled. It replaces what the sinks burned plus 10% of the gap to `target_supply`, capped at 3x the nominal stipend (1,500 x players). Paid with half the treasury equally to all players.
- Sinks (`burned`): 2% fee on sells, and daily stall rent (0.5% of stall cash, 2% when supply is above target).
- Not burned, only moved: the stall levy (30% of stall cash above `RICH_CASH` = 140,000 goes to the treasury), townsfolk purchases and stall restocking (both pass through the treasury).
- Anti-bleed: a stall with cash under `BID_FLOAT` (60,000) lowers its bids (down to 30%); a stall never spends its last `RESTOCK_RESERVE` (35,000) on wholesale; townsfolk favour the poorest stall.
- Caps: 2 open guarantees, 5 open loans, 5 investments per player; tier limits 9k/24k/60k/135k; qty per trade at most 20; mid price moves at most 20% per day.
- No cash-out, no transfers between players, no randomness paid for. Pts are non-transferable. Random events come from the seeded world RNG and only move prices and restock.

## Stability numbers (100 seeds, 60 days, default config)
Worst day drift 105 bp (1.05%), mean final drift 28 bp, worst final drift 88 bp, price index 5,740 to 21,814 bp, at least 3 of 4 stalls solvent (cash >= 20,000) on every day of every seed.

## How the others use it
- `contract/` depends on it with `features = ["borsh"]`, stores a `World` (Borsh), verifies the signed `act`, calls `econ::apply` / `econ::advance`, and reflects `Receipt` into events.
- `runner/` links it (serde/JSON) for the same rules in demo mode, `/v1/sim` (`sim::simulate` frames, scripted events) and quote previews; it supplies the merchant decisions and voice lines, never prices.

## How the economy works, in plain words
Soko Kuu is a small market in a Kenyan town. Everyone plays with **points** (pts). Points are for play only: they cannot be cashed out, sent to another player, or won by chance.

- **Where points come from.** Every day each player gets a small stipend (about 1,500 pts). The game adjusts the stipend so the total stays near its target: when the market has burned points it hands out a bit more, when there are too many it hands out less. That is the only way new points enter.
- **Where points go.** Selling costs a 2% fee, and each stall pays daily rent (0.5% of its cash, 2% when it is overstocked). Those points are removed from the game. Rich stalls are also taxed 30% of cash above 140,000 pts, which goes to the town treasury and flows back to players.
- **Prices.** Prices follow fixed rules, not opinions. Supply and demand move them, and events (drought, floods, fuel prices) nudge them. A price can never move more than 20% in one day. No AI sets prices.
- **Credit.** Good behaviour earns reputation: +1 for each loan repaid on time, -3 for a default. Reputation unlocks four tiers with borrowing limits of 9k, 24k, 60k and 135k pts. A loan lasts 5 days; merchant loans cost 6% and chama loans 4%. A player may hold at most 5 open loans and 2 guarantees, so one bad bet cannot sink everyone.
- **Chama (savings group).** Up to 8 friends join a chama with a 2,000 pts share and add 5% of their pts each week (at most 3,000). Members vote on loan offers, and the majority decides. Savings and loans stay inside the group, and members share the payout at season end.
- **Closed loop.** Total points are counted every day: they only move between players, stalls, chamas and the treasury, apart from the stipend coming in and the fee and rent going out. There is no cash-out, no token and no transfer between players. Across 100 test worlds of 60 days each, the total never drifted more than about 1% from its target, and at least 3 of 4 stalls always stayed in business.
