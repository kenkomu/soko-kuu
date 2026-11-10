//! Signed-act verification. Signed bytes (docs/API.md):
//! `sokokuu/v1|<chain_id>|<contract_id>|<pubkey>|<nonce>|<expires_ms>|<canonical_action_json>`
use base64::Engine as _;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};

pub fn parse_pubkey(pk: &str) -> Option<[u8; 32]> {
    let rest = pk.strip_prefix("ed25519:")?;
    let raw = bs58::decode(rest).into_vec().ok()?;
    raw.try_into().ok()
}

pub fn verify(pubkey: &str, message: &str, sig_b64: &str) -> bool {
    let Some(raw) = parse_pubkey(pubkey) else { return false };
    let Ok(vk) = VerifyingKey::from_bytes(&raw) else { return false };
    let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(sig_b64) else { return false };
    let Ok(sig) = Signature::from_slice(&bytes) else { return false };
    vk.verify(message.as_bytes(), &sig).is_ok()
}

pub fn signed_message(chain_id: &str, contract_id: &str, pubkey: &str, nonce: u64, expires_ms: u64, canonical_action: &str) -> String {
    format!("sokokuu/v1|{chain_id}|{contract_id}|{pubkey}|{nonce}|{expires_ms}|{canonical_action}")
}

pub const DELETE_ACCOUNT_JSON: &str = r#"{"type":"delete_account"}"#;
