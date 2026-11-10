//! Reputation tiers and credit rules.
use crate::action::Pts;
use serde::{Deserialize, Serialize};

pub const LOAN_DAYS: u32 = 5;
pub const MERCHANT_INTEREST_BP: u64 = 600;
pub const CHAMA_INTEREST_BP: u64 = 400;
/// Storage and collusion caps (docs/SECURITY_UX.md #8, #13).
pub const MAX_OPEN_GUARANTEES: usize = 2;
pub const MAX_OPEN_LOANS: usize = 5;
pub const MAX_INVESTMENTS: usize = 5;
/// Settled loans are pruned this many days after their due day.
pub const KEEP_SETTLED_DAYS: u32 = 3;
pub const DEFAULT_PENALTY: i32 = 3;

/// Score thresholds for tiers 0..=3.
pub const TIER_MIN_SCORE: [i32; 4] = [0, 3, 8, 15];
pub const TIER_LIMIT: [Pts; 4] = [9_000, 24_000, 60_000, 135_000];

pub fn tier(score: i32) -> u8 {
    let mut t = 0;
    for (i, m) in TIER_MIN_SCORE.iter().enumerate() { if score >= *m { t = i as u8; } }
    t
}
pub fn credit_limit(tier: u8) -> Pts { TIER_LIMIT[(tier as usize).min(3)] }
pub fn owed(cost: Pts, interest_bp: u64) -> Pts { cost.saturating_add(crate::pricing::mul_div(cost, interest_bp, 10_000)) }

/// Can a borrower with `outstanding` owed take a new loan of `owed_new`?
pub fn within_limit(score: i32, outstanding: Pts, owed_new: Pts) -> bool {
    outstanding.saturating_add(owed_new) <= credit_limit(tier(score))
}

/// Score change on repay: +1 on time, 0 if late.
pub fn repay_delta(on_time: bool) -> i32 { if on_time { 1 } else { 0 } }

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(rename_all = "snake_case")]
pub enum LoanStatus { Open, Repaid, Defaulted }

/// Guarantor needs tier >= 1.
pub fn can_guarantee(guarantor_score: i32) -> bool { tier(guarantor_score) >= 1 }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tiers() {
        assert_eq!((tier(0), tier(2), tier(3), tier(8), tier(99)), (0, 0, 1, 2, 3));
        assert_eq!(credit_limit(9), 135_000);
    }
    #[test]
    fn limits() {
        assert!(within_limit(0, 5_000, 4_000));
        assert!(!within_limit(0, 5_000, 4_001));
        assert_eq!(owed(10_000, 600), 10_600);
        assert!(!can_guarantee(2) && can_guarantee(3));
    }
}
