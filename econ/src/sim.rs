//! Seeded simulation with simple bot players; used for the stability test and `/v1/sim` frames.
use crate::action::*;
use crate::events::*;
use crate::pricing::*;
use crate::rng::Rng;
use crate::world::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Frame {
    pub day: u32,
    pub supply: Pts,
    /// signed drift vs initial supply, in bp
    pub drift_bp: i64,
    pub price_index_bp: u64,
    pub minted: Pts,
    pub burned: Pts,
    pub treasury: Pts,
    pub solvent_merchants: usize,
    pub open_loans: usize,
    pub defaults: u32,
    pub events: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptedEvent { pub day: u32, pub kind: EventKind, pub magnitude: u32 }

pub fn drift_bp(supply: Pts, target: Pts) -> i64 { ((supply as i128 - target as i128) * BP as i128 / target.max(1) as i128) as i64 }

fn act(w: &mut World, pid: &str, a: Action) -> bool { w.apply(pid, &a).is_ok() }

fn setup_chamas(w: &mut World) {
    let ids: Vec<String> = w.players.keys().cloned().collect();
    for grp in ids.chunks(4) {
        if grp.len() < 3 { continue; }
        if !act(w, &grp[0], Action::ChamaCreate {}) { continue; }
        let cid = w.players[&grp[0]].chama.clone().unwrap();
        for m in &grp[1..] { act(w, m, Action::ChamaJoin { chama_id: cid.clone() }); }
    }
}

fn bot_turn(w: &mut World, pid: &str, rng: &mut Rng) {
    // repay
    let loans: Vec<(u64, Pts)> = w.loans.values().filter(|l| l.borrower == pid && l.status == crate::credit::LoanStatus::Open).map(|l| (l.id, l.owed)).collect();
    for (id, owed) in loans { if w.players[pid].pts >= owed + 2_000 || rng.below(100) < 10 { act(w, pid, Action::CreditRepay { loan_id: id }); } }
    // vote
    if let Some(cid) = w.players[pid].chama.clone() {
        if let Some(o) = w.chamas[&cid].offer.clone() {
            if o.borrower != pid && !o.votes.contains_key(pid) {
                let v = if rng.below(100) < 75 { Vote::Yes } else { Vote::No };
                act(w, pid, Action::ChamaVote { offer_id: o.id, vote: v });
            }
            // guarantee a chama-mate's loan sometimes
        }
        let cand = w.loans.values().find(|l| l.borrower != pid && l.guarantor.is_none() && l.status == crate::credit::LoanStatus::Open
            && w.players.get(&l.borrower).and_then(|b| b.chama.as_ref()) == Some(&cid)).map(|l| (l.borrower.clone(), l.id));
        if let Some((b, id)) = cand { if rng.below(100) < 20 { act(w, pid, Action::Guarantee { borrower: b, loan_id: id }); } }
    }
    // sell: best bid among goods held
    let held: Vec<(String, u32)> = w.players[pid].stock.iter().filter(|(_, q)| **q > 0).map(|(g, q)| (g.clone(), *q)).collect();
    for (g, q) in held {
        let gd = good(&g).unwrap();
        let best = (0..w.merchants.len()).filter_map(|mi| w.quote(mi, &g).map(|qq| (mi, qq.bid))).max_by_key(|(_, b)| *b).unwrap();
        let ratio = best.1 * BP / gd.base;
        if ratio >= 11_000 || rng.below(100) < 35 {
            let n = q.min(MAX_QTY);
            act(w, pid, Action::Sell { merchant: w.merchants[best.0].id.clone(), good: g, qty: n, min_unit_price: None });
        }
    }
    // buy cheapest relative to base
    let mut best: Option<(usize, &'static GoodDef, Pts, u64)> = None;
    for mi in 0..w.merchants.len() {
        for g in GOODS.iter() {
            let q = w.quote(mi, g.id).unwrap();
            if q.stock == 0 { continue; }
            let ratio = q.ask * BP / g.base;
            let ratio = ratio + rng.below(300);
            if best.is_none_or(|b| ratio < b.3) { best = Some((mi, g, q.ask, ratio)); }
        }
    }
    if let Some((mi, g, ask, ratio)) = best {
        let mname = w.merchants[mi].id.clone();
        if ratio <= 13_000 || rng.below(100) < 30 {
            act(w, pid, Action::Haggle { merchant: mname.clone(), good: g.id.into() });
            let budget = w.players[pid].pts * 4 / 10;
            let mut qty = (budget / ask).min(12) as u32;
            if qty == 0 && rng.below(100) < 30 { // short of cash: ask for credit
                qty = 3;
                act(w, pid, Action::CreditRequest { merchant: mname.clone(), good: g.id.into(), qty });
            } else if qty > 0 {
                act(w, pid, Action::Buy { merchant: mname, good: g.id.into(), qty, max_unit_price: ask + ask / 10 });
            }
        }
    }
    // invest surplus
    if w.players[pid].pts > 24_000 && rng.below(100) < 50 {
        let mi = (0..w.merchants.len()).min_by_key(|i| w.merchants[*i].cash).unwrap();
        act(w, pid, Action::Invest { merchant: w.merchants[mi].id.clone(), pts: 10_000 });
    }
}

/// Run `days` days with bots. Returns one frame per day (after the daily tick).
pub fn simulate(cfg: Config, days: u32, scripted: &[ScriptedEvent]) -> (World, Vec<Frame>) {
    let mut w = World::new(cfg.clone());
    for s in scripted { w.inject(Event::new(s.kind, s.day, s.magnitude)); }
    setup_chamas(&mut w);
    w.target_supply = w.supply();
    let target = w.target_supply;
    let mut rng = Rng::new(cfg.seed.wrapping_mul(7919));
    let mut frames = Vec::with_capacity(days as usize);
    for _ in 0..days {
        act(&mut w, "p000", Action::Advance {}); // dawn -> midday
        let ids: Vec<String> = w.players.keys().cloned().collect();
        for _ in 0..2 { for id in &ids { bot_turn(&mut w, id, &mut rng); } }
        act(&mut w, "p000", Action::Advance {}); // midday -> dusk
        let r = w.apply("p000", &Action::Advance {}).expect("advance"); // dusk -> dawn: tick
        let s = w.supply();
        frames.push(Frame {
            day: w.day, supply: s, drift_bp: drift_bp(s, target), price_index_bp: w.price_index_bp(),
            minted: w.minted, burned: w.burned, treasury: w.treasury, solvent_merchants: w.solvent_merchants(),
            open_loans: w.loans.values().filter(|l| l.status == crate::credit::LoanStatus::Open).count(),
            defaults: w.players.values().map(|p| p.defaults).sum(), events: r.events,
        });
    }
    (w, frames)
}

#[derive(Debug, Clone, Serialize)]
pub struct StabilityReport { pub seeds: u64, pub days: u32, pub worst_abs_drift_bp: i64, pub mean_final_drift_bp: i64, pub worst_final_drift_bp: i64, pub min_price_index_bp: u64, pub max_price_index_bp: u64, pub min_solvent_merchants: usize }

pub fn stability(seeds: u64, days: u32) -> StabilityReport {
    let mut rep = StabilityReport { seeds, days, worst_abs_drift_bp: 0, mean_final_drift_bp: 0, worst_final_drift_bp: 0, min_price_index_bp: u64::MAX, max_price_index_bp: 0, min_solvent_merchants: usize::MAX };
    let mut sum = 0i64;
    for seed in 1..=seeds {
        let (_, fr) = simulate(Config { seed, ..Config::default() }, days, &[]);
        for f in &fr {
            rep.worst_abs_drift_bp = rep.worst_abs_drift_bp.max(f.drift_bp.abs());
            rep.min_price_index_bp = rep.min_price_index_bp.min(f.price_index_bp);
            rep.max_price_index_bp = rep.max_price_index_bp.max(f.price_index_bp);
            rep.min_solvent_merchants = rep.min_solvent_merchants.min(f.solvent_merchants);
        }
        let last = fr.last().unwrap().drift_bp;
        sum += last;
        if last.abs() > rep.worst_final_drift_bp.abs() { rep.worst_final_drift_bp = last; }
    }
    rep.mean_final_drift_bp = sum / seeds as i64;
    rep
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn daily_mid_move_never_exceeds_20pct() {
        let ev: Vec<ScriptedEvent> = (1..40).step_by(3).map(|d| ScriptedEvent { day: d, kind: crate::events::ALL_KINDS[(d % 6) as usize], magnitude: 100 }).collect();
        let mut w = World::new(Config { seed: 4, random_events: false, ..Config::default() });
        for e in &ev { w.inject(Event::new(e.kind, e.day, e.magnitude)); }
        let mut prev: Vec<Vec<u64>> = w.merchants.iter().map(|m| GOODS.iter().map(|g| m.ref_mid[g.id]).collect()).collect();
        for _ in 0..40 {
            for _ in 0..3 { w.advance().unwrap(); }
            for (mi, m) in w.merchants.iter().enumerate() {
                for (gi, g) in GOODS.iter().enumerate() {
                    let (a, b) = (prev[mi][gi], m.ref_mid[g.id]);
                    assert!(b * 10_000 <= a * 12_000 + 10_000 && b * 10_000 + 10_000 >= a * 8_000, "{} {a}->{b}", g.id);
                    prev[mi][gi] = b;
                }
            }
        }
    }
    #[test]
    fn deterministic() {
        let (_, a) = simulate(Config { seed: 5, ..Config::default() }, 20, &[]);
        let (_, b) = simulate(Config { seed: 5, ..Config::default() }, 20, &[]);
        assert_eq!(serde_json::to_string(&a).unwrap(), serde_json::to_string(&b).unwrap());
    }
    #[test]
    fn hundred_seed_drift_within_15pct() {
        let r = stability(100, 60);
        eprintln!("{}", serde_json::to_string_pretty(&r).unwrap());
        assert!(r.worst_abs_drift_bp <= 1500, "drift {:?}", r);
    }
    /// Regression pin for the stability guarantees: 100 seeds x 60 days.
    /// Worst-day drift under 1,500 bp, and at least 3 of 4 stalls hold >= 20,000 pts every day.
    #[test]
    fn stability_guarantees_pinned() {
        let r = stability(100, 60);
        assert_eq!((r.seeds, r.days), (100, 60));
        assert!(r.worst_abs_drift_bp < 1500, "drift guarantee broken: {:?}", r);
        assert!(r.min_solvent_merchants >= 3, "stall solvency guarantee broken: {:?}", r);
    }
    #[test]
    fn scripted_drought_raises_farm_prices() {
        let ev = [ScriptedEvent { day: 3, kind: EventKind::Ukame, magnitude: 80 }];
        let cfg = Config { seed: 2, random_events: false, ..Config::default() };
        let (_, calm) = simulate(cfg.clone(), 6, &[]);
        let (_, dry) = simulate(cfg, 6, &ev);
        assert!(dry[3].price_index_bp > calm[3].price_index_bp);
    }
}
