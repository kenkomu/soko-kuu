//! Chain adapters. The runner validates, then submits the signed act to the contract and pays gas.
//! Contract ABI (from `contract`): act({pubkey, nonce, expires_ms, action, sig}); `action` is the exact
//! canonical JSON string that was signed. Views: nonce_of(pubkey), pts_of(pubkey), clock(), chain_id().
//! Panics are prefixed with an error code.
use async_trait::async_trait;
use sha2::{Digest, Sha256};

pub struct SubmitReq {
    pub pubkey: String,
    pub nonce: u64,
    pub expires_ms: u64,
    /// `action_json`: the exact string the player signed (sent to the contract's `action` param)
    pub action: String,
    pub sig: String,
    /// full signed message
    pub message: String,
}

#[derive(Debug, Clone)]
pub enum ChainError {
    /// The contract rejected the act (code is one of docs/API.md codes).
    Reject { code: String, msg: String },
    /// Chain or relayer unreachable.
    Down(String),
}

#[async_trait]
pub trait Chain: Send + Sync {
    async fn submit(&self, req: &SubmitReq) -> Result<String, ChainError>;
    async fn nonce_of(&self, pubkey: &str) -> Option<u64>;
    /// Relayer-only clock advance (`advance_clock()` on the contract).
    /// Relayer-only: move a player's on-chain identity from `old` to `new` pubkey.
    async fn rebind_key(&self, _old: &str, _new: &str) -> Result<String, ChainError> { Ok("demo:rebind".into()) }
    /// Relayer account balance in yoctoNEAR, if known (balance alarm).
    async fn balance_yocto(&self) -> Option<u128> { None }
    async fn advance_clock(&self) -> Result<String, ChainError> { Ok("demo:clock".into()) }
    /// The contract's own clock `(day, phase)` (`clock` view), if readable. Used to start the local engine in step.
    /// The contract's balance for a player (`pts_of` view), to detect drift between the contract and the local engine.
    async fn pts_of(&self, _pubkey: &str) -> Option<u64> { None }
    /// `world_hash` view: first 16 bytes of sha256(Borsh(World)) as 32 hex chars. None = view missing or unreachable (skip).
    async fn world_hash(&self) -> Option<String> { None }
    /// `world_snapshot` view: Borsh bytes of the whole econ World. None = view missing or unreachable (skip).
    async fn world_snapshot(&self) -> Option<Vec<u8>> { None }
    async fn chain_clock(&self) -> Option<(u32, String)> { None }
}

const CODES: [&str; 14] = ["BAD_SIG", "BAD_NONCE", "EXPIRED", "NOT_ENOUGH_PTS", "NOT_ENOUGH_STOCK", "CREDIT_DENIED", "NOT_MEMBER", "ALREADY_VOTED",
    "WRONG_PHASE", "PRICE_MOVED", "FORBIDDEN", "RATE_LIMITED", "NON_TRANSFERABLE", "INTERNAL"];

/// Maps a contract panic message to a rejection. NON_TRANSFERABLE becomes INTERNAL (no such public code).
pub fn parse_chain_error(msg: &str) -> Option<ChainError> {
    let is_code_char = |c: char| c.is_ascii_uppercase() || c == '_';
    for code in CODES {
        let mut from = 0;
        while let Some(i) = msg[from..].find(code) {
            let s = from + i; let e = s + code.len();
            let before_ok = msg[..s].chars().next_back().is_none_or(|c| !is_code_char(c));
            let after_ok = msg[e..].chars().next().is_none_or(|c| !is_code_char(c));
            if before_ok && after_ok {
                let mapped = if code == "NON_TRANSFERABLE" { "INTERNAL" } else { code };
                // keep only the contract's own words: `CODE: text` inside the RPC's Debug wrapper becomes `text`
                let rest = msg[e..].trim_start_matches(':').trim_start();
                let text: String = rest.chars().take_while(|c| *c != '"' && *c != '\\').collect();
                let text = if text.trim().is_empty() { "Action refused by the contract".to_string() } else { text.trim().to_string() };
                return Some(ChainError::Reject { code: mapped.into(), msg: text.chars().take(200).collect() });
            }
            from = e;
        }
    }
    None
}

pub struct DemoChain;
#[async_trait]
impl Chain for DemoChain {
    async fn submit(&self, req: &SubmitReq) -> Result<String, ChainError> {
        let h: String = Sha256::digest(req.message.as_bytes()).iter().map(|b| format!("{b:02x}")).collect();
        Ok(format!("demo:{}", &h[..44]))
    }
    async fn nonce_of(&self, _pubkey: &str) -> Option<u64> { None }
}
