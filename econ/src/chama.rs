//! Chama (savings group) rules: shared cash pool, member shares, majority votes on loan offers.
use crate::action::{Pts, Vote};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const MAX_MEMBERS: usize = 8;
pub const JOIN_SHARE: Pts = 2_000;
/// Weekly contribution: 5% of member pts, capped.
pub const CONTRIB_BP: u64 = 500;
pub const CONTRIB_CAP: Pts = 3_000;
pub const CONTRIB_EVERY_DAYS: u32 = 7;
/// Offers expire this many days after opening.
pub const OFFER_DAYS: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Offer {
    pub id: u64,
    pub borrower: String,
    pub merchant: String,
    pub good: String,
    pub qty: u32,
    pub cost: Pts,
    pub owed: Pts,
    pub deadline_day: u32,
    pub votes: BTreeMap<String, Vote>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tally { Pending, Approved, Rejected }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Chama {
    pub id: String,
    pub cash: Pts,
    /// member -> shares (pts contributed)
    pub shares: BTreeMap<String, Pts>,
    pub offer: Option<Offer>,
}

impl Chama {
    pub fn new(id: String) -> Self { Chama { id, cash: 0, shares: BTreeMap::new(), offer: None } }
    pub fn is_member(&self, p: &str) -> bool { self.shares.contains_key(p) }
    pub fn contribute(&mut self, p: &str, amt: Pts) { { let e = self.shares.entry(p.to_string()).or_insert(0); *e = e.saturating_add(amt); } self.cash += amt; }
    pub fn total_shares(&self) -> Pts { self.shares.values().sum() }
}

/// Majority of ALL members decides; the borrower does not vote (needs > half of the other members).
pub fn tally(members: usize, offer: &Offer) -> Tally {
    let voters = members.saturating_sub(1);
    let yes = offer.votes.values().filter(|v| **v == Vote::Yes).count();
    let no = offer.votes.values().filter(|v| **v == Vote::No).count();
    if voters == 0 { return Tally::Rejected; }
    if yes * 2 > voters { Tally::Approved } else if no * 2 >= voters { Tally::Rejected } else { Tally::Pending }
}

/// Weekly contribution for a member holding `pts`.
pub fn contribution(pts: Pts) -> Pts { crate::pricing::mul_div(pts, CONTRIB_BP, 10_000).min(CONTRIB_CAP) }

/// Split the chama cash at season end by shares. Sums exactly to cash (remainder to first member).
pub fn payout(c: &Chama) -> BTreeMap<String, Pts> {
    let total = c.total_shares();
    let mut out = BTreeMap::new();
    if total == 0 { return out; }
    let mut paid = 0;
    for (m, s) in &c.shares { let a = crate::pricing::mul_div(c.cash, *s, total); paid += a; out.insert(m.clone(), a); }
    if let Some((_, v)) = out.iter_mut().next() { *v += c.cash - paid; }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    fn offer() -> Offer { Offer { id: 1, borrower: "a".into(), merchant: "m".into(), good: "g".into(), qty: 1, cost: 10, owed: 11, deadline_day: 1, votes: BTreeMap::new() } }
    #[test]
    fn tally_rules() {
        let mut o = offer();
        assert_eq!(tally(5, &o), Tally::Pending);
        for p in ["b", "c"] { o.votes.insert(p.into(), Vote::Yes); }
        assert_eq!(tally(5, &o), Tally::Pending);
        o.votes.insert("d".into(), Vote::Yes);
        assert_eq!(tally(5, &o), Tally::Approved);
        let mut o2 = offer();
        for p in ["b", "c"] { o2.votes.insert(p.into(), Vote::No); }
        assert_eq!(tally(5, &o2), Tally::Rejected);
        assert_eq!(tally(1, &offer()), Tally::Rejected);
    }
    #[test]
    fn payout_exact() {
        let mut c = Chama::new("c1".into());
        c.contribute("a", 1000); c.contribute("b", 1000); c.contribute("c", 1000);
        c.cash += 101;
        let p = payout(&c);
        assert_eq!(p.values().sum::<u64>(), c.cash);
    }
    #[test]
    fn payout_never_leaves_dust() {
        let mut r = crate::rng::Rng::new(9);
        for _ in 0..500 {
            let mut c = Chama::new("c".into());
            for i in 0..(2 + r.below(7)) { c.contribute(&format!("m{i}"), 1 + r.below(50_000)); }
            c.cash += r.below(100_000); // interest earned
            let out = payout(&c);
            assert_eq!(out.values().sum::<u64>(), c.cash, "dust or overpay");
            assert_eq!(out.len(), c.shares.len());
        }
    }
    #[test]
    fn contrib_cap() { assert_eq!(contribution(1_000_000), CONTRIB_CAP); assert_eq!(contribution(10_000), 500); }
}
