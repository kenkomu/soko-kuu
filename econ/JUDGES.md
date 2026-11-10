# Soko Kuu economy: what limits it (for judges)

Points (pts) are play money. They cannot be cashed out, sent to another player, or won by chance. All rules live in this crate (`econ/`) and are plain integer code. The contract and the runner run the same `World::apply`, so they cannot disagree. No AI sets prices.

## The closed-loop guarantee

Every pt sits in exactly one place: a player, a stall, a chama (savings group) or the town treasury. Trades, loans, levies and restocking only move pts between those places. Only two flows change the total, and both are counted in the world state (`minted`, `burned` in `src/world.rs`):

- In: the daily stipend (`minted`).
- Out: the 2% sell fee and daily stall rent (`burned`).

There is no withdraw action, no player-to-player transfer and no token. A thermostat steers the total back to its starting value (`target_supply`) every day (`world.rs`, dusk step 7). The mint is the pts burned that day plus 10% of the gap to target, never below 0, and never above 3 times the nominal stipend pool (3 x 1,500 x players). When supply is above target, rent rises from 0.5% to 2%.

## Every limit, with its constant

Defaults come from `Config::default()` in `src/world.rs`: 24 players, 4 stalls, 20,000 start pts per player, 120,000 cash per stall, stipend 1,500.

| Rule | Value | Where |
|---|---|---|
| Daily stipend (nominal, per player) | 1,500 pts, scaled by the thermostat | `Config.stipend`, `world.rs` step 7 |
| Stipend ceiling (all players per day) | 3 x stipend x players | `world.rs` step 7 (`clamp(0, 3 * ...)`) |
| Thermostat correction | 10% of the gap to target per day | `world.rs` step 7 (`/ 10`) |
| Sell fee, burned | 200 bp = 2% | `pricing::FEE_BP` |
| Stall rent, burned | 0.5% of stall cash per day (50 bp); 2% (200 bp) when supply is above target | `world.rs` step 7 (`rent_bp`) |
| Trade size | at most 20 units per trade | `pricing::MAX_QTY` |
| Price move per day | mid price within +-20% of the day's start price | `pricing::MAX_DAILY_MOVE_BP` = 2,000 bp (`quote_ref`) |
| Price floor and ceiling | mid between 1/4 and 4 times the good's base price | `pricing::quote_ref` |
| Stock effect on price | factor between 50% and 200%, linear in stock | `pricing::stock_factor_bp` |
| Buy/sell spread | 800 bp (8%) each side of mid, at most 50% | `pricing::BASE_SPREAD_BP` |
| Wholesale (stall restock) | 70% of mid | `pricing::WHOLESALE_BP` |
| Haggle | 2% to 6% plus 1% per credit tier, once per player per merchant/good per day, discount never above 20% | `pricing::haggle_discount_bp`, `apply_discount` |
| Stall rich-levy | 30% of stall cash above 140,000 goes to the treasury (moved, not burned) | `world::RICH_CASH`, `world.rs` step 5a |
| Stall anti-bleed | below 60,000 cash a stall lowers its bids, down to 30% | `world::BID_FLOAT`, `world.rs` bid code |
| Stall restock reserve | a stall keeps at least 35,000 and spends no further on wholesale | `world::RESTOCK_RESERVE` |
| Treasury payout | half the treasury shared equally among players each day | `world.rs` step 7 (`treasury / 2`) |
| Credit tiers (reputation score) | tiers start at score 0, 3, 8, 15 | `credit::TIER_MIN_SCORE` |
| Borrowing limits per tier | 9,000 / 24,000 / 60,000 / 135,000 pts outstanding | `credit::TIER_LIMIT` |
| Loan length | 5 days | `credit::LOAN_DAYS` |
| Interest | merchant loans 6%, chama loans 4% | `credit::MERCHANT_INTEREST_BP` = 600, `CHAMA_INTEREST_BP` = 400 |
| Reputation | +1 for on-time repayment, -3 for a default | `credit::repay_delta`, `DEFAULT_PENALTY` |
| Open loans per player | 5 | `credit::MAX_OPEN_LOANS` |
| Open guarantees per player | 2 (guarantor must be tier 1 or higher) | `credit::MAX_OPEN_GUARANTEES`, `can_guarantee` |
| Investments per player | 5 open; 7 days; 4% yield | `credit::MAX_INVESTMENTS`, `world::INVEST_DAYS`, `INVEST_YIELD_BP` |
| Chama size | 8 members | `chama::MAX_MEMBERS` |
| Chama join share | 2,000 pts | `chama::JOIN_SHARE` |
| Chama contribution | 5% of member pts, at most 3,000, every 7 days | `chama::CONTRIB_BP` = 500, `CONTRIB_CAP`, `CONTRIB_EVERY_DAYS` |
| Chama loan offer | majority vote, expires after 1 day | `chama::OFFER_DAYS`, `chama::tally` |
| Season end | chama cash shared out by shares; no earlier withdrawal | `World::season_close` |

Random events (drought, fuel, road, festival, harvest, glut) come from the seeded world RNG and only move prices and restocking. They never pay anyone (`src/events.rs`).

## Reproduce the stability numbers

From `econ/`:

```
cargo test --release                    # 32 tests, all pass
cargo test --release --features borsh   # 34 tests, all pass (adds Borsh round-trip and size report)
cargo run --release --bin econ_sim -- stability 100 60
```

The last command runs 100 seeds for 60 days each with default config and prints (output of 10 Nov 2026):

```
worst_abs_drift_bp   105     worst single day, any seed: 1.05% from target supply
mean_final_drift_bp  28
worst_final_drift_bp 88
min_price_index_bp   5740    price index never below 57.4% of base
max_price_index_bp   21814   never above 218.1% of base
min_solvent_merchants 3      at least 3 of 4 stalls hold 20,000+ pts every day of every seed
```

The tests `sim::tests::hundred_seed_drift_within_15pct` and `stability_guarantees_pinned` fail the build if drift exceeds 1,500 bp (15%) or fewer than 3 stalls stay solvent. The run is deterministic: same seeds, same numbers. Single worlds can be inspected with `econ_sim sim <seed> <days> [events.json]` and `cargo run --release --example dist`.
