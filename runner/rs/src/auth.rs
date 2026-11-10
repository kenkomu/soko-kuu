//! Email magic-link login. Only a hash of the email is kept; consent is required.
//! Tokens are bound to the registering pubkey, single use, valid 10 minutes and stored hashed.
use async_trait::async_trait;
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::collections::HashMap;

const TTL_MS: u64 = 10 * 60 * 1000;

pub struct Mail { pub to: String, pub subject: String, pub text: String }

#[async_trait]
pub trait Mailer: Send + Sync {
    async fn send(&self, m: Mail) -> Result<(), String>;
}

/// Dev mailer: logs a masked address and the link to stdout.
pub struct LogMailer;
#[async_trait]
impl Mailer for LogMailer {
    async fn send(&self, m: Mail) -> Result<(), String> {
        let masked = match m.to.split_once('@') { Some((l, d)) => format!("{}***@{d}", l.chars().next().unwrap_or('*')), None => "***".into() };
        println!("[mail:dev] to={masked} {}", m.text.lines().nth(1).unwrap_or(""));
        Ok(())
    }
}

pub struct WebhookMailer { pub url: String, pub client: reqwest::Client }
#[async_trait]
impl Mailer for WebhookMailer {
    async fn send(&self, m: Mail) -> Result<(), String> {
        let r = self.client.post(&self.url).json(&serde_json::json!({"to": m.to, "subject": m.subject, "text": m.text})).send().await.map_err(|e| e.to_string())?;
        if r.status().is_success() { Ok(()) } else { Err("mail webhook failed".into()) }
    }
}

pub fn sha_hex(s: &str) -> String { Sha256::digest(s.as_bytes()).iter().map(|b| format!("{b:02x}")).collect() }

fn email_ok(e: &str) -> bool {
    let Some((l, d)) = e.split_once('@') else { return false };
    !l.is_empty() && l.len() <= 64 && !e.contains(char::is_whitespace) && !d.contains('@') && d.len() <= 255 && d.rsplit_once('.').is_some_and(|(h, t)| !h.is_empty() && t.len() >= 2)
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Pending { email_hash: String, pubkey: String, exp: u64 }

#[derive(Default)]
pub struct Auth {
    pending: HashMap<String, Pending>,       // sha256(token) -> pending
    bound: HashMap<String, String>,          // email hash -> player id (one account per verified email)
    email_sends: HashMap<String, Vec<u64>>,  // email hash -> send times (3 per hour)
    pub confirm_url: String,
    pub mails_per_hour: usize,
}

/// Durable form: hashes only, never an address.
#[derive(serde::Serialize, serde::Deserialize, Default)]
struct AuthState { pending: HashMap<String, Pending>, bound: HashMap<String, String>, email_sends: HashMap<String, Vec<u64>> }

pub enum AuthErr { Invalid(String), Expired(String), BadKey(String), Rate(u64) }

impl Auth {
    pub fn new(confirm_url: String) -> Self { Auth { confirm_url, mails_per_hour: 3, ..Default::default() } }
    /// Validates and creates a token. Returns (raw token, mail to send).
    pub fn register(&mut self, email: &str, pubkey: &str, consent: bool, now: u64) -> Result<(String, Mail), AuthErr> {
        if !consent { return Err(AuthErr::Invalid("Consent is required to create an account.".into())); }
        let email = email.trim();
        if !email_ok(email) { return Err(AuthErr::Invalid("Invalid email.".into())); }
        if crate::sig::parse_pubkey(pubkey).is_none() { return Err(AuthErr::BadKey("Invalid pubkey (expected ed25519:<base58>).".into())); }
        let h = sha_hex(&email.to_lowercase());
        let sends = self.email_sends.entry(h.clone()).or_default();
        sends.retain(|t| now.saturating_sub(*t) < 3_600_000);
        if sends.len() >= self.mails_per_hour {
            return Err(AuthErr::Rate(3_600_000u64.saturating_sub(now.saturating_sub(sends[0])) / 1000 + 1));
        }
        sends.push(now);
        self.pending.retain(|_, v| v.exp >= now);
        let mut raw = [0u8; 24]; rand::thread_rng().fill_bytes(&mut raw);
        let token = bs58::encode(raw).into_string();
        self.pending.insert(sha_hex(&token), Pending { email_hash: h, pubkey: pubkey.into(), exp: now + TTL_MS });
        let mail = Mail { to: email.into(), subject: "Your Soko Kuu sign-in link".into(),
            text: format!("Open this link to sign in (valid 10 minutes):\n{}{token}\nIf you did not ask for this, ignore this email.", self.confirm_url) };
        Ok((token, mail))
    }
    /// Consumes the token and returns the email hash. A different pubkey is BAD_SIG (token is kept).
    pub fn confirm(&mut self, token: &str, pubkey: &str, now: u64) -> Result<String, AuthErr> {
        let key = sha_hex(token); // tokens are stored hashed
        match self.pending.get(&key) {
            Some(v) if v.exp >= now => { if v.pubkey != pubkey { return Err(AuthErr::BadKey("This link was issued for a different key.".into())); } }
            _ => return Err(AuthErr::Expired("Link is invalid or expired.".into())),
        }
        Ok(self.pending.remove(&key).unwrap().email_hash)
    }
    pub fn export(&self) -> serde_json::Value {
        let st = AuthState {
            pending: self.pending.iter().map(|(k, v)| (k.clone(), Pending { email_hash: v.email_hash.clone(), pubkey: v.pubkey.clone(), exp: v.exp })).collect(),
            bound: self.bound.clone(), email_sends: self.email_sends.clone(),
        };
        serde_json::to_value(st).unwrap_or_default()
    }
    pub fn import(&mut self, v: serde_json::Value) -> Result<(), String> {
        let st: AuthState = serde_json::from_value(v).map_err(|e| e.to_string())?;
        self.pending = st.pending; self.bound = st.bound; self.email_sends = st.email_sends;
        Ok(())
    }
    pub fn player_for(&self, email_hash: &str) -> Option<&String> { self.bound.get(email_hash) }
    pub fn bind(&mut self, email_hash: String, player_id: String) { self.bound.insert(email_hash, player_id); }
    pub fn unbind_player(&mut self, player_id: &str) { self.bound.retain(|_, v| v != player_id); }
}
