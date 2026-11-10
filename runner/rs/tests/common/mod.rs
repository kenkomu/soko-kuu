#![allow(dead_code)]
use async_trait::async_trait;
use base64::Engine as _;
use ed25519_dalek::{Signer, SigningKey};
use serde_json::{json, Value};
use sokokuu_runner::app::{router, App, Options};
use sokokuu_runner::auth::{Mail, Mailer};
use sokokuu_runner::chain::{Chain, ChainError, SubmitReq};
use sokokuu_runner::sig;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

pub struct NoMail;
#[async_trait]
impl Mailer for NoMail { async fn send(&self, _m: Mail) -> Result<(), String> { Ok(()) } }

/// Scripted chain: records submissions; behaviour switchable.
pub struct MockChain { pub calls: Mutex<Vec<(String, u64)>>, pub behave: Mutex<&'static str>, pub chain_nonce: u64, pub rebinds: Mutex<Vec<(String, String)>>, pub balance: Mutex<Option<u128>>, pub hash: Mutex<Option<String>>, pub snapshot: Mutex<Option<Vec<u8>>>, pub snapshot_fetches: Mutex<u32> }
impl MockChain { pub fn new(chain_nonce: u64) -> Arc<Self> { Arc::new(MockChain { calls: Mutex::new(vec![]), behave: Mutex::new("ok"), chain_nonce, rebinds: Mutex::new(vec![]), balance: Mutex::new(None), hash: Mutex::new(None), snapshot: Mutex::new(None), snapshot_fetches: Mutex::new(0) }) } }
#[async_trait]
impl Chain for MockChain {
    async fn submit(&self, r: &SubmitReq) -> Result<String, ChainError> {
        self.calls.lock().unwrap().push((r.action.clone(), r.nonce));
        match *self.behave.lock().unwrap() {
            "reject" => Err(ChainError::Reject { code: "BAD_NONCE".into(), msg: "BAD_NONCE: x".into() }),
            "down" => Err(ChainError::Down("rpc down".into())),
            _ => Ok("abc".into()),
        }
    }
    async fn nonce_of(&self, _p: &str) -> Option<u64> { Some(self.chain_nonce) }
    async fn rebind_key(&self, old: &str, new: &str) -> Result<String, ChainError> {
        self.rebinds.lock().unwrap().push((old.into(), new.into()));
        match *self.behave.lock().unwrap() {
            "reject" => return Err(ChainError::Reject { code: "FORBIDDEN".into(), msg: "FORBIDDEN: key already in use".into() }),
            "reject_not_member" => return Err(ChainError::Reject { code: "NOT_MEMBER".into(), msg: "NOT_MEMBER: old key unknown".into() }),
            "down" => return Err(ChainError::Down("rpc down".into())),
            _ => {}
        }
        Ok("rebind-tx".into())
    }
    async fn world_hash(&self) -> Option<String> { self.hash.lock().unwrap().clone() }
    async fn world_snapshot(&self) -> Option<Vec<u8>> { *self.snapshot_fetches.lock().unwrap() += 1; self.snapshot.lock().unwrap().clone() }
    async fn balance_yocto(&self) -> Option<u128> { *self.balance.lock().unwrap() }
}

pub struct Key { pub sk: SigningKey, pub pubkey: String }
pub fn new_key() -> Key {
    let sk = SigningKey::from_bytes(&rand::random::<[u8; 32]>());
    let pubkey = format!("ed25519:{}", bs58::encode(sk.verifying_key().to_bytes()).into_string());
    Key { sk, pubkey }
}
/// `action_json`: the exact string that is signed and sent (no canonicalisation step).
pub fn canon(action: &Value) -> String { action.to_string() }
pub fn sign_canon(k: &Key, nonce: u64, exp: u64, canon_action: &str) -> String {
    let msg = sig::signed_message("testnet", "sokokuu.testnet", &k.pubkey, nonce, exp, canon_action);
    base64::engine::general_purpose::STANDARD.encode(k.sk.sign(msg.as_bytes()).to_bytes())
}
pub fn now() -> u64 { sokokuu_runner::app::now_ms() }

pub struct T { pub base: String, pub app: Arc<App>, pub c: reqwest::Client }
pub struct Resp { pub status: u16, pub headers: reqwest::header::HeaderMap, pub json: Value }
impl Resp {
    pub fn ok(&self) -> bool { self.json["ok"] == json!(true) }
    pub fn code(&self) -> String { self.json["error"]["code"].as_str().unwrap_or("").to_string() }
    pub fn data(&self) -> &Value { &self.json["data"] }
}

pub async fn start(extra: &[(&str, &str)]) -> T { start_with(extra, Options { mailer: Some(Arc::new(NoMail)), ..Default::default() }).await }
pub async fn start_with(extra: &[(&str, &str)], opts: Options) -> T {
    let mut env: HashMap<String, String> = [("MODE", "demo"), ("DEV_RETURN_TOKEN", "1"), ("DEMO_SEED", "7"), ("ADVANCE_COOLDOWN_MS", "0")].iter().map(|(a, b)| (a.to_string(), b.to_string())).collect();
    for (k, v) in extra { env.insert(k.to_string(), v.to_string()); }
    let app = App::build(&env, opts).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let r = router(app.clone());
    tokio::spawn(async move { axum::serve(listener, r.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap(); });
    T { base: format!("http://{addr}"), app, c: reqwest::Client::new() }
}

impl T {
    pub async fn call(&self, method: &str, path: &str, body: Option<Value>, headers: &[(&str, &str)]) -> Resp {
        let m = reqwest::Method::from_bytes(method.as_bytes()).unwrap();
        let mut rb = self.c.request(m, format!("{}{}", self.base, path));
        for (k, v) in headers { rb = rb.header(*k, *v); }
        if let Some(b) = body { rb = rb.json(&b); }
        let r = rb.send().await.unwrap();
        let (status, headers) = (r.status().as_u16(), r.headers().clone());
        let txt = r.text().await.unwrap();
        Resp { status, headers, json: serde_json::from_str(&txt).unwrap_or(Value::Null) }
    }
    pub async fn get(&self, path: &str) -> Resp { self.call("GET", path, None, &[]).await }
    pub async fn login(&self, k: &Key, email: &str) -> String {
        let r = self.call("POST", "/v1/auth/register", Some(json!({"email": email, "pubkey": k.pubkey, "consent": true})), &[]).await;
        let tok = r.data()["dev_token"].as_str().expect("dev token").to_string();
        let c = self.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": k.pubkey})), &[]).await;
        c.data()["player_id"].as_str().expect("player_id").to_string()
    }
    pub async fn guest(&self, k: &Key) -> Resp {
        self.call("POST", "/v1/auth/guest", Some(json!({"pubkey": k.pubkey, "age_confirmed": true})), &[]).await
    }
    pub async fn state(&self, k: &Key) -> Resp { self.get(&format!("/v1/state?pubkey={}", k.pubkey)).await }
}

pub struct Actor<'a> { pub t: &'a T, pub key: &'a Key, pub nonce: u64 }
impl<'a> Actor<'a> {
    pub fn new(t: &'a T, key: &'a Key) -> Self { Actor { t, key, nonce: 0 } }
    pub async fn act(&mut self, action: Value) -> Resp {
        let (n, exp) = (self.nonce + 1, now() + 60_000);
        let sig = sign_canon(self.key, n, exp, &canon(&action));
        let r = self.send(action, n, exp, sig).await;
        if r.ok() { self.nonce = n; }
        r
    }
    pub async fn send(&self, action: Value, nonce: u64, exp: u64, sig: String) -> Resp {
        self.t.call("POST", "/v1/act", Some(json!({"pubkey": self.key.pubkey, "nonce": nonce, "expires_ms": exp, "action_json": canon(&action), "sig": sig})), &[]).await
    }
}
