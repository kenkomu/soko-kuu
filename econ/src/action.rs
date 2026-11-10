//! Public, stable action types matching docs/API.md `POST /v1/act`.
//! Serialized as `{"type":"buy", ...}` with snake_case tags.
use serde::{Deserialize, Serialize};

/// Integer points (pointi). Never floats.
pub type Pts = u64;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(rename_all = "snake_case")]
pub enum Vote {
    Yes,
    No,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Action {
    Buy { merchant: String, good: String, qty: u32, max_unit_price: Pts },
    Sell { merchant: String, good: String, qty: u32, #[serde(default, skip_serializing_if = "Option::is_none")] min_unit_price: Option<Pts> },
    Haggle { merchant: String, good: String },
    ChamaCreate {},
    ChamaJoin { chama_id: String },
    ChamaVote { offer_id: u64, vote: Vote },
    CreditRequest { merchant: String, good: String, qty: u32 },
    CreditRepay { loan_id: u64 },
    Guarantee { borrower: String, loan_id: u64 },
    Invest { merchant: String, pts: Pts },
    Advance {},
}

/// Error codes from docs/API.md.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    BadSig, BadNonce, Expired, NotEnoughPts, NotEnoughStock, CreditDenied,
    NotMember, AlreadyVoted, WrongPhase, RateLimited, Internal,
    PriceMoved,
    Forbidden,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(rename_all = "snake_case")]
pub enum Phase { Dawn, Midday, Dusk }

impl Phase {
    pub fn next(self) -> (Phase, bool) {
        match self { Phase::Dawn => (Phase::Midday, false), Phase::Midday => (Phase::Dusk, false), Phase::Dusk => (Phase::Dawn, true) }
    }
}

/// Canonical JSON: keys sorted, no spaces (the bytes that get signed).
pub fn canonical_json(a: &Action) -> String {
    // serde_json::Value uses BTreeMap (sorted) unless preserve_order is enabled.
    let v = serde_json::to_value(a).expect("serializable");
    serde_json::to_string(&v).expect("serializable")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_sorted() {
        let a = Action::Buy { merchant: "njeri".into(), good: "tomato".into(), qty: 3, max_unit_price: 3900 };
        assert_eq!(canonical_json(&a), r#"{"good":"tomato","max_unit_price":3900,"merchant":"njeri","qty":3,"type":"buy"}"#);
    }
    #[test]
    fn roundtrip_all() {
        let j = r#"{"type":"chama_vote","offer_id":4,"vote":"yes"}"#;
        let a: Action = serde_json::from_str(j).unwrap();
        assert_eq!(a, Action::ChamaVote { offer_id: 4, vote: Vote::Yes });
        let adv: Action = serde_json::from_str(r#"{"type":"advance"}"#).unwrap();
        assert_eq!(adv, Action::Advance {});
        assert_eq!(canonical_json(&adv), r#"{"type":"advance"}"#);
    }
}
