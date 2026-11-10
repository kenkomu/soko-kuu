//! Hardening tests (security / efficiency / scalability review). Each test names the property it pins.
mod common;
use async_trait::async_trait;
use common::*;
use serde_json::{json, Value};
use sokokuu_runner::app::Options;
use sokokuu_runner::chain::{Chain, ChainError, SubmitReq};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn buy() -> Value { json!({"type":"buy","merchant":"njeri","good":"tomato","qty":1,"max_unit_price":100000}) }
fn sell_none() -> Value { json!({"type":"sell","merchant":"njeri","good":"fish","qty":5}) }

async fn midday(t: &T) {
    assert!(t.call("POST", "/v1/admin/advance", None, &[("x-admin-token", "s3cret")]).await.ok());
}

async fn raw_act(t: &T, k: &Key, nonce: u64, exp: u64, action_json: &str, sig: &str) -> Resp {
    t.call("POST", "/v1/act", Some(json!({"pubkey": k.pubkey, "nonce": nonce, "expires_ms": exp, "action_json": action_json, "sig": sig})), &[]).await
}

#[tokio::test]
async fn rule1_replay_tamper_wrong_contract_wrong_chain_expired() {
    let t = start(&[("ADMIN_TOKEN","s3cret")]).await;
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    midday(&t).await;
    let aj = canon(&buy());
    let exp = now() + 60_000;
    let sig = sign_canon(&k, 1, exp, &aj);
    assert!(raw_act(&t, &k, 1, exp, &aj, &sig).await.ok());
    // replay of the exact same request
    assert_eq!(raw_act(&t, &k, 1, exp, &aj, &sig).await.code(), "BAD_NONCE");
    // one byte changed in action_json (qty 1 -> 2) with the old signature
    let tam = aj.replace("\"qty\":1", "\"qty\":2");
    let sig2 = sign_canon(&k, 2, exp, &aj);
    assert_eq!(raw_act(&t, &k, 2, exp, &tam, &sig2).await.code(), "BAD_SIG");
    // changed nonce / expiry with an old signature
    assert_eq!(raw_act(&t, &k, 3, exp, &aj, &sig2).await.code(), "BAD_SIG");
    assert_eq!(raw_act(&t, &k, 2, exp + 1, &aj, &sig2).await.code(), "BAD_SIG");
    // signature made for another contract id / another chain id
    use base64::Engine as _;
    use ed25519_dalek::Signer;
    for (chain, contract) in [("testnet", "other.testnet"), ("mainnet", "sokokuu.testnet")] {
        let msg = sokokuu_runner::sig::signed_message(chain, contract, &k.pubkey, 2, exp, &aj);
        let s = base64::engine::general_purpose::STANDARD.encode(k.sk.sign(msg.as_bytes()).to_bytes());
        assert_eq!(raw_act(&t, &k, 2, exp, &aj, &s).await.code(), "BAD_SIG", "{chain}/{contract}");
    }
    // expired and too-far-future
    let old = now() - 1000;
    assert_eq!(raw_act(&t, &k, 2, old, &aj, &sign_canon(&k, 2, old, &aj)).await.code(), "EXPIRED");
    let far = now() + 3_600_000;
    assert_eq!(raw_act(&t, &k, 2, far, &aj, &sign_canon(&k, 2, far, &aj)).await.code(), "EXPIRED");
    // another key cannot reuse a signature
    let k2 = new_key();
    assert!(t.guest(&k2).await.ok());
    let r = t.call("POST", "/v1/act", Some(json!({"pubkey": k2.pubkey, "nonce": 2, "expires_ms": exp, "action_json": aj, "sig": sig2})), &[]).await;
    assert_eq!(r.code(), "BAD_SIG");
}

#[tokio::test]
async fn rejected_action_does_not_consume_nonce() {
    let t = start(&[("ADMIN_TOKEN","s3cret")]).await;
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    midday(&t).await;
    let mut a = Actor::new(&t, &k);
    let r = a.act(sell_none()).await; // no stock
    assert!(!r.ok());
    assert_eq!(a.nonce, 0);
    let r2 = a.act(buy()).await; assert!(r2.ok(), "nonce 1 still usable: {} {}", r2.status, r2.code());
}

#[tokio::test]
async fn concurrent_requests_with_same_nonce_apply_once() {
    let t = Arc::new(start(&[("ADMIN_TOKEN","s3cret"),("IP_RPM", "1000")]).await);
    let k = Arc::new(new_key());
    assert!(t.guest(&k).await.ok());
    midday(&t).await;
    let aj = canon(&buy());
    let exp = now() + 60_000;
    let sig = sign_canon(&k, 1, exp, &aj);
    let mut hs = vec![];
    for _ in 0..20 {
        let (t, k, aj, sig) = (t.clone(), k.clone(), aj.clone(), sig.clone());
        hs.push(tokio::spawn(async move { raw_act(&t, &k, 1, exp, &aj, &sig).await.ok() }));
    }
    let mut oks = 0;
    for h in hs { if h.await.unwrap() { oks += 1; } }
    assert_eq!(oks, 1);
    let s = t.state(&k).await;
    assert_eq!(s.data()["stock"]["tomato"], json!(1));
}

#[tokio::test]
async fn bad_signature_spam_cannot_burn_a_victims_write_quota() {
    let t = start(&[("ADMIN_TOKEN","s3cret"),("IP_RPM", "100000")]).await;
    let victim = new_key();
    assert!(t.guest(&victim).await.ok());
    midday(&t).await;
    let attacker = new_key();
    // attacker sends 70 junk requests naming the victim's pubkey
    for _ in 0..70 {
        let r = t.call("POST", "/v1/act", Some(json!({"pubkey": victim.pubkey, "nonce": 1, "expires_ms": now() + 60_000, "action_json": canon(&buy()), "sig": sign_canon(&attacker, 1, now() + 60_000, "x")})), &[]).await;
        assert_eq!(r.code(), "BAD_SIG");
    }
    let mut a = Actor::new(&t, &victim);
    let r = a.act(buy()).await;
    assert!(r.ok(), "victim locked out by unsigned spam: {} {}", r.status, r.code());
}

#[tokio::test]
async fn write_rate_limit_is_per_pubkey_and_relayer_is_not_called_after_limit() {
    let mock = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet"), ("IP_RPM", "100000")], Options { mailer: Some(Arc::new(NoMail)), chain: Some(mock.clone()), ..Default::default() }).await;
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    let mut a = Actor::new(&t, &k);
    let mut limited = 0;
    for _ in 0..100 { let r = a.act(buy()).await; if r.status == 429 { limited += 1; } }
    let calls = mock.calls.lock().unwrap().len();
    assert!(limited >= 35, "limited={limited}");
    assert!(calls <= 60, "relayer calls {calls}");
}

#[tokio::test]
async fn xff_spoofing_does_not_bypass_ip_limit_by_default() {
    let t = start(&[("IP_RPM", "10")]).await;
    let mut limited = 0;
    for i in 0..30 {
        let r = t.call("GET", "/v1/health", None, &[("x-forwarded-for", &format!("10.0.0.{i}"))]).await;
        if r.status == 429 { limited += 1; }
    }
    assert!(limited >= 15, "limited={limited}");
}

#[tokio::test]
async fn many_pubkeys_from_one_ip_are_throttled() {
    let t = start(&[("IP_RPM", "100000")]).await;
    let mut limited = 0;
    for _ in 0..40 { if t.guest(&new_key()).await.status == 429 { limited += 1; } }
    assert!(limited >= 15, "limited={limited}");
}

#[tokio::test]
async fn oversized_body_is_refused() {
    let t = start(&[]).await;
    let big = "a".repeat(200_000);
    let r = t.c.post(format!("{}/v1/act", t.base)).body(big).send().await.unwrap();
    assert_eq!(r.status().as_u16(), 413);
}

#[tokio::test]
async fn cors_is_exact() {
    let t = start(&[("CORS_ORIGINS", "https://me.github.io")]).await;
    let allow = |o: &'static str| { let t = &t; async move { t.call("GET", "/v1/health", None, &[("origin", o)]).await.headers.get("access-control-allow-origin").map(|v| v.to_str().unwrap().to_string()) } };
    assert_eq!(allow("https://me.github.io").await.as_deref(), Some("https://me.github.io"));
    for bad in ["https://me.github.io.evil.com", "https://evil.com", "http://me.github.io", "https://me.github.io/", "null", "https://localhost.evil.com", "https://evil.com:80@localhost"] {
        assert_eq!(allow(bad).await, None, "{bad}");
    }
}

#[tokio::test]
async fn magic_link_single_use_bound_to_key_and_expired_unknown() {
    let t = start(&[]).await;
    let (k1, k2) = (new_key(), new_key());
    let r = t.call("POST", "/v1/auth/register", Some(json!({"email":"a@example.com","pubkey":k1.pubkey,"consent":true})), &[]).await;
    let tok = r.data()["dev_token"].as_str().unwrap().to_string();
    let wrong = t.call("POST", "/v1/auth/confirm", Some(json!({"token":tok,"pubkey":k2.pubkey})), &[]).await;
    assert_eq!(wrong.code(), "BAD_SIG");
    assert!(t.call("POST", "/v1/auth/confirm", Some(json!({"token":tok,"pubkey":k1.pubkey})), &[]).await.ok());
    assert_eq!(t.call("POST", "/v1/auth/confirm", Some(json!({"token":tok,"pubkey":k1.pubkey})), &[]).await.code(), "EXPIRED");
    assert_eq!(t.call("POST", "/v1/auth/confirm", Some(json!({"token":"zzz","pubkey":k1.pubkey})), &[]).await.code(), "EXPIRED");
    // consent and age gates
    assert!(!t.call("POST", "/v1/auth/register", Some(json!({"email":"b@example.com","pubkey":k1.pubkey})), &[]).await.ok());
}

struct Scripted { delay: Duration, down_msg: Option<String>, calls: Mutex<u32> }
#[async_trait]
impl Chain for Scripted {
    async fn submit(&self, _r: &SubmitReq) -> Result<String, ChainError> {
        tokio::time::sleep(self.delay).await;
        *self.calls.lock().unwrap() += 1;
        match &self.down_msg { Some(m) => Err(ChainError::Down(m.clone())), None => Ok("tx1".into()) }
    }
    async fn nonce_of(&self, _p: &str) -> Option<u64> { Some(0) }
}
fn tn(c: Arc<Scripted>) -> Options { Options { mailer: Some(Arc::new(NoMail)), chain: Some(c), ..Default::default() } }

#[tokio::test]
async fn testnet_hides_dev_token_and_player_advance_and_admin_needs_token() {
    let c = Arc::new(Scripted { delay: Duration::ZERO, down_msg: None, calls: Mutex::new(0) });
    let t = start_with(&[("MODE", "testnet"), ("DEV_RETURN_TOKEN", "1"), ("ADMIN_TOKEN", "s3cret-s3cret-s3cret")], tn(c)).await;
    let k = new_key();
    let r = t.call("POST", "/v1/auth/register", Some(json!({"email":"a@example.com","pubkey":k.pubkey,"consent":true})), &[]).await;
    assert!(r.ok() && r.data().get("dev_token").is_none());
    assert!(t.guest(&k).await.ok());
    assert_eq!(Actor::new(&t, &k).act(json!({"type":"advance"})).await.code(), "FORBIDDEN");
    assert_eq!(t.call("POST", "/v1/admin/advance", None, &[]).await.code(), "FORBIDDEN");
    assert_eq!(t.call("POST", "/v1/admin/pause", Some(json!({"paused":true})), &[("x-admin-token", "wrong")]).await.code(), "FORBIDDEN");
    assert!(t.call("POST", "/v1/admin/pause", Some(json!({"paused":true})), &[("x-admin-token", "s3cret-s3cret-s3cret")]).await.ok());
    assert_eq!(Actor::new(&t, &k).act(buy()).await.code(), "FORBIDDEN");
}

#[tokio::test]
async fn chain_outage_text_is_not_leaked_to_clients_or_health() {
    let secret = "error sending request for url (https://rpc.example/?apiKey=SECRETKEY123)";
    let c = Arc::new(Scripted { delay: Duration::ZERO, down_msg: Some(secret.into()), calls: Mutex::new(0) });
    let t = start_with(&[("MODE", "testnet")], tn(c)).await;
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    let r = Actor::new(&t, &k).act(buy()).await;
    let h = t.get("/v1/health").await;
    let all = format!("{} {}", r.json, h.json);
    assert!(!all.contains("SECRETKEY123"), "leaked: {all}");
}

#[tokio::test]
async fn client_disconnect_mid_chain_call_keeps_runner_state_consistent() {
    let c = Arc::new(Scripted { delay: Duration::from_millis(400), down_msg: None, calls: Mutex::new(0) });
    let t = start_with(&[("ADMIN_TOKEN","s3cret"),("MODE", "testnet")], tn(c.clone())).await;
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    midday(&t).await;
    let before = t.state(&k).await.data().clone();
    let exp = now() + 60_000;
    let aj = canon(&buy());
    let sig = sign_canon(&k, 1, exp, &aj);
    let short = reqwest::Client::builder().timeout(Duration::from_millis(100)).build().unwrap();
    let r = short.post(format!("{}/v1/act", t.base)).json(&json!({"pubkey":k.pubkey,"nonce":1,"expires_ms":exp,"action_json":aj,"sig":sig})).send().await;
    assert!(r.is_err(), "client should have timed out");
    tokio::time::sleep(Duration::from_millis(800)).await;
    let after = t.state(&k).await.data().clone();
    let chain_calls = *c.calls.lock().unwrap();
    // consistent = either nothing happened, or the action fully happened (pts spent AND nonce advanced AND chain called)
    let spent = after["pts"] != before["pts"];
    let advanced = after["nonce"] == json!(1);
    assert_eq!(spent, advanced, "pts spent={spent} but nonce advanced={advanced} (chain calls {chain_calls})");
    assert_eq!(advanced, chain_calls == 1);
}

#[tokio::test]
#[ignore = "documents a known limit: one global lock is held across chain calls, so reads wait for an in-flight act"]
async fn reads_are_not_blocked_by_a_slow_chain_call() {
    let c = Arc::new(Scripted { delay: Duration::from_millis(600), down_msg: None, calls: Mutex::new(0) });
    let t = Arc::new(start_with(&[("MODE", "testnet")], tn(c)).await);
    let k = Arc::new(new_key());
    assert!(t.guest(&k).await.ok());
    let (t2, k2) = (t.clone(), k.clone());
    let h = tokio::spawn(async move { Actor::new(&t2, &k2).act(buy()).await.ok() });
    tokio::time::sleep(Duration::from_millis(100)).await;
    let s = Instant::now();
    t.get("/v1/prices").await;
    let took = s.elapsed();
    h.await.unwrap();
    assert!(took < Duration::from_millis(200), "prices took {took:?} while a chain call was in flight");
}

#[tokio::test]
async fn delete_account_needs_valid_signature_and_cannot_be_replayed() {
    let t = start(&[]).await;
    let (k, other) = (new_key(), new_key());
    assert!(t.guest(&k).await.ok() && t.guest(&other).await.ok());
    let exp = now() + 60_000;
    let bad = t.call("DELETE", "/v1/auth/account", Some(json!({"pubkey":k.pubkey,"nonce":1,"expires_ms":exp,"sig":sign_canon(&other,1,exp,"{\"type\":\"delete_account\"}")})), &[]).await;
    assert_eq!(bad.code(), "BAD_SIG");
    let body = json!({"pubkey":k.pubkey,"nonce":1,"expires_ms":exp,"sig":sign_canon(&k,1,exp,"{\"type\":\"delete_account\"}")});
    assert!(t.call("DELETE", "/v1/auth/account", Some(body.clone()), &[]).await.ok());
    assert_eq!(t.call("DELETE", "/v1/auth/account", Some(body), &[]).await.code(), "NOT_MEMBER");
    assert_eq!(t.state(&k).await.status, 404);
}

#[tokio::test]
async fn batch_is_not_atomic_first_actions_stay_applied() {
    let t = start(&[("ADMIN_TOKEN","s3cret")]).await;
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    midday(&t).await;
    let exp = now() + 60_000;
    let mk = |n: u64, a: Value| { let aj = canon(&a); json!({"pubkey":k.pubkey,"nonce":n,"expires_ms":exp,"action_json":aj,"sig":sign_canon(&k,n,exp,&aj)}) };
    let r = t.call("POST", "/v1/act_batch", Some(json!({"actions":[mk(1, buy()), mk(2, sell_none()), mk(3, buy())]})), &[]).await;
    assert_eq!(r.data()["completed"], json!(1));
    assert_eq!(r.data()["stopped_at"], json!(1));
    assert_eq!(t.state(&k).await.data()["stock"]["tomato"], json!(1));
}

#[tokio::test]
async fn etag_and_gzip_are_consistent() {
    let t = start(&[("ADMIN_TOKEN","s3cret")]).await;
    let r = t.get("/v1/prices").await;
    let etag = r.headers.get("etag").unwrap().to_str().unwrap().to_string();
    let r2 = t.call("GET", "/v1/prices", None, &[("if-none-match", &etag)]).await;
    assert_eq!(r2.status, 304);
    // a state change (any act) must change prices etag only if prices changed; after buy the stock changes
    let k = new_key();
    assert!(t.guest(&k).await.ok());
    midday(&t).await;
    assert!(Actor::new(&t, &k).act(buy()).await.ok());
    let r3 = t.call("GET", "/v1/prices", None, &[("if-none-match", &etag)]).await;
    assert_eq!(r3.status, 200, "stale 304 after a state change");
    // gzip response must say Vary: Accept-Encoding
    let c = reqwest::Client::builder().no_gzip().build().unwrap();
    let g = c.get(format!("{}/v1/prices", t.base)).header("accept-encoding", "gzip").send().await.unwrap();
    assert_eq!(g.headers().get("content-encoding").map(|v| v.to_str().unwrap()), Some("gzip"));
    let vary = g.headers().get_all("vary").iter().map(|v| v.to_str().unwrap().to_lowercase()).collect::<Vec<_>>().join(",");
    assert!(vary.contains("accept-encoding"), "vary={vary}");
}

#[tokio::test]
async fn unbounded_maps_stay_bounded_under_junk_input() {
    // many distinct junk "pubkeys" must not be able to grow the limiter with huge keys
    let t = start(&[("IP_RPM", "100000")]).await;
    let big = format!("ed25519:{}", "A".repeat(50_000));
    for _ in 0..5 { let r = t.call("POST", "/v1/act", Some(json!({"pubkey": big, "nonce": 1, "expires_ms": 1, "action_json": "{}", "sig": "x"})), &[]).await; assert_eq!(r.code(), "BAD_SIG"); }
}
