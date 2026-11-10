//! Closed-loop world state and the single rule engine `World::apply`.
//! Money is conserved except two explicit flows: `minted` (daily stipend, thermostat-controlled) and
//! `burned` (market fee on sells, stall rent). No cash-out, no transfers between players.
use crate::action::*;
use crate::chama::*;
use crate::credit::*;
use crate::events::*;
use crate::pricing::*;
use crate::rng::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Merchant cash below this lowers its bids.
pub const BID_FLOAT: Pts = 60_000;
/// Stall cash above this pays a daily market levy to the treasury.
pub const RICH_CASH: Pts = 140_000;
/// A stall never spends its last pts on wholesale: it keeps this much to pay bids.
pub const RESTOCK_RESERVE: Pts = 35_000;
pub const INVEST_DAYS: u32 = 7;
pub const INVEST_YIELD_BP: u64 = 400;
pub const MERCHANT_NAMES: [&str; 4] = ["njeri", "otieno", "wanjiru", "hassan"];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Config {
    pub seed: u64,
    pub players: usize,
    pub merchants: usize,
    pub start_pts: Pts,
    pub merchant_cash: Pts,
    pub stipend: Pts,
    pub random_events: bool,
}
impl Default for Config {
    fn default() -> Self {
        Config { seed: 1, players: 24, merchants: 4, start_pts: 20_000, merchant_cash: 120_000, stipend: 1_500, random_events: true }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Merchant {
    pub id: String,
    pub cash: Pts,
    pub stock: BTreeMap<String, u32>,
    pub spread_bp: u64,
    /// Mid price at the start of the day; today's mid may only move +-20% from it.
    pub ref_mid: BTreeMap<String, Pts>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Player {
    pub id: String,
    pub pts: Pts,
    pub stock: BTreeMap<String, u32>,
    pub score: i32,
    pub defaults: u32,
    pub chama: Option<String>,
    /// "merchant/good" -> (day, discount bp) from a successful haggle
    pub haggles: BTreeMap<String, (u32, u64)>,
}
impl Player { pub fn tier(&self) -> u8 { tier(self.score) } }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(rename_all = "snake_case")]
pub enum Lender { Merchant(String), Chama(String) }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Loan {
    pub id: u64,
    pub borrower: String,
    pub lender: Lender,
    pub merchant: String,
    pub good: String,
    pub qty: u32,
    pub cost: Pts,
    pub owed: Pts,
    pub due_day: u32,
    pub guarantor: Option<String>,
    pub status: LoanStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Investment { pub id: u64, pub player: String, pub merchant: String, pub pts: Pts, pub mature_day: u32 }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct NewsItem { pub day: u32, pub kind: EventKind, pub text: String }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct LedgerLine { pub cause: String, pub pts: i64 }

/// Result of one action: the acting player's pts delta, itemised, plus human-readable events.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Receipt { pub pts_delta: i64, pub ledger: Vec<LedgerLine>, pub events: Vec<String> }

impl Receipt {
    fn line(&mut self, cause: impl Into<String>, pts: i64) { self.pts_delta += pts; self.ledger.push(LedgerLine { cause: cause.into(), pts }); }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct World {
    pub cfg: Config,
    pub day: u32,
    pub phase: Phase,
    pub merchants: Vec<Merchant>,
    pub players: BTreeMap<String, Player>,
    pub chamas: BTreeMap<String, Chama>,
    pub loans: BTreeMap<u64, Loan>,
    pub investments: Vec<Investment>,
    pub events: Vec<Event>,
    pub news: Vec<NewsItem>,
    pub treasury: Pts,
    pub minted: Pts,
    pub burned: Pts,
    pub target_supply: Pts,
    pub next_id: u64,
    pub rng: Rng,
    /// `burned` at the previous tick; the faucet replaces what the sinks removed.
    pub burned_mark: Pts,
}

impl World {
    pub fn new(cfg: Config) -> World {
        let merchants = (0..cfg.merchants).map(|i| Merchant {
            id: MERCHANT_NAMES.get(i).map(|s| s.to_string()).unwrap_or(format!("m{i}")),
            cash: cfg.merchant_cash,
            stock: GOODS.iter().map(|g| (g.id.to_string(), g.target_stock)).collect(),
            spread_bp: BASE_SPREAD_BP,
            ref_mid: GOODS.iter().map(|g| (g.id.to_string(), g.base)).collect(),
        }).collect();
        let players = (0..cfg.players).map(|i| {
            let id = format!("p{i:03}");
            (id.clone(), Player { id, pts: cfg.start_pts, ..Default::default() })
        }).collect();
        let mut w = World {
            day: 0, phase: Phase::Dawn, merchants, players, chamas: BTreeMap::new(), loans: BTreeMap::new(),
            investments: vec![], events: vec![], news: vec![], treasury: 0, minted: 0, burned: 0, target_supply: 0,
            next_id: 1, rng: Rng::new(cfg.seed), burned_mark: 0, cfg,
        };
        w.target_supply = w.supply();
        w
    }

    /// All money in the system.
    pub fn supply(&self) -> Pts {
        self.players.values().map(|p| p.pts).sum::<Pts>()
            + self.merchants.iter().map(|m| m.cash).sum::<Pts>()
            + self.chamas.values().map(|c| c.cash).sum::<Pts>()
            + self.treasury
    }

    pub fn merchant_idx(&self, id: &str) -> Option<usize> { self.merchants.iter().position(|m| m.id == id) }

    pub fn mods(&self, gi: usize) -> Modifiers { modifiers(&self.events, self.day, gi) }

    pub fn quote(&self, mi: usize, good_id: &str) -> Option<Quote> {
        let gi = good_index(good_id)?;
        let m = self.merchants.get(mi)?;
        let stock = *m.stock.get(good_id).unwrap_or(&0);
        let mut q = quote_ref(&GOODS[gi], stock, &self.mods(gi), m.spread_bp, m.ref_mid.get(good_id).copied());
        // A cash-poor stall lowballs its bids (down to 30%) so it cannot be bled dry.
        if m.cash < BID_FLOAT {
            let f = (m.cash * BP / BID_FLOAT).max(3_000);
            q.bid = (q.bid * f / BP).min(q.ask - 1);
            q.why.push("This stall is short of cash, so it is offering less when buying.".into());
        }
        Some(q)
    }

    pub fn outstanding(&self, pid: &str) -> Pts {
        self.loans.values().filter(|l| l.borrower == pid && l.status == LoanStatus::Open).map(|l| l.owed).sum()
    }

    pub fn net_worth(&self, pid: &str) -> i64 {
        let Some(p) = self.players.get(pid) else { return 0 };
        let mut v = p.pts as i64;
        for (g, q) in &p.stock { if let Some(d) = good(g) { v += (d.base * *q as u64 * 9 / 10) as i64; } }
        v - self.outstanding(pid) as i64
    }

    fn id(&mut self) -> u64 { let i = self.next_id; self.next_id += 1; i }

    /// Queue a scripted event (also used by /v1/sim).
    pub fn inject(&mut self, e: Event) { self.events.push(e); }

    pub fn apply(&mut self, pid: &str, a: &Action) -> Result<Receipt, ErrorCode> {
        if !self.players.contains_key(pid) { return Err(ErrorCode::NotMember); }
        let mut r = Receipt::default();
        match a {
            Action::Buy { merchant, good: g, qty, max_unit_price } => {
                self.need_midday()?;
                let (mi, gd) = self.lookup(merchant, g, *qty)?;
                let q = self.quote(mi, g).unwrap();
                if *self.merchants[mi].stock.get(g.as_str()).unwrap_or(&0) < *qty { return Err(ErrorCode::NotEnoughStock); }
                let key = format!("{merchant}/{g}");
                let p = self.players.get(pid).unwrap();
                let mut unit = q.ask;
                if let Some((d, bp)) = p.haggles.get(&key) { if *d == self.day { unit = apply_discount(q.ask, *bp); } }
                if unit > *max_unit_price { return Err(ErrorCode::PriceMoved); }
                let total = unit.checked_mul(*qty as u64).ok_or(ErrorCode::Internal)?;
                if p.pts < total { return Err(ErrorCode::NotEnoughPts); }
                let p = self.players.get_mut(pid).unwrap();
                p.pts -= total;
                *p.stock.entry(gd.id.to_string()).or_insert(0) += qty;
                p.haggles.remove(&key);
                let m = &mut self.merchants[mi];
                m.cash = m.cash.saturating_add(total);
                *m.stock.get_mut(gd.id).unwrap() -= qty;
                r.line(format!("bought {qty} {g} from {merchant} at {unit}"), -(total as i64));
            }
            Action::Sell { merchant, good: g, qty, min_unit_price } => {
                self.need_midday()?;
                let (mi, gd) = self.lookup(merchant, g, *qty)?;
                let q = self.quote(mi, g).unwrap();
                if self.players[pid].stock.get(g).copied().unwrap_or(0) < *qty { return Err(ErrorCode::NotEnoughStock); }
                if let Some(min) = min_unit_price { if q.bid < *min { return Err(ErrorCode::PriceMoved); } }
                let total = q.bid.checked_mul(*qty as u64).ok_or(ErrorCode::Internal)?;
                if self.merchants[mi].cash < total { return Err(ErrorCode::NotEnoughPts); }
                let f = fee(total);
                self.merchants[mi].cash -= total;
                *self.merchants[mi].stock.entry(gd.id.to_string()).or_insert(0) += qty;
                self.burned = self.burned.saturating_add(f);
                let p = self.players.get_mut(pid).unwrap();
                *p.stock.get_mut(g.as_str()).unwrap() -= qty;
                p.pts = p.pts.saturating_add(total - f);
                r.line(format!("sold {qty} {g} to {merchant} at {}", q.bid), total as i64);
                r.line("market fee", -(f as i64));
            }
            Action::Haggle { merchant, good: g } => {
                self.need_midday()?;
                let (_, _) = self.lookup(merchant, g, 1)?;
                let key = format!("{merchant}/{g}");
                let day = self.day;
                let seed = self.cfg.seed;
                let p = self.players.get_mut(pid).unwrap();
                if matches!(p.haggles.get(&key), Some((d, _)) if *d == day) { return Err(ErrorCode::RateLimited); }
                let bp = haggle_discount_bp(mix(&[seed, day as u64, hash_str(pid), hash_str(&key)]), p.tier());
                p.haggles.insert(key, (day, bp));
                r.events.push(format!("{merchant} agrees to {}.{:02}% off {g} today.", bp / 100, bp % 100));
            }
            Action::ChamaCreate {} => {
                if self.players[pid].chama.is_some() { return Err(ErrorCode::WrongPhase); }
                if self.players[pid].pts < JOIN_SHARE { return Err(ErrorCode::NotEnoughPts); }
                let id = format!("c{}", self.id());
                let mut c = Chama::new(id.clone());
                c.contribute(pid, JOIN_SHARE);
                self.chamas.insert(id.clone(), c);
                let p = self.players.get_mut(pid).unwrap();
                p.pts -= JOIN_SHARE; p.chama = Some(id.clone());
                r.line("chama join share", -(JOIN_SHARE as i64));
                r.events.push(format!("chama {id} created"));
            }
            Action::ChamaJoin { chama_id } => {
                if self.players[pid].chama.is_some() { return Err(ErrorCode::WrongPhase); }
                let c = self.chamas.get_mut(chama_id).ok_or(ErrorCode::NotMember)?;
                if c.shares.len() >= MAX_MEMBERS { return Err(ErrorCode::WrongPhase); }
                if self.players[pid].pts < JOIN_SHARE { return Err(ErrorCode::NotEnoughPts); }
                c.contribute(pid, JOIN_SHARE);
                let p = self.players.get_mut(pid).unwrap();
                p.pts -= JOIN_SHARE; p.chama = Some(chama_id.clone());
                r.line("chama join share", -(JOIN_SHARE as i64));
            }
            Action::ChamaVote { offer_id, vote } => {
                let cid = self.players[pid].chama.clone().ok_or(ErrorCode::NotMember)?;
                let c = self.chamas.get_mut(&cid).ok_or(ErrorCode::NotMember)?;
                let o = c.offer.as_mut().filter(|o| o.id == *offer_id).ok_or(ErrorCode::WrongPhase)?;
                if o.borrower == pid { return Err(ErrorCode::WrongPhase); }
                if o.votes.contains_key(pid) { return Err(ErrorCode::AlreadyVoted); }
                o.votes.insert(pid.to_string(), *vote);
                let t = tally(c.shares.len(), o);
                match t {
                    Tally::Pending => r.events.push("vote recorded".into()),
                    Tally::Rejected => { c.offer = None; r.events.push("chama offer rejected".into()); }
                    Tally::Approved => { let msg = self.execute_offer(&cid); r.events.push(msg); }
                }
            }
            Action::CreditRequest { merchant, good: g, qty } => {
                self.need_midday()?;
                let (mi, gd) = self.lookup(merchant, g, *qty)?;
                if *self.merchants[mi].stock.get(gd.id).unwrap_or(&0) < *qty { return Err(ErrorCode::NotEnoughStock); }
                let cost = self.quote(mi, g).unwrap().ask.checked_mul(*qty as u64).ok_or(ErrorCode::Internal)?;
                if self.loans.values().filter(|l| l.borrower == pid && l.status == LoanStatus::Open).count() >= MAX_OPEN_LOANS { return Err(ErrorCode::CreditDenied); }
                let p = &self.players[pid];
                let owed_m = owed(cost, MERCHANT_INTEREST_BP);
                if within_limit(p.score, self.outstanding(pid), owed_m) {
                    let id = self.id();
                    let due = self.day + LOAN_DAYS;
                    self.merchants[mi].stock.entry(gd.id.to_string()).and_modify(|s| *s -= qty);
                    *self.players.get_mut(pid).unwrap().stock.entry(gd.id.to_string()).or_insert(0) += qty;
                    self.loans.insert(id, Loan { id, borrower: pid.into(), lender: Lender::Merchant(merchant.clone()), merchant: merchant.clone(), good: g.clone(), qty: *qty, cost, owed: owed_m, due_day: due, guarantor: None, status: LoanStatus::Open });
                    r.events.push(format!("loan {id}: {qty} {g} on credit, owe {owed_m} by day {due}"));
                } else if let Some(cid) = p.chama.clone() {
                    let id = self.next_id;
                    let day = self.day;
                    let c = self.chamas.get_mut(&cid).unwrap();
                    if c.offer.is_some() || c.cash < cost || c.shares.len() < 3 { return Err(ErrorCode::CreditDenied); }
                    c.offer = Some(Offer { id, borrower: pid.into(), merchant: merchant.clone(), good: g.clone(), qty: *qty, cost, owed: owed(cost, CHAMA_INTEREST_BP), deadline_day: day + OFFER_DAYS, votes: BTreeMap::new() });
                    self.next_id += 1;
                    r.events.push(format!("chama offer {id} opened for {qty} {g}"));
                } else { return Err(ErrorCode::CreditDenied); }
            }
            Action::CreditRepay { loan_id } => {
                let l = self.loans.get(loan_id).filter(|l| l.borrower == pid && l.status == LoanStatus::Open).ok_or(ErrorCode::WrongPhase)?.clone();
                if self.players[pid].pts < l.owed { return Err(ErrorCode::NotEnoughPts); }
                self.players.get_mut(pid).unwrap().pts -= l.owed;
                self.credit_lender(&l.lender, l.owed);
                let on_time = self.day <= l.due_day;
                self.players.get_mut(pid).unwrap().score += repay_delta(on_time);
                if on_time { if let Some(g) = &l.guarantor { if let Some(gp) = self.players.get_mut(g) { gp.score += 1; } } }
                self.loans.get_mut(loan_id).unwrap().status = LoanStatus::Repaid;
                r.line(format!("repaid loan {loan_id}"), -(l.owed as i64));
            }
            Action::Guarantee { borrower, loan_id } => {
                if borrower == pid { return Err(ErrorCode::WrongPhase); }
                if !can_guarantee(self.players[pid].score) { return Err(ErrorCode::CreditDenied); }
                if self.loans.values().filter(|l| l.status == LoanStatus::Open && l.guarantor.as_deref() == Some(pid)).count() >= MAX_OPEN_GUARANTEES { return Err(ErrorCode::CreditDenied); }
                let l = self.loans.get_mut(loan_id).filter(|l| l.borrower == *borrower && l.status == LoanStatus::Open && l.guarantor.is_none()).ok_or(ErrorCode::WrongPhase)?;
                l.guarantor = Some(pid.into());
                r.events.push(format!("you now guarantee loan {loan_id}"));
            }
            Action::Invest { merchant, pts } => {
                self.need_midday()?;
                let mi = self.merchant_idx(merchant).ok_or(ErrorCode::NotMember)?;
                if *pts == 0 { return Err(ErrorCode::NotEnoughPts); }
                if self.investments.iter().filter(|i| i.player == pid).count() >= MAX_INVESTMENTS { return Err(ErrorCode::RateLimited); }
                if self.players[pid].pts < *pts { return Err(ErrorCode::NotEnoughPts); }
                self.players.get_mut(pid).unwrap().pts -= pts;
                self.merchants[mi].cash = self.merchants[mi].cash.saturating_add(*pts);
                let id = self.id();
                self.investments.push(Investment { id, player: pid.into(), merchant: merchant.clone(), pts: *pts, mature_day: self.day + INVEST_DAYS });
                r.line(format!("invested in {merchant}"), -(*pts as i64));
            }
            Action::Advance {} => { r.events = self.advance()?.events; }
        }
        Ok(r)
    }

    /// Move to the next phase; dusk -> dawn runs the daily settlement. Needs no player id, so the relayer's
    /// clock can run before anyone has registered. Never fails today; returns Result for forward compatibility.
    pub fn advance(&mut self) -> Result<Receipt, ErrorCode> {
        let mut r = Receipt::default();
        let (np, roll) = self.phase.next();
        self.phase = np;
        if roll { self.tick(&mut r.events); }
        Ok(r)
    }

    fn need_midday(&self) -> Result<(), ErrorCode> { if self.phase == Phase::Midday { Ok(()) } else { Err(ErrorCode::WrongPhase) } }

    fn lookup(&self, merchant: &str, g: &str, qty: u32) -> Result<(usize, &'static GoodDef), ErrorCode> {
        if qty == 0 || qty > MAX_QTY { return Err(ErrorCode::NotEnoughStock); }
        let mi = self.merchant_idx(merchant).ok_or(ErrorCode::NotMember)?;
        let gd = good(g).ok_or(ErrorCode::NotEnoughStock)?;
        Ok((mi, gd))
    }

    fn credit_lender(&mut self, l: &Lender, amt: Pts) {
        match l {
            Lender::Merchant(m) => { if let Some(i) = self.merchant_idx(m) { self.merchants[i].cash = self.merchants[i].cash.saturating_add(amt); } else { self.treasury = self.treasury.saturating_add(amt); } }
            Lender::Chama(c) => { if let Some(c) = self.chamas.get_mut(c) { c.cash = c.cash.saturating_add(amt); } else { self.treasury = self.treasury.saturating_add(amt); } }
        }
    }

    fn execute_offer(&mut self, cid: &str) -> String {
        let Some(o) = self.chamas.get_mut(cid).and_then(|c| c.offer.take()) else { return "no offer".into() };
        let mi = self.merchant_idx(&o.merchant);
        let ok = mi.is_some_and(|mi| self.merchants[mi].stock.get(&o.good).copied().unwrap_or(0) >= o.qty)
            && self.chamas[cid].cash >= o.cost && self.players.contains_key(&o.borrower);
        if !ok { return "chama offer lapsed (stock or cash changed)".into(); }
        let mi = mi.unwrap();
        self.chamas.get_mut(cid).unwrap().cash -= o.cost;
        self.merchants[mi].cash = self.merchants[mi].cash.saturating_add(o.cost);
        *self.merchants[mi].stock.get_mut(&o.good).unwrap() -= o.qty;
        *self.players.get_mut(&o.borrower).unwrap().stock.entry(o.good.clone()).or_insert(0) += o.qty;
        let id = self.id();
        let due = self.day + LOAN_DAYS;
        self.loans.insert(id, Loan { id, borrower: o.borrower.clone(), lender: Lender::Chama(cid.into()), merchant: o.merchant, good: o.good, qty: o.qty, cost: o.cost, owed: o.owed, due_day: due, guarantor: None, status: LoanStatus::Open });
        format!("chama approved loan {id} for {}", o.borrower)
    }

    /// Daily settlement, run when dusk rolls over to the next dawn.
    fn tick(&mut self, out: &mut Vec<String>) {
        let nd = self.day + 1;
        // 1. defaults
        let due: Vec<u64> = self.loans.values().filter(|l| l.status == LoanStatus::Open && l.due_day < nd).map(|l| l.id).collect();
        for id in due {
            let l = self.loans[&id].clone();
            let mut need = l.owed;
            let take = self.players.get(&l.borrower).map_or(0, |p| p.pts.min(need));
            if let Some(p) = self.players.get_mut(&l.borrower) { p.pts -= take; p.score = (p.score - DEFAULT_PENALTY).max(0); p.defaults += 1; }
            need -= take;
            let mut got = take;
            if let Some(g) = &l.guarantor {
                if let Some(gp) = self.players.get_mut(g) {
                    let t = gp.pts.min(need);
                    gp.pts -= t; gp.score = (gp.score - 1).max(0); got += t;
                }
            }
            self.credit_lender(&l.lender, got);
            self.loans.get_mut(&id).unwrap().status = LoanStatus::Defaulted;
            out.push(format!("loan {id} defaulted; lender recovered {got} of {}", l.owed));
        }
        self.loans.retain(|_, l| l.status == LoanStatus::Open || l.due_day + KEEP_SETTLED_DAYS >= nd);
        // 2. investments mature
        let (mature, keep): (Vec<_>, Vec<_>) = std::mem::take(&mut self.investments).into_iter().partition(|i| i.mature_day <= nd);
        self.investments = keep;
        for i in mature {
            let want = i.pts.saturating_add(mul_div(i.pts, INVEST_YIELD_BP, BP));
            if let Some(mi) = self.merchant_idx(&i.merchant) {
                let pay = want.min(self.merchants[mi].cash);
                self.merchants[mi].cash -= pay;
                if let Some(p) = self.players.get_mut(&i.player) { p.pts = p.pts.saturating_add(pay); } else { self.treasury = self.treasury.saturating_add(pay); }
            }
        }
        // 3. chama offers expire, weekly contributions
        for c in self.chamas.values_mut() { if c.offer.as_ref().is_some_and(|o| o.deadline_day < nd) { c.offer = None; } }
        if nd.is_multiple_of(CONTRIB_EVERY_DAYS) {
            let ids: Vec<String> = self.chamas.keys().cloned().collect();
            for cid in ids {
                let members: Vec<String> = self.chamas[&cid].shares.keys().cloned().collect();
                for m in members {
                    let p = self.players.get_mut(&m).unwrap();
                    let c = contribution(p.pts);
                    p.pts -= c;
                    self.chamas.get_mut(&cid).unwrap().contribute(&m, c);
                }
            }
        }
        // 4. spoilage and personal consumption (goods sinks)
        for m in self.merchants.iter_mut() { for g in GOODS.iter() { if let Some(s) = m.stock.get_mut(g.id) { *s -= (*s as u64 * g.spoil_bp / BP) as u32; } } }
        for p in self.players.values_mut() {
            for g in GOODS.iter() { if let Some(s) = p.stock.get_mut(g.id) { *s -= (*s as u64 * g.spoil_bp / BP) as u32; } }
            if let Some((g, _)) = p.stock.iter().filter(|(_, q)| **q > 0).max_by_key(|(_, q)| **q).map(|(g, q)| (g.clone(), *q)) { *p.stock.get_mut(&g).unwrap() -= 1; }
        }
        // 5. day advances; events
        self.day = nd;
        if self.cfg.random_events {
            if let Some(e) = maybe_spawn(&mut self.rng, nd) { self.events.push(e); }
        }
        self.events.retain(|e| e.day + e.duration() > nd);
        for e in self.events.iter().filter(|e| e.day == nd) {
            self.news.push(NewsItem { day: nd, kind: e.kind, text: e.text() });
            if self.news.len() > 20 { self.news.remove(0); }
            out.push(e.text());
        }
        // 5a. market levy: a stall holding more than RICH_CASH pays 30% of the excess into the treasury (conserved, not burned)
        for m in self.merchants.iter_mut() { if m.cash > RICH_CASH { let levy = (m.cash - RICH_CASH) * 30 / 100; m.cash -= levy; self.treasury = self.treasury.saturating_add(levy); } }
        // 5b. townsfolk buy from stalls (paid from the treasury, i.e. farmers' receipts): goods sink and money return
        let festival = self.events.iter().filter(|e| e.kind == EventKind::Festival && e.active(nd)).map(|e| e.magnitude as u64).max().unwrap_or(0);
        // Townsfolk prefer the stall that looks poorest (shopper loyalty to the struggling neighbour): keeps stalls solvent.
        let avg_cash = (self.merchants.iter().map(|m| m.cash).sum::<Pts>() / self.merchants.len().max(1) as u64).max(1);
        for mi in 0..self.merchants.len() {
            let weight_pct = (avg_cash * 100 / self.merchants[mi].cash.max(1)).clamp(25, 300);
            for (gi, g) in GOODS.iter().enumerate() {
                let q = quote_ref(g, self.merchants[mi].stock[g.id], &self.mods(gi), self.merchants[mi].spread_bp, self.merchants[mi].ref_mid.get(g.id).copied());
                let want = (g.target_stock as u64 / 4).max(1) * (100 + festival) / 100 * weight_pct / 100;
                let n = want.min(self.merchants[mi].stock[g.id] as u64).min(self.treasury / q.ask.max(1));
                let pay = n * q.ask;
                self.treasury -= pay;
                self.merchants[mi].cash = self.merchants[mi].cash.saturating_add(pay);
                *self.merchants[mi].stock.get_mut(g.id).unwrap() -= n as u32;
            }
        }
        // 6. merchants restock from the treasury (wholesale)
        for mi in 0..self.merchants.len() {
            for (gi, g) in GOODS.iter().enumerate() {
                let mods = self.mods(gi);
                let stock = self.merchants[mi].stock[g.id];
                let mid = quote_ref(g, stock, &mods, 0, self.merchants[mi].ref_mid.get(g.id).copied()).mid;
                let unit = wholesale(mid);
                let gap = g.target_stock.saturating_sub(stock) as u64;
                let bulk = g.target_stock as u64 / 8 * mods.restock_bp.saturating_sub(BP) / BP;
                let mut n = gap.div_ceil(2) * mods.restock_bp / BP + bulk;
                n = n.min(self.merchants[mi].cash.saturating_sub(RESTOCK_RESERVE) / unit);
                let cost = n * unit;
                self.merchants[mi].cash -= cost;
                self.treasury = self.treasury.saturating_add(cost);
                *self.merchants[mi].stock.get_mut(g.id).unwrap() += n as u32;
            }
        }
        // 6b. roll the daily reference mid (closing mid, already clamped to +-20% of yesterday's)
        for mi in 0..self.merchants.len() {
            for (gi, g) in GOODS.iter().enumerate() {
                let q = quote_ref(g, self.merchants[mi].stock[g.id], &self.mods(gi), 0, self.merchants[mi].ref_mid.get(g.id).copied());
                self.merchants[mi].ref_mid.insert(g.id.to_string(), q.mid);
            }
        }
        // 7. thermostat stipend + treasury payout + stall rent
        let supply = self.supply() as i128;
        let target = self.target_supply as i128;
        let err_bp = (target - supply) * BP as i128 / target.max(1);
        let replace = self.burned - self.burned_mark;
        self.burned_mark = self.burned;
        let correction = err_bp * target / BP as i128 / 10; // close 10% of the gap per day
        let mint = (replace as i128 + correction).clamp(0, 3 * (self.cfg.stipend * self.players.len() as u64) as i128) as u64;
        let n = self.players.len() as u64;
        self.minted = self.minted.saturating_add(mint);
        let pay = self.treasury / 2;
        self.treasury -= pay;
        if let Some(each) = (mint + pay).checked_div(n) {
            let rem = (mint + pay) - each * n;
            for p in self.players.values_mut() { p.pts = p.pts.saturating_add(each); }
            self.treasury = self.treasury.saturating_add(rem);
        } else { self.treasury = self.treasury.saturating_add(pay); self.minted -= mint; }
        let rent_bp = if supply > target { 200 } else { 50 };
        for m in self.merchants.iter_mut() { let rent = m.cash * rent_bp / BP; m.cash -= rent; self.burned = self.burned.saturating_add(rent); }
    }

    /// Season end: chama cash is shared out by shares (closed loop; players cannot withdraw earlier).
    pub fn season_close(&mut self) {
        for c in self.chamas.values_mut() {
            for (m, a) in payout(c) { if let Some(p) = self.players.get_mut(&m) { p.pts = p.pts.saturating_add(a); } }
            c.cash = 0;
        }
    }

    pub fn price_index_bp(&self) -> u64 {
        let mut sum = 0u64; let mut n = 0u64;
        for mi in 0..self.merchants.len() { for g in GOODS.iter() { sum += self.quote(mi, g.id).unwrap().mid * BP / g.base; n += 1; } }
        sum / n.max(1)
    }

    /// Merchants able to afford a full restock of one good at the current day.
    pub fn solvent_merchants(&self) -> usize { self.merchants.iter().filter(|m| m.cash >= 20_000).count() }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn w() -> World { let mut w = World::new(Config { random_events: false, ..Config::default() }); w.phase = Phase::Midday; w }
    fn buy(w: &mut World, p: &str, q: u32) -> Result<Receipt, ErrorCode> {
        w.apply(p, &Action::Buy { merchant: "njeri".into(), good: "tomato".into(), qty: q, max_unit_price: 100_000 })
    }
    #[test]
    fn buy_sell_conserves_except_fee() {
        let mut w = w();
        let s0 = w.supply();
        buy(&mut w, "p000", 5).unwrap();
        assert_eq!(w.supply(), s0);
        w.apply("p000", &Action::Sell { merchant: "njeri".into(), good: "tomato".into(), qty: 5, min_unit_price: None }).unwrap();
        assert_eq!(w.supply() + w.burned, s0);
        assert!(w.players["p000"].pts < 20_000, "round trip must cost the player");
    }
    #[test]
    fn errors() {
        let mut w = w();
        assert_eq!(buy(&mut w, "p000", 21), Err(ErrorCode::NotEnoughStock));
        assert_eq!(w.apply("p000", &Action::Buy { merchant: "njeri".into(), good: "tomato".into(), qty: 1, max_unit_price: 1 }), Err(ErrorCode::PriceMoved));
        w.players.get_mut("p000").unwrap().pts = 1;
        assert_eq!(buy(&mut w, "p000", 1), Err(ErrorCode::NotEnoughPts));
        w.phase = Phase::Dawn;
        assert_eq!(buy(&mut w, "p001", 1), Err(ErrorCode::WrongPhase));
        assert_eq!(w.apply("nobody", &Action::Advance {}), Err(ErrorCode::NotMember));
    }
    #[test]
    fn haggle_once_per_day_and_cheaper() {
        let mut w = w();
        let ask = w.quote(0, "tomato").unwrap().ask;
        let h = Action::Haggle { merchant: "njeri".into(), good: "tomato".into() };
        w.apply("p000", &h).unwrap();
        assert_eq!(w.apply("p000", &h), Err(ErrorCode::RateLimited));
        let r = buy(&mut w, "p000", 1).unwrap();
        assert!(-r.pts_delta < ask as i64);
    }
    #[test]
    fn credit_repay_and_default() {
        let mut w = w();
        let cr = Action::CreditRequest { merchant: "njeri".into(), good: "tomato".into(), qty: 2 };
        w.apply("p000", &cr).unwrap();
        let id = *w.loans.keys().next().unwrap();
        let s = w.supply();
        w.apply("p000", &Action::CreditRepay { loan_id: id }).unwrap();
        assert_eq!(w.supply(), s);
        assert_eq!(w.players["p000"].score, 1);
        // default path
        w.apply("p001", &cr).unwrap();
        let id2 = *w.loans.keys().last().unwrap();
        w.players.get_mut("p001").unwrap().pts = 0;
        w.day = w.loans[&id2].due_day;
        w.phase = Phase::Dusk;
        w.apply("p001", &Action::Advance {}).unwrap();
        assert_eq!(w.loans[&id2].status, LoanStatus::Defaulted);
        assert_eq!(w.players["p001"].defaults, 1);
    }
    #[test]
    fn credit_limit_denied_without_chama() {
        let mut w = w();
        let big = Action::CreditRequest { merchant: "njeri".into(), good: "fish".into(), qty: 20 };
        assert_eq!(w.apply("p000", &big), Err(ErrorCode::CreditDenied));
    }
    #[test]
    fn chama_offer_flow() {
        let mut w = w();
        w.apply("p000", &Action::ChamaCreate {}).unwrap();
        let cid = w.players["p000"].chama.clone().unwrap();
        for p in ["p001", "p002", "p003"] { w.apply(p, &Action::ChamaJoin { chama_id: cid.clone() }).unwrap(); }
        for p in ["p001", "p002"] { w.players.get_mut(p).unwrap().pts += 0; }
        // chama needs cash for the offer: 4 * 2000 = 8000; request 3 fish ~ 18000 > cash, so use cheap sukuma
        let big = Action::CreditRequest { merchant: "njeri".into(), good: "sukuma".into(), qty: 6 };
        w.players.get_mut("p000").unwrap().score = 0;
        // force over-limit by existing debt
        w.apply("p000", &Action::CreditRequest { merchant: "njeri".into(), good: "fish".into(), qty: 1 }).unwrap();
        let r = w.apply("p000", &big);
        assert!(r.is_ok() && w.chamas[&cid].offer.is_some(), "{r:?}");
        {
            let oid = w.chamas[&cid].offer.as_ref().unwrap().id;
            assert_eq!(w.apply("p000", &Action::ChamaVote { offer_id: oid, vote: Vote::Yes }), Err(ErrorCode::WrongPhase));
            w.apply("p001", &Action::ChamaVote { offer_id: oid, vote: Vote::Yes }).unwrap();
            assert_eq!(w.apply("p001", &Action::ChamaVote { offer_id: oid, vote: Vote::Yes }), Err(ErrorCode::AlreadyVoted));
            w.apply("p002", &Action::ChamaVote { offer_id: oid, vote: Vote::Yes }).unwrap();
            assert!(w.loans.values().any(|l| matches!(l.lender, Lender::Chama(_))));
        }
        assert_eq!(w.apply("p010", &Action::ChamaVote { offer_id: 1, vote: Vote::Yes }), Err(ErrorCode::NotMember));
    }
    #[test]
    fn advance_without_players() {
        let mut w = World::new(Config { players: 0, random_events: false, ..Config::default() });
        assert_eq!(w.phase, Phase::Dawn);
        for _ in 0..3 { super::advance(&mut w).unwrap(); }
        assert_eq!((w.day, w.phase), (1, Phase::Dawn));
        // Action::Advance still works for a registered player and does the same thing.
        let mut w2 = World::new(Config { random_events: false, ..Config::default() });
        w2.apply("p000", &Action::Advance {}).unwrap();
        assert_eq!(w2.phase, Phase::Midday);
    }
    #[test]
    fn rejected_apply_leaves_world_unchanged() {
        let mut w = w();
        w.apply("p000", &Action::ChamaCreate {}).unwrap();
        let cid = w.players["p000"].chama.clone().unwrap();
        w.apply("p001", &Action::Haggle { merchant: "njeri".into(), good: "tomato".into() }).unwrap();
        w.players.get_mut("p002").unwrap().pts = 5;
        let snap = |w: &World| serde_json::to_string(w).unwrap();
        let bad: Vec<(&str, Action)> = vec![
            ("p000", Action::Buy { merchant: "njeri".into(), good: "tomato".into(), qty: 99, max_unit_price: 1 }),
            ("p000", Action::Buy { merchant: "njeri".into(), good: "tomato".into(), qty: 1, max_unit_price: 1 }),
            ("p002", Action::Buy { merchant: "njeri".into(), good: "tomato".into(), qty: 1, max_unit_price: 99999 }),
            ("p000", Action::Sell { merchant: "njeri".into(), good: "tomato".into(), qty: 1, min_unit_price: None }),
            ("p001", Action::Haggle { merchant: "njeri".into(), good: "tomato".into() }),
            ("p000", Action::ChamaCreate {}),
            ("p003", Action::ChamaJoin { chama_id: "nope".into() }),
            ("p002", Action::ChamaJoin { chama_id: cid.clone() }),
            ("p003", Action::ChamaVote { offer_id: 1, vote: Vote::Yes }),
            ("p000", Action::ChamaVote { offer_id: 77, vote: Vote::Yes }),
            ("p000", Action::CreditRepay { loan_id: 5 }),
            ("p000", Action::Guarantee { borrower: "p001".into(), loan_id: 5 }),
            ("p000", Action::CreditRequest { merchant: "njeri".into(), good: "fish".into(), qty: 20 }),
            ("p002", Action::Invest { merchant: "njeri".into(), pts: 1000 }),
            ("ghost", Action::Advance {}),
        ];
        for (p, a) in bad {
            let before = snap(&w);
            assert!(super::apply(&mut w, p, &a).is_err(), "{p} {a:?} should fail");
            assert_eq!(before, snap(&w), "state changed by rejected {a:?}");
        }
        w.phase = Phase::Dawn;
        let before = snap(&w);
        assert_eq!(w.apply("p001", &Action::Invest { merchant: "njeri".into(), pts: 10 }), Err(ErrorCode::WrongPhase));
        assert_eq!(before, snap(&w));
    }
    #[test]
    fn caps_and_pruning() {
        let mut w = w();
        w.players.get_mut("p000").unwrap().pts = 1_000_000;
        w.players.get_mut("p000").unwrap().score = 20;
        for _ in 0..MAX_INVESTMENTS { w.apply("p000", &Action::Invest { merchant: "njeri".into(), pts: 10 }).unwrap(); }
        assert_eq!(w.apply("p000", &Action::Invest { merchant: "njeri".into(), pts: 10 }), Err(ErrorCode::RateLimited));
        for _ in 0..MAX_OPEN_LOANS { w.apply("p001", &Action::CreditRequest { merchant: "njeri".into(), good: "sukuma".into(), qty: 1 }).unwrap(); }
        assert_eq!(w.apply("p001", &Action::CreditRequest { merchant: "njeri".into(), good: "sukuma".into(), qty: 1 }), Err(ErrorCode::CreditDenied));
        let ids: Vec<u64> = w.loans.keys().cloned().collect();
        for (i, id) in ids.iter().enumerate() {
            let r = w.apply("p000", &Action::Guarantee { borrower: "p001".into(), loan_id: *id });
            assert_eq!(r.is_ok(), i < MAX_OPEN_GUARANTEES, "guarantee {i}");
        }
        for _ in 0..4 { w.advance().unwrap(); w.advance().unwrap(); w.advance().unwrap(); }
        w.players.get_mut("p001").unwrap().pts = 0;
        for _ in 0..12 { w.advance().unwrap(); w.advance().unwrap(); w.advance().unwrap(); }
        assert!(w.loans.is_empty(), "settled loans pruned");
    }
    #[test]
    fn emptied_good_and_triple_event_stay_within_20pct() {
        let mut w = w();
        let before = w.quote(0, "tomato").unwrap();
        w.merchants[0].stock.insert("tomato".into(), 0);
        let empty = w.quote(0, "tomato").unwrap();
        assert!(empty.mid > before.mid);
        assert!(empty.mid <= before.mid * 12 / 10 + 1, "{} vs {}", empty.mid, before.mid);
        // 3x price event (fuel+ukame+festival at 100%) cannot lift the mid past +20% on the day it starts
        for k in [EventKind::Ukame, EventKind::Fuel, EventKind::Festival] { w.inject(Event::new(k, 0, 100)); }
        let hot = w.quote(0, "tomato").unwrap();
        assert!(hot.mid <= before.mid * 12 / 10 + 1);
        // and the next day's reference rises by at most another 20%
        w.phase = Phase::Dusk;
        let ref0 = w.merchants[0].ref_mid["tomato"];
        w.advance().unwrap();
        assert!(w.merchants[0].ref_mid["tomato"] <= ref0 * 12 / 10 + 1);
    }
    #[test]
    fn invest_matures() {
        let mut w = w();
        w.apply("p000", &Action::Invest { merchant: "njeri".into(), pts: 1_000 }).unwrap();
        w.day = INVEST_DAYS - 1; w.phase = Phase::Dusk;
        w.apply("p000", &Action::Advance {}).unwrap();
        assert!(w.investments.is_empty());
    }
}

/// Clock entry point (no player id). See `World::advance`.
pub fn advance(world: &mut World) -> Result<Receipt, ErrorCode> { world.advance() }

/// State-transition entry point for the contract and runner. Mutates `world` in place only on `Ok`
/// (on `Err` the world is unchanged). Time is `world.day`/`world.phase`; no wall clock is used.
pub fn apply(world: &mut World, player: &str, action: &Action) -> Result<Receipt, ErrorCode> {
    world.apply(player, action)
}

#[cfg(all(test, feature = "borsh"))]
mod borsh_tests {
    use super::*;
    #[test]
    fn size_report() {
        for (days, n) in [(0u32, 24usize), (30, 24), (60, 24), (0, 200)] {
            let (w, _) = crate::sim::simulate(Config { players: n, ..Config::default() }, days, &[]);
            eprintln!("SIZE players={n} day={days} borsh_bytes={}", borsh::to_vec(&w).unwrap().len());
        }
    }
    #[test]
    fn world_roundtrips() {
        let mut w = World::new(Config::default());
        w.apply("p000", &Action::ChamaCreate {}).unwrap();
        let b = borsh::to_vec(&w).unwrap();
        let w2: World = borsh::from_slice(&b).unwrap();
        assert_eq!(w2.supply(), w.supply());
        assert_eq!(w2.day, w.day);
    }
}
