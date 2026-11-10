//! Rule-based pricing. Integer basis-point math only. No LLM, no floats.
use crate::action::Pts;
use serde::{Deserialize, Serialize};

pub const BP: u64 = 10_000;
/// Max change of a merchant's mid price per day, in bp (+-20%).
pub const MAX_DAILY_MOVE_BP: u64 = 2_000;

/// `a * b / c` in u128, saturating to u64::MAX. Used for every bp/ratio computation.
pub fn mul_div(a: u64, b: u64, c: u64) -> u64 {
    let c = c.max(1) as u128;
    u64::try_from(a as u128 * b as u128 / c).unwrap_or(u64::MAX)
}
pub const MAX_QTY: u32 = 20;
/// Market fee on sells, burned (sink).
pub const FEE_BP: u64 = 200;
pub const BASE_SPREAD_BP: u64 = 800;
pub const WHOLESALE_BP: u64 = 7_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GoodDef {
    pub id: &'static str,
    pub base: Pts,
    pub target_stock: u32,
    /// Daily spoilage of stock, in bp (floored, so tiny stocks are safe).
    pub spoil_bp: u64,
    pub farm: bool,
}

pub const GOODS: [GoodDef; 6] = [
    GoodDef { id: "tomato", base: 3000, target_stock: 40, spoil_bp: 400, farm: true },
    GoodDef { id: "maize", base: 2200, target_stock: 40, spoil_bp: 100, farm: true },
    GoodDef { id: "sukuma", base: 1200, target_stock: 40, spoil_bp: 500, farm: true },
    GoodDef { id: "onion", base: 2800, target_stock: 40, spoil_bp: 100, farm: true },
    GoodDef { id: "fish", base: 6000, target_stock: 40, spoil_bp: 400, farm: false },
    GoodDef { id: "charcoal", base: 4500, target_stock: 40, spoil_bp: 0, farm: false },
];

pub fn good_index(id: &str) -> Option<usize> { GOODS.iter().position(|g| g.id == id) }
pub fn good(id: &str) -> Option<&'static GoodDef> { GOODS.iter().find(|g| g.id == id) }

/// Event-driven multipliers for one good on one day (10_000 = neutral).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Modifiers {
    pub price_bp: u64,
    pub restock_bp: u64,
    pub why: Vec<String>,
}
impl Modifiers {
    pub fn neutral() -> Self { Modifiers { price_bp: BP, restock_bp: BP, why: vec![] } }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Quote {
    pub mid: Pts,
    pub ask: Pts,
    pub bid: Pts,
    pub stock: u32,
    pub why: Vec<String>,
}

/// Stock factor: scarce -> dearer, plentiful -> cheaper. Linear, clamped to [5000, 20000] bp.
pub fn stock_factor_bp(stock: u32, target: u32) -> u64 {
    let t = target.max(1) as i64;
    let f = BP as i64 + (t - stock as i64) * 6_000 / t;
    f.clamp(5_000, 20_000) as u64
}

/// Price for `good` given merchant stock, event modifiers, spread (bp) and reputation (tier discount on ask).
pub fn quote(def: &GoodDef, stock: u32, mods: &Modifiers, spread_bp: u64) -> Quote { quote_ref(def, stock, mods, spread_bp, None) }

/// Like `quote`, but with `ref_mid` (the mid at the start of the day) the mid may only move +-20% from it.
pub fn quote_ref(def: &GoodDef, stock: u32, mods: &Modifiers, spread_bp: u64, ref_mid: Option<u64>) -> Quote {
    let sf = stock_factor_bp(stock, def.target_stock);
    let mut mid = mul_div(mul_div(def.base, sf, BP), mods.price_bp, BP);
    mid = mid.clamp(def.base / 4, def.base * 4).max(2);
    let mut cap_line: Option<String> = None;
    if let Some(r) = ref_mid {
        let (lo, hi) = (mul_div(r, BP - MAX_DAILY_MOVE_BP, BP).max(2), mul_div(r, BP + MAX_DAILY_MOVE_BP, BP));
        if mid > hi { cap_line = Some(format!("Price rise limited to {}% today; it may climb further tomorrow.", MAX_DAILY_MOVE_BP / 100)); }
        else if mid < lo { cap_line = Some(format!("Price fall limited to {}% today; it may drop further tomorrow.", MAX_DAILY_MOVE_BP / 100)); }
        mid = mid.clamp(lo, hi);
    }
    let spread_bp = spread_bp.min(BP / 2);
    let ask = mul_div(mid, BP + spread_bp, 1).div_ceil(BP);
    let mut bid = mul_div(mid, BP - spread_bp, BP);
    if bid >= ask { bid = ask - 1; }
    let mut why = Vec::new();
    if sf > 10_300 { why.push(format!("{} is scarce at this stall, so the price is {}% above normal.", def.id, (sf - BP) / 100)); }
    else if sf < 9_700 { why.push(format!("{} is plentiful at this stall, so the price is {}% below normal.", def.id, (BP - sf) / 100)); }
    else { why.push(format!("{} stock is near normal, so the price sits near its usual level.", def.id)); }
    why.extend(mods.why.iter().cloned());
    why.extend(cap_line);
    Quote { mid, ask, bid, stock, why }
}

/// Haggle: deterministic discount (bp) off ask, 200..=600 plus 100 per reputation tier. Free to try, capped.
pub fn haggle_discount_bp(hash: u64, tier: u8) -> u64 { 200 + hash % 401 + 100 * tier as u64 }

pub fn apply_discount(ask: Pts, bp: u64) -> Pts { mul_div(ask, BP - bp.min(2_000), BP).max(1) }

pub fn fee(total: Pts) -> Pts { mul_div(total, FEE_BP, BP) }

/// Wholesale cost the merchant pays when restocking one unit.
pub fn wholesale(mid: Pts) -> Pts { mul_div(mid, WHOLESALE_BP, BP).max(1) }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scarcity_raises_price() {
        let g = &GOODS[0];
        let m = Modifiers::neutral();
        let lo = quote(g, 5, &m, 800);
        let mid = quote(g, 40, &m, 800);
        let hi = quote(g, 80, &m, 800);
        assert!(lo.ask > mid.ask && mid.ask > hi.ask);
        assert_eq!(mid.mid, g.base);
    }
    #[test]
    fn bid_below_ask_and_bounded() {
        for g in GOODS.iter() {
            for s in [0u32, 1, 10, 40, 200] {
                let q = quote(g, s, &Modifiers { price_bp: 30_000, restock_bp: BP, why: vec![] }, 800);
                assert!(q.bid < q.ask);
                assert!(q.mid <= g.base * 4 && q.mid >= g.base / 4);
            }
        }
    }
    #[test]
    fn daily_clamp() {
        let g = &GOODS[0];
        let wild = Modifiers { price_bp: 30_000, restock_bp: BP, why: vec![] };
        let q = quote_ref(g, 0, &wild, 800, Some(3000));
        assert_eq!(q.mid, 3600);
        assert!(q.why.iter().any(|l| l.contains("rise limited to 20%")));
        let q = quote_ref(g, 200, &Modifiers { price_bp: 3_000, restock_bp: BP, why: vec![] }, 800, Some(3000));
        assert_eq!(q.mid, 2400);
        assert!(q.why.iter().any(|l| l.contains("fall limited to 20%")));
        assert!(!quote_ref(g, 40, &Modifiers::neutral(), 800, Some(3000)).why.iter().any(|l| l.contains("limited")));
        assert_eq!(mul_div(u64::MAX, u64::MAX, 1), u64::MAX);
    }
    #[test]
    fn haggle_capped() {
        for h in 0..1000u64 { assert!(haggle_discount_bp(h, 3) <= 1300); }
        assert!(apply_discount(1000, 9_999) >= 800);
    }
}
