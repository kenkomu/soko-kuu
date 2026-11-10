//! The rule engine seam. `Market` is what the server needs; `EconMarket` backs it with `econ::world::World`
//! (all prices and rules are code in the econ crate; nothing here sets a price).
use econ::chama::Offer;
use econ::chama::{JOIN_SHARE, MAX_MEMBERS};
use econ::credit::{credit_limit, LoanStatus, CHAMA_INTEREST_BP, MERCHANT_INTEREST_BP};
use econ::pricing::GOODS;
use econ::world::{Config, Lender, Player, World, BID_FLOAT};
use econ::{Action, ErrorCode, Phase, Pts};
use serde::Serialize;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashSet};

pub const TIER_NAMES: [&str; 4] = ["mgeni", "mfanyabiashara", "mzoefu", "mzee_wa_soko"];

pub struct Outcome { pub state_delta: Value, pub events: Vec<Value> }

pub trait Market: Send {
    fn boxed_clone(&self) -> Box<dyn Market>;
    fn add_player(&mut self, pubkey: &str) -> String;
    fn remove_player(&mut self, id: &str);
    fn apply(&mut self, id: &str, a: &Action) -> Result<Outcome, ErrorCode>;
    fn state(&self, id: &str) -> Option<Value>;
    fn clock(&self) -> (u32, Phase);
    fn prices(&self) -> Value;
    fn news(&self) -> Value;
    fn chama(&self, id: &str) -> Option<Value>;
    fn ledger(&self, id: &str, day: u32) -> Value;
    fn report(&self, id: Option<&str>) -> Value;
    /// Players in `hide` (e.g. fresh guests) are left off the personal board.
    fn leaderboard(&self, hide: &HashSet<String>) -> Value;
    /// Open chamas anyone can join.
    fn chamas(&self) -> Value;
    /// Relayer-driven clock: move to the next phase with no player involved.
    fn advance_clock(&mut self) -> Vec<Value>;
    fn player_count(&self) -> usize;
    /// testnet: player ids are the contract's ids (64 hex chars of the key) so a contract snapshot drops in unchanged.
    fn set_chain_ids(&mut self) {}
    /// State the contract does not hold (ledger history, personal bests, price sparklines), for the data directory.
    fn export_extra(&self) -> Value { Value::Null }
    fn import_extra(&mut self, _v: Value) -> Result<(), String> { Ok(()) }
    fn has_player(&self, _id: &str) -> bool { false }
    /// Insert a player with the onboarding grant if missing (same as the contract's first-act registration).
    fn ensure_player(&mut self, _id: &str) {}
    /// Hash (same format as the contract's `world_hash`) of the local world, ignoring `pending` players the contract has not seen yet.
    fn comparable_hash(&self, _pending: &HashSet<String>) -> Option<String> { None }
    /// Replace the whole world with the contract's Borsh snapshot.
    fn replace_world(&mut self, _bytes: &[u8]) -> Result<(), String> { Err("not supported".into()) }
}

/// First 16 bytes of sha256(Borsh(World)) as hex: exactly the contract's `world_hash`.
pub fn world_hash_hex(w: &World) -> Option<String> {
    let bytes = borsh::to_vec(w).ok()?;
    Some(Sha256::digest(&bytes).iter().take(16).map(|b| format!("{b:02x}")).collect())
}

#[derive(Clone, Serialize, serde::Deserialize)]
struct Entry { day: u32, phase: Phase, kind: String, delta: i64, cause: String, balance: Pts }

#[derive(Clone)]
pub struct EconMarket {
    world: World,
    ledgers: BTreeMap<String, Vec<Entry>>,
    best: BTreeMap<String, i64>,
    /// "merchant/good" -> recent daily ask prices (sparkline)
    history: BTreeMap<String, Vec<u64>>,
    chain_ids: bool,
}

impl EconMarket {
    pub fn new(seed: u64) -> Self {
        let cfg = Config { seed, players: 0, ..Config::default() };
        let mut m = EconMarket { world: World::new(cfg), ledgers: BTreeMap::new(), best: BTreeMap::new(), history: BTreeMap::new(), chain_ids: false };
        m.record_history();
        m
    }
    fn record_history(&mut self) {
        for (mi, mer) in self.world.merchants.iter().enumerate() {
            for g in GOODS.iter() {
                if let Some(q) = self.world.quote(mi, g.id) {
                    let h = self.history.entry(format!("{}/{}", mer.id, g.id)).or_default();
                    h.push(q.ask);
                    if h.len() > 30 { h.remove(0); }
                }
            }
        }
    }
    /// After a day rolled over: itemise the settlement per player, refresh bests and price history.
    fn settle(&mut self, pts0: BTreeMap<String, Pts>) {
        let (d, ph) = (self.world.day, self.world.phase);
        for (pid, old) in pts0 {
            if let Some(p) = self.world.players.get(&pid) {
                let (now, delta) = (p.pts, p.pts as i64 - old as i64);
                if delta != 0 { self.push(&pid, "settlement", delta, "Daily settlement (allowance, repayments, contributions).".into(), d, ph, now); }
            }
        }
        let ids: Vec<String> = self.world.players.keys().cloned().collect();
        for pid in ids { self.bump_best(&pid); }
        self.record_history();
    }
    fn all_pts(&self) -> BTreeMap<String, Pts> { self.world.players.iter().map(|(k, p)| (k.clone(), p.pts)).collect() }
    pub fn world(&self) -> &World { &self.world }

    #[allow(clippy::too_many_arguments)]
    fn push(&mut self, id: &str, kind: &str, delta: i64, cause: String, day: u32, phase: Phase, balance: Pts) {
        let v = self.ledgers.entry(id.to_string()).or_default();
        v.push(Entry { day, phase, kind: kind.into(), delta, cause, balance });
        if v.len() > 500 { v.remove(0); }
    }
    fn bump_best(&mut self, id: &str) {
        let nw = self.world.net_worth(id);
        let b = self.best.entry(id.to_string()).or_insert(nw);
        if nw > *b { *b = nw; }
    }
}

fn kind_of(a: &Action) -> &'static str {
    match a {
        Action::Buy { .. } => "buy", Action::Sell { .. } => "sell", Action::Haggle { .. } => "haggle",
        Action::ChamaCreate {} | Action::ChamaJoin { .. } | Action::ChamaVote { .. } => "chama",
        Action::CreditRequest { .. } => "credit", Action::CreditRepay { .. } => "repay",
        Action::Guarantee { .. } => "guarantee", Action::Invest { .. } => "invest", Action::Advance {} => "advance",
    }
}

fn nonzero_stock(p: &Player) -> Value {
    let m: Map<String, Value> = p.stock.iter().filter(|(_, q)| **q > 0).map(|(g, q)| (g.clone(), json!(q))).collect();
    Value::Object(m)
}

fn diff(a: &Value, b: &Value) -> Value {
    let mut d = Map::new();
    if let (Some(ao), Some(bo)) = (a.as_object(), b.as_object()) {
        for (k, v) in bo { if ao.get(k) != Some(v) { d.insert(k.clone(), v.clone()); } }
    }
    let pts = |v: &Value| v["pts"].as_i64().unwrap_or(0);
    d.insert("pts_change".into(), json!(pts(b) - pts(a)));
    let mut sc = Map::new();
    let (sa, sb) = (a["stock"].as_object().cloned().unwrap_or_default(), b["stock"].as_object().cloned().unwrap_or_default());
    for g in sa.keys().chain(sb.keys()) {
        let x = sb.get(g).and_then(Value::as_i64).unwrap_or(0) - sa.get(g).and_then(Value::as_i64).unwrap_or(0);
        if x != 0 { sc.insert(g.clone(), json!(x)); }
    }
    d.insert("stock_change".into(), Value::Object(sc));
    Value::Object(d)
}

fn cap(s: &str) -> String { let mut c = s.chars(); c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default() }

impl Market for EconMarket {
    fn boxed_clone(&self) -> Box<dyn Market> { Box::new(self.clone()) }

    fn add_player(&mut self, pubkey: &str) -> String {
        let chain_id = if self.chain_ids {
            pubkey.strip_prefix("ed25519:").and_then(|r| bs58::decode(r).into_vec().ok()).filter(|b| b.len() == 32)
                .map(|b| b.iter().map(|x| format!("{x:02x}")).collect::<String>())
        } else { None };
        let id = chain_id.unwrap_or_else(|| {
            let h: String = Sha256::digest(pubkey.as_bytes()).iter().take(4).map(|b| format!("{b:02x}")).collect();
            format!("p{h}")
        });
        if !self.world.players.contains_key(&id) {
            let pts = self.world.cfg.start_pts;
            self.world.players.insert(id.clone(), Player { id: id.clone(), pts, ..Default::default() });
            if self.chain_ids { self.world.minted += pts; } // the contract mints the grant at first act
            self.world.target_supply += pts; // onboarding grant enters the loop; keep the drift baseline honest
            let (d, ph) = (self.world.day, self.world.phase);
            self.push(&id, "onboard", pts as i64, "Welcome grant for new traders.".into(), d, ph, pts);
            self.bump_best(&id);
        }
        id
    }

    fn set_chain_ids(&mut self) { self.chain_ids = true; }
    fn export_extra(&self) -> Value { json!({"ledgers": self.ledgers, "best": self.best, "history": self.history}) }
    fn import_extra(&mut self, v: Value) -> Result<(), String> {
        let l: BTreeMap<String, Vec<Entry>> = serde_json::from_value(v["ledgers"].clone()).map_err(|e| e.to_string())?;
        let b: BTreeMap<String, i64> = serde_json::from_value(v["best"].clone()).map_err(|e| e.to_string())?;
        let h: BTreeMap<String, Vec<u64>> = serde_json::from_value(v["history"].clone()).map_err(|e| e.to_string())?;
        self.ledgers = l; self.best = b;
        if !h.is_empty() { self.history = h; }
        Ok(())
    }
    fn has_player(&self, id: &str) -> bool { self.world.players.contains_key(id) }
    fn ensure_player(&mut self, id: &str) {
        if self.world.players.contains_key(id) { return; }
        let pts = self.world.cfg.start_pts;
        self.world.players.insert(id.to_string(), Player { id: id.to_string(), pts, ..Default::default() });
        self.world.minted += pts;
        self.world.target_supply += pts;
    }
    fn comparable_hash(&self, pending: &HashSet<String>) -> Option<String> {
        let mut w = self.world.clone();
        let grant = w.cfg.start_pts;
        for id in pending {
            if w.players.remove(id).is_some() { w.minted = w.minted.saturating_sub(grant); w.target_supply = w.target_supply.saturating_sub(grant); }
        }
        world_hash_hex(&w)
    }
    fn replace_world(&mut self, bytes: &[u8]) -> Result<(), String> {
        let w: World = borsh::from_slice(bytes).map_err(|e| format!("bad snapshot: {e}"))?;
        self.world = w;
        self.record_history();
        Ok(())
    }
    fn remove_player(&mut self, id: &str) {
        if let Some(p) = self.world.players.remove(id) {
            self.world.treasury += p.pts; // conserved: points of a leaver go back to the treasury, never out
            for c in self.world.chamas.values_mut() { c.shares.remove(id); }
        }
        self.ledgers.remove(id); self.best.remove(id);
    }

    fn apply(&mut self, id: &str, a: &Action) -> Result<Outcome, ErrorCode> {
        let before = self.state(id).ok_or(ErrorCode::NotMember)?;
        let (day0, phase0) = (self.world.day, self.world.phase);
        let pts0: BTreeMap<String, Pts> = if matches!(a, Action::Advance {}) { self.all_pts() } else { BTreeMap::new() };
        let r = self.world.apply(id, a)?;
        let end = self.world.players.get(id).map_or(0, |p| p.pts);
        let mut remaining: i64 = r.ledger.iter().map(|l| l.pts).sum();
        for l in &r.ledger {
            let bal = (end as i64 - remaining + l.pts).max(0) as Pts;
            remaining -= l.pts;
            self.push(id, kind_of(a), l.pts, l.cause.clone(), day0, phase0, bal);
        }
        if self.world.day != day0 { self.settle(pts0); }
        self.bump_best(id);
        let after = self.state(id).ok_or(ErrorCode::Internal)?;
        Ok(Outcome { state_delta: diff(&before, &after), events: r.events.iter().map(|t| json!({"type": "info", "text": t})).collect() })
    }

    fn state(&self, id: &str) -> Option<Value> {
        let w = &self.world; let p = w.players.get(id)?;
        let t = p.tier(); let out = w.outstanding(id);
        let loans: Vec<Value> = w.loans.values().filter(|l| l.borrower == id && l.status == LoanStatus::Open).map(|l| json!({
            "id": l.id, "merchant": l.merchant, "good": l.good, "qty": l.qty, "principal": l.cost, "owed": l.owed,
            "interest_pct": match &l.lender { Lender::Merchant(_) => MERCHANT_INTEREST_BP / 100, Lender::Chama(_) => CHAMA_INTEREST_BP / 100 },
            "due_day": l.due_day, "guarantor": l.guarantor,
            "lender": match &l.lender { Lender::Merchant(_) => "merchant", Lender::Chama(_) => "chama" },
            "lender_id": match &l.lender { Lender::Merchant(m) => m.clone(), Lender::Chama(c) => c.clone() },
        })).collect();
        Some(json!({
            "player_id": id, "day": w.day, "phase": w.phase, "pts": p.pts, "stock": nonzero_stock(p),
            "reputation": {"tier": TIER_NAMES[(t as usize).min(3)], "tier_index": t, "score": p.score},
            "credit": {"limit": credit_limit(t).saturating_sub(out), "tier_limit": credit_limit(t), "outstanding": out},
            "loans": loans, "chama_id": p.chama,
        }))
    }

    fn clock(&self) -> (u32, Phase) { (self.world.day, self.world.phase) }

    fn prices(&self) -> Value {
        let w = &self.world;
        let mut merchants = Map::new(); let mut items = vec![];
        for (mi, m) in w.merchants.iter().enumerate() {
            let mut goods = Map::new();
            for g in GOODS.iter() {
                let Some(q) = w.quote(mi, g.id) else { continue };
                let mut hist = self.history.get(&format!("{}/{}", m.id, g.id)).cloned().unwrap_or_default();
                hist.push(q.ask); // today's live ask last
                let v = json!({"ask": q.ask, "bid": q.bid, "stock": q.stock, "why": q.why, "history": hist});
                items.push(json!({"merchant": m.id, "good": g.id, "ask": q.ask, "bid": q.bid, "stock": q.stock, "why": q.why, "history": hist}));
                goods.insert(g.id.into(), v);
            }
            let voice = if m.cash < BID_FLOAT { format!("{}: Pesa ni kidogo, naomba kuuza mzigo.", cap(&m.id)) } else { format!("{}: Karibuni sokoni!", cap(&m.id)) };
            merchants.insert(m.id.clone(), json!({"name": cap(&m.id), "voice": voice, "goods": goods}));
        }
        json!({"day": w.day, "phase": w.phase, "price_index": w.price_index_bp(), "price_index_bp": w.price_index_bp(), "merchants": merchants, "items": items})
    }

    fn news(&self) -> Value {
        let mut items: Vec<Value> = self.world.news.iter().rev().take(50).map(|n| json!({"text": n.text, "day": n.day, "kind": n.kind})).collect();
        if items.is_empty() { items.push(json!({"text": "Soko Kuu imefunguliwa. Karibuni sokoni!", "day": self.world.day, "kind": "festival"})); }
        json!({"items": items})
    }

    fn chama(&self, id: &str) -> Option<Value> {
        let c = self.world.chamas.get(id)?;
        let offer = c.offer.as_ref().map(|o: &Offer| serde_json::to_value(o).unwrap_or(Value::Null));
        Some(json!({
            "id": c.id, "members": c.shares.keys().collect::<Vec<_>>(), "shares": c.shares, "cash": c.cash,
            "offer": offer, "votes": c.offer.as_ref().map(|o| &o.votes), "deadline_day": c.offer.as_ref().map(|o| o.deadline_day),
        }))
    }

    fn ledger(&self, id: &str, day: u32) -> Value {
        let e: Vec<&Entry> = self.ledgers.get(id).map(|v| v.iter().filter(|x| x.day == day).collect()).unwrap_or_default();
        json!({"day": day, "entries": e})
    }

    fn report(&self, id: Option<&str>) -> Value {
        let w = &self.world; let supply = w.supply();
        let merchants: Vec<Value> = w.merchants.iter().map(|m| json!({"id": m.id, "name": cap(&m.id), "cash": m.cash, "solvent": m.cash >= 20_000, "stock": m.stock})).collect();
        let score = id.and_then(|i| w.players.get(i).map(|p| json!({"net_worth": w.net_worth(i), "best": self.best.get(i), "reputation": p.score})));
        json!({
            "day": w.day, "window": "season",
            "faucets": {"daily_allowance": w.minted}, "sinks": {"fees_and_rent": w.burned},
            "treasury": w.treasury, "price_index": w.price_index_bp(), "price_index_bp": w.price_index_bp(),
            "money_supply": supply, "target_supply": w.target_supply, "drift_bp": econ::sim::drift_bp(supply, w.target_supply),
            "merchants": merchants, "solvent_merchants": w.solvent_merchants(), "score": score,
        })
    }

    fn leaderboard(&self, hide: &HashSet<String>) -> Value {
        let w = &self.world;
        let mut personal: Vec<(String, i64)> = self.best.iter().filter(|(k, _)| !hide.contains(*k)).map(|(k, v)| (k.clone(), *v)).collect();
        personal.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        let personal: Vec<Value> = personal.into_iter().take(20).map(|(p, v)| json!({"player_id": p, "best_net_worth": v})).collect();
        let mut chamas: Vec<(String, usize, i64)> = w.chamas.values().map(|c| {
            let s: i64 = c.shares.keys().map(|m| w.net_worth(m)).sum::<i64>() + c.cash as i64;
            (c.id.clone(), c.shares.len(), s)
        }).collect();
        chamas.sort_by(|a, b| b.2.cmp(&a.2).then(a.0.cmp(&b.0)));
        let chamas: Vec<Value> = chamas.into_iter().take(20).map(|(id, n, s)| json!({"chama_id": id, "members": n, "score": s})).collect();
        json!({"personal": personal, "chamas": chamas})
    }

    fn chamas(&self) -> Value {
        let items: Vec<Value> = self.world.chamas.values().filter(|c| c.shares.len() < MAX_MEMBERS).map(|c| json!({
            "id": c.id, "members": c.shares.len(), "max_members": MAX_MEMBERS, "join_share": JOIN_SHARE, "cash": c.cash, "open_offer": c.offer.is_some(),
        })).collect();
        json!({"items": items, "join_share": JOIN_SHARE})
    }

    fn advance_clock(&mut self) -> Vec<Value> {
        let (day0, pts0) = (self.world.day, self.all_pts());
        let ev = self.world.advance().map(|r| r.events).unwrap_or_default();
        if self.world.day != day0 { self.settle(pts0); }
        ev.iter().map(|t| json!({"type": "info", "text": t})).collect()
    }

    fn player_count(&self) -> usize { self.world.players.len() }
}
