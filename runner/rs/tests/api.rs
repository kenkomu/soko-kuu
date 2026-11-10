#![allow(clippy::len_zero, clippy::needless_range_loop)]
mod common;
use common::*;
use serde_json::json;
use sokokuu_runner::app::Options;
use std::sync::Arc;

fn adv() -> serde_json::Value { json!({"type": "advance"}) }
fn buy(m: &str, g: &str, q: u32, max: u64) -> serde_json::Value { json!({"type":"buy","merchant":m,"good":g,"qty":q,"max_unit_price":max}) }

#[test]
fn action_json_is_signed_as_sent_and_parses_into_econ_action() {
    let s = r#"{"type":"buy","merchant":"njeri","good":"tomato","qty":3,"max_unit_price":3900}"#;
    let a: econ::Action = serde_json::from_str(s).unwrap();
    assert!(matches!(a, econ::Action::Buy { qty: 3, max_unit_price: 3900, .. }));
    assert_eq!(canon(&adv()), r#"{"type":"advance"}"#);
}

#[test]
fn ed25519_verify_roundtrip() {
    let k = new_key();
    let s = sign_canon(&k, 1, 5, r#"{"type":"advance"}"#);
    let msg = sokokuu_runner::sig::signed_message("testnet", "sokokuu.testnet", &k.pubkey, 1, 5, r#"{"type":"advance"}"#);
    assert!(sokokuu_runner::sig::verify(&k.pubkey, &msg, &s));
    assert!(!sokokuu_runner::sig::verify(&k.pubkey, "tampered", &s));
    assert!(!sokokuu_runner::sig::verify(&k.pubkey, &msg, "AAAA"));
}

#[tokio::test]
async fn health_reads_consent_login_act_flow() {
    let t = start(&[]).await; let k = new_key();
    let h = t.get("/v1/health").await; assert_eq!(h.data()["mode"], "demo"); assert_eq!(h.data()["contract_id"], "sokokuu.testnet");
    let no = t.call("POST", "/v1/auth/register", Some(json!({"email": "a@example.com", "pubkey": k.pubkey})), &[]).await;
    assert!(!no.ok());
    assert_eq!(t.state(&k).await.status, 404);
    let mut a = Actor::new(&t, &k);
    assert_eq!(a.act(adv()).await.code(), "NOT_MEMBER");
    let id = t.login(&k, "a@example.com").await; assert!(id.starts_with('p') && id.len() == 9);
    assert!(a.act(adv()).await.ok()); // dawn -> midday
    let pr = t.get("/v1/prices").await;
    let item = pr.data()["items"].as_array().unwrap().iter().find(|i| i["merchant"] == "njeri" && i["good"] == "tomato").unwrap().clone();
    assert!(item["why"].as_array().unwrap().len() > 0);
    let ask = item["ask"].as_u64().unwrap();
    let r = a.act(buy("njeri", "tomato", 3, ask)).await;
    assert!(r.ok(), "{}", r.json);
    assert!(r.data()["tx_hash"].as_str().unwrap().starts_with("demo:"));
    assert_eq!(r.data()["state_delta"]["stock_change"]["tomato"], 3);
    let st = t.state(&k).await; let d = st.data();
    assert_eq!(d["stock"]["tomato"], 3); assert_eq!(d["pts"].as_u64().unwrap(), 20000 - 3 * ask);
    assert_eq!(d["nonce"], 2); assert_eq!(d["phase"], "midday");
    let day = d["day"].as_u64().unwrap();
    let led = t.get(&format!("/v1/ledger?pubkey={}&day={day}", k.pubkey)).await;
    assert!(led.data()["entries"].as_array().unwrap().iter().any(|e| e["kind"] == "buy"));
    assert!(t.get("/v1/news").await.ok());
    assert!(t.get(&format!("/v1/report?pubkey={}", k.pubkey)).await.data()["score"]["net_worth"].as_i64().unwrap() > 0);
    assert!(t.get("/v1/leaderboard").await.ok());
}

#[tokio::test]
async fn signature_nonce_expiry_stock_phase_errors() {
    let t = start(&[("ADVANCE_COOLDOWN_MS", "5000")]).await; let k = new_key(); t.login(&k, "a@example.com").await;
    let mut a = Actor::new(&t, &k);
    assert_eq!(a.send(adv(), 1, now() + 5000, "AAAA".into()).await.code(), "BAD_SIG");
    let other = new_key(); let exp = now() + 5000;
    assert_eq!(a.send(adv(), 1, exp, sign_canon(&other, 1, exp, &canon(&adv()))).await.code(), "BAD_SIG");
    let e = now() + 60000;
    assert_eq!(a.send(adv(), 0, e, sign_canon(&k, 0, e, &canon(&adv()))).await.code(), "BAD_NONCE"); // not greater than the last accepted nonce
    let past = now() - 1;
    assert_eq!(a.send(adv(), 1, past, sign_canon(&k, 1, past, &canon(&adv()))).await.code(), "EXPIRED");
    // dawn: market closed
    assert_eq!(a.act(buy("njeri", "tomato", 1, 99999)).await.code(), "WRONG_PHASE");
    assert!(a.act(adv()).await.ok());
    assert_eq!(a.act(adv()).await.code(), "RATE_LIMITED"); // cooldown, nonce not consumed
    assert_eq!(a.act(buy("njeri", "tomato", 21, 99999)).await.code(), "NOT_ENOUGH_STOCK");
    assert_eq!(a.act(buy("njeri", "tomato", 20, 99999)).await.code(), "NOT_ENOUGH_PTS");
    assert_eq!(a.act(buy("njeri", "tomato", 1, 1)).await.code(), "PRICE_MOVED");
    assert_eq!(a.act(json!({"type":"credit_request","merchant":"njeri","good":"fish","qty":20})).await.code(), "CREDIT_DENIED");
    assert_eq!(a.act(json!({"type":"chama_vote","offer_id":1,"vote":"yes"})).await.code(), "NOT_MEMBER");
    assert_eq!(a.nonce, 1, "failed acts do not consume the nonce");
    assert!(!t.call("POST", "/v1/act", Some(json!({"pubkey": k.pubkey, "action": {"type": "withdraw"}})), &[]).await.ok());
    // a tampered action no longer matches the signature
    let n = a.nonce + 1; let e = now() + 60000;
    let sig = sign_canon(&k, n, e, &canon(&buy("njeri", "tomato", 1, 9000)));
    assert_eq!(a.send(buy("njeri", "tomato", 5, 9000), n, e, sig).await.code(), "BAD_SIG");
}

#[tokio::test]
async fn full_day_loans_chama_vote_and_account_deletion() {
    let t = start(&[]).await;
    let ks: Vec<Key> = (0..4).map(|_| new_key()).collect();
    for (i, k) in ks.iter().enumerate() { t.login(k, &format!("u{i}@example.com")).await; }
    let mut a: Vec<Actor> = ks.iter().map(|k| Actor::new(&t, k)).collect();
    assert!(a[0].act(json!({"type":"chama_create"})).await.ok());
    for i in 1..4 { assert!(a[i].act(json!({"type":"chama_join","chama_id":"c1"})).await.ok()); }
    assert!(a[0].act(adv()).await.ok()); // midday
    let l1 = a[0].act(json!({"type":"credit_request","merchant":"njeri","good":"fish","qty":1})).await;
    assert!(l1.ok(), "{}", l1.json);
    // second request is over the tier limit: the chama (4 members, enough cash) opens an offer
    let r = a[0].act(json!({"type":"credit_request","merchant":"njeri","good":"sukuma","qty":6})).await;
    assert!(r.ok(), "{}", r.json);
    let ch = t.get("/v1/chama/c1").await; assert_eq!(ch.data()["members"].as_array().unwrap().len(), 4);
    let oid = ch.data()["offer"]["id"].as_u64().expect("open offer");
    assert_eq!(a[0].act(json!({"type":"chama_vote","offer_id":oid,"vote":"yes"})).await.code(), "WRONG_PHASE"); // borrower cannot vote
    assert!(a[1].act(json!({"type":"chama_vote","offer_id":oid,"vote":"yes"})).await.ok());
    assert_eq!(a[1].act(json!({"type":"chama_vote","offer_id":oid,"vote":"no"})).await.code(), "ALREADY_VOTED");
    assert!(a[2].act(json!({"type":"chama_vote","offer_id":oid,"vote":"yes"})).await.ok());
    let st = t.state(&ks[0]).await; let loans = st.data()["loans"].as_array().unwrap().clone();
    assert_eq!(loans.len(), 2, "merchant loan + chama-approved loan");
    let ml = loans.iter().find(|l| l["lender"] == "merchant").unwrap();
    assert_eq!(ml["interest_pct"], 6); assert_eq!(ml["due_day"], 5); assert_eq!(ml["lender_id"], "njeri");
    assert!(ml["principal"].as_u64().unwrap() < ml["owed"].as_u64().unwrap());
    assert_eq!(loans.iter().find(|l| l["lender"] == "chama").unwrap()["interest_pct"], 4);
    // guarantee needs reputation
    let lid = loans[0]["id"].as_u64().unwrap();
    let bid = st.data()["player_id"].as_str().unwrap().to_string();
    assert_eq!(a[1].act(json!({"type":"guarantee","borrower":bid,"loan_id":lid})).await.code(), "CREDIT_DENIED");
    for l in &loans { assert!(a[0].act(json!({"type":"credit_repay","loan_id":l["id"]})).await.ok()); }
    assert_eq!(t.state(&ks[0]).await.data()["loans"].as_array().unwrap().len(), 0);
    // dusk closes the market
    assert!(a[1].act(adv()).await.ok());
    assert_eq!(a[0].act(buy("njeri", "tomato", 1, 99999)).await.code(), "WRONG_PHASE");
    assert!(a[2].act(adv()).await.ok()); // next dawn: daily settlement
    let day = t.state(&ks[0]).await.data()["day"].as_u64().unwrap(); assert_eq!(day, 1);
    // signed account deletion: wrong nonce first
    let exp = now() + 60000; let dj = r#"{"type":"delete_account"}"#;
    let body = |n: u64| json!({"pubkey": ks[3].pubkey, "nonce": n, "expires_ms": exp, "sig": sign_canon(&ks[3], n, exp, dj)});
    assert_eq!(t.call("DELETE", "/v1/auth/account", Some(body(0)), &[]).await.code(), "BAD_NONCE");
    let n = t.state(&ks[3]).await.data()["nonce"].as_u64().unwrap() + 1;
    assert!(t.call("DELETE", "/v1/auth/account", Some(body(n)), &[]).await.ok());
    assert_eq!(t.state(&ks[3]).await.status, 404);
    // the chama and the world keep working after a member leaves
    assert!(a[0].act(adv()).await.ok());
}

#[tokio::test]
async fn cors_allows_localhost_and_pages_origin_only() {
    let t = start(&[("CORS_ORIGINS", "https://kuu.github.io")]).await;
    for o in ["https://kuu.github.io", "http://localhost:5173"] {
        let r = t.call("OPTIONS", "/v1/act", None, &[("origin", o), ("access-control-request-method", "POST"), ("access-control-request-headers", "content-type")]).await;
        assert_eq!(r.headers.get("access-control-allow-origin").unwrap(), o, "preflight {o}");
        let g = t.call("GET", "/v1/health", None, &[("origin", o)]).await;
        assert_eq!(g.headers.get("access-control-allow-origin").unwrap(), o);
    }
    let bad = t.call("GET", "/v1/health", None, &[("origin", "https://evil.example")]).await;
    assert!(bad.headers.get("access-control-allow-origin").is_none());
    let pf = t.call("OPTIONS", "/v1/act", None, &[("origin", "https://evil.example"), ("access-control-request-method", "POST")]).await;
    assert!(pf.headers.get("access-control-allow-origin").is_none());
}

#[tokio::test]
async fn no_cash_out_transfer_or_buy_points_endpoints() {
    let t = start(&[]).await;
    for p in ["withdraw", "cashout", "transfer", "buy-points", "purchase", "token"] {
        assert_eq!(t.call("GET", &format!("/v1/{p}"), None, &[]).await.status, 404);
        assert_eq!(t.call("POST", &format!("/v1/{p}"), Some(json!({})), &[]).await.status, 404);
    }
}

#[tokio::test]
async fn testnet_mode_falls_back_to_demo_without_relayer_config() {
    let t = start(&[("MODE", "testnet")]).await;
    let h = t.get("/v1/health").await;
    assert_eq!(h.data()["mode"], "demo");
    assert!(h.data()["degraded"].as_str().unwrap().contains("testnet unavailable"));
}

fn mock_opts(c: Arc<MockChain>) -> Options { Options { mailer: Some(Arc::new(NoMail)), chain: Some(c), ..Default::default() } }

#[tokio::test]
async fn testnet_mode_submits_to_chain_and_falls_back_on_outage() {
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet")], mock_opts(chain.clone())).await;
    let k = new_key(); t.app.test_bind(&k.pubkey).await;
    let mut a = Actor::new(&t, &k);
    assert_eq!(a.act(json!({"type":"chama_create"})).await.data()["tx_hash"], "abc");
    assert_eq!(chain.calls.lock().unwrap()[0], (r#"{"type":"chama_create"}"#.to_string(), 1), "action_json forwarded as signed");
    let k2 = new_key(); t.app.test_bind(&k2.pubkey).await;
    *chain.behave.lock().unwrap() = "down";
    let r = Actor::new(&t, &k2).act(json!({"type":"chama_create"})).await;
    assert!(r.data()["tx_hash"].as_str().unwrap().starts_with("demo:"));
    assert_eq!(t.get("/v1/health").await.data()["mode"], "demo");
}

#[test]
fn chain_error_mapping() {
    use sokokuu_runner::chain::{parse_chain_error, ChainError};
    let Some(ChainError::Reject { code, .. }) = parse_chain_error("Smart contract panicked: BAD_NONCE: expected 3") else { panic!() };
    assert_eq!(code, "BAD_NONCE");
    let Some(ChainError::Reject { code, .. }) = parse_chain_error("NON_TRANSFERABLE: no") else { panic!() };
    assert_eq!(code, "INTERNAL");
    assert!(parse_chain_error("connection refused").is_none());
    assert!(parse_chain_error("XBAD_SIGX").is_none());
}

#[tokio::test]
async fn rollback_on_contract_reject_and_nonce_sync_from_chain() {
    let chain = MockChain::new(41);
    *chain.behave.lock().unwrap() = "reject";
    let t = start_with(&[("MODE", "testnet"), ("ADMIN_TOKEN", "s3cret")], mock_opts(chain.clone())).await;
    let k = new_key();
    let tok = t.app.test_register("z@example.com", &k.pubkey).await.unwrap();
    assert!(t.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": k.pubkey})), &[]).await.ok());
    assert_eq!(t.state(&k).await.data()["nonce"], 41);
    let mut a = Actor::new(&t, &k); a.nonce = 41;
    let before = t.state(&k).await.data().clone();
    assert_eq!(a.act(json!({"type":"chama_create"})).await.code(), "BAD_NONCE");
    assert_eq!(*t.state(&k).await.data(), before, "engine rolled back: no chama, same pts, same nonce");
    *chain.behave.lock().unwrap() = "ok";
    assert!(a.act(json!({"type":"chama_create"})).await.ok());
    // the relayer moves the clock; a buy rejected by the contract leaves pts and stock untouched
    assert!(t.call("POST", "/v1/admin/advance", None, &[("x-admin-token", "s3cret")]).await.ok());
    assert_eq!(t.state(&k).await.data()["phase"], "midday");
    *chain.behave.lock().unwrap() = "reject";
    let mid = t.state(&k).await.data().clone();
    assert_eq!(a.act(buy("njeri", "tomato", 2, 99999)).await.code(), "BAD_NONCE");
    assert_eq!(*t.state(&k).await.data(), mid);
}

#[tokio::test]
async fn delete_account_is_forwarded_so_nonces_stay_aligned() {
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet"), ("EMAILS_PER_HOUR", "20")], mock_opts(chain.clone())).await;
    let (k1, k2) = (new_key(), new_key()); t.app.test_bind(&k1.pubkey).await; t.app.test_bind(&k2.pubkey).await;
    let dj = r#"{"type":"delete_account"}"#; let exp = now() + 60000;
    let del = |k: &Key, n: u64| json!({"pubkey": k.pubkey, "nonce": n, "expires_ms": exp, "sig": sign_canon(k, n, exp, dj)});
    // contract refuses: the account stays and the nonce is not consumed
    *chain.behave.lock().unwrap() = "reject";
    assert_eq!(t.call("DELETE", "/v1/auth/account", Some(del(&k1, 1)), &[]).await.code(), "BAD_NONCE");
    assert_eq!(t.state(&k1).await.data()["nonce"], 0);
    *chain.behave.lock().unwrap() = "ok";
    let mut a = Actor::new(&t, &k1);
    assert!(a.act(json!({"type":"chama_create"})).await.ok()); // nonce 1 consumed by a normal act
    assert!(t.call("DELETE", "/v1/auth/account", Some(del(&k1, 2)), &[]).await.ok());
    let calls = chain.calls.lock().unwrap().clone();
    assert_eq!(calls.last().unwrap(), &(dj.to_string(), 2), "delete_account forwarded with its nonce");
    assert_eq!(t.state(&k1).await.status, 404);
    // the other account is unaffected
    assert!(Actor::new(&t, &k2).act(json!({"type":"chama_create"})).await.ok());
}

#[tokio::test]
async fn sim_is_deterministic_and_responds_to_events() {
    let t = start(&[]).await;
    let run = |body: serde_json::Value| { let t = &t; async move { t.call("POST", "/v1/sim", Some(body), &[]).await } };
    let a = run(json!({"seed": 5, "days": 10})).await; let b = run(json!({"seed": 5, "days": 10})).await;
    assert!(a.ok()); assert_eq!(a.json, b.json); assert_eq!(a.data()["frames"].as_array().unwrap().len(), 10);
    let c = run(json!({"seed": 5, "days": 10, "events": [{"day": 3, "kind": "ukame", "magnitude": 90}, {"day": 1, "kind": "bogus", "magnitude": 1}]})).await;
    assert_ne!(a.data()["frames"], c.data()["frames"]);
    assert_eq!(a.data()["frames"][0], c.data()["frames"][0]);
    assert_eq!(run(json!({"seed": 3, "days": 9999})).await.data()["frames"].as_array().unwrap().len(), 120);
}

#[test]
fn money_stays_stable_over_100_seeds() {
    let r = econ::sim::stability(100, 30);
    println!("worst drift bp {}", r.worst_abs_drift_bp);
    assert!(r.worst_abs_drift_bp.abs() <= 1500, "{r:?}");
}

#[tokio::test]
async fn sign_in_and_act_requests_are_rate_limited() {
    let t = start(&[]).await; let k = new_key();
    let mut limited = false;
    for _ in 0..25 {
        let r = t.call("POST", "/v1/auth/register", Some(json!({"email": "r@example.com", "pubkey": k.pubkey, "consent": true})), &[]).await;
        if r.code() == "RATE_LIMITED" { assert_eq!(r.status, 429); limited = true; break; }
    }
    assert!(limited, "register must be rate-limited");
    // /v1/act is limited per pubkey (60 per minute), counted once the signature verifies
    let k2 = new_key(); assert!(t.guest(&k2).await.ok());
    let mut a = Actor::new(&t, &k2);
    let mut limited = false;
    for _ in 0..70 {
        let r = a.act(json!({"type":"sell","merchant":"njeri","good":"fish","qty":5})).await;
        if r.code() == "RATE_LIMITED" { limited = true; break; }
    }
    assert!(limited, "act must be rate-limited");
}

#[tokio::test]
async fn security_replay_far_expiry_link_binding_and_headers() {
    let t = start(&[]).await; let (k, other) = (new_key(), new_key());
    // magic link bound to the registering key; single use
    let r = t.call("POST", "/v1/auth/register", Some(json!({"email": "s@example.com", "pubkey": k.pubkey, "consent": true})), &[]).await;
    let tok = r.data()["dev_token"].as_str().unwrap().to_string();
    assert_eq!(t.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": other.pubkey})), &[]).await.code(), "BAD_SIG");
    assert!(t.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": k.pubkey})), &[]).await.ok());
    assert_eq!(t.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": k.pubkey})), &[]).await.code(), "EXPIRED");
    // replay: the same signed bytes are rejected the second time
    let a = Actor::new(&t, &k); let exp = now() + 60_000;
    let sig = sign_canon(&k, 1, exp, &canon(&adv()));
    assert!(a.send(adv(), 1, exp, sig.clone()).await.ok());
    assert_eq!(a.send(adv(), 1, exp, sig).await.code(), "BAD_NONCE");
    // expiry more than 2 minutes ahead is refused
    let far = now() + 600_000;
    assert_eq!(a.send(adv(), 2, far, sign_canon(&k, 2, far, &canon(&adv()))).await.code(), "EXPIRED");
    // signature for another contract id is refused
    let msg = sokokuu_runner::sig::signed_message("testnet", "evil.testnet", &k.pubkey, 2, exp, &canon(&adv()));
    use base64::Engine as _; use ed25519_dalek::Signer as _;
    let bad = base64::engine::general_purpose::STANDARD.encode(k.sk.sign(msg.as_bytes()).to_bytes());
    assert_eq!(a.send(adv(), 2, exp, bad).await.code(), "BAD_SIG");
    let h = t.call("GET", "/v1/health", None, &[]).await;
    assert_eq!(h.headers.get("x-content-type-options").unwrap(), "nosniff");
    assert!(h.headers.get("strict-transport-security").is_some());
}

#[tokio::test]
async fn guest_flow_age_gate_and_leaderboard_visibility() {
    let t = start(&[]).await; let k = new_key();
    let no = t.call("POST", "/v1/auth/guest", Some(json!({"pubkey": k.pubkey})), &[]).await;
    assert_eq!(no.code(), "FORBIDDEN");
    let g = t.guest(&k).await; assert!(g.ok());
    assert_eq!(t.guest(&k).await.data()["player_id"], g.data()["player_id"], "idempotent");
    let st = t.state(&k).await; assert_eq!(st.data()["pts"], 20000);
    for f in ["player_id", "nonce", "next_phase_ms", "reputation", "credit", "loans", "chama_id", "day", "phase", "stock"] { assert!(st.data().get(f).is_some(), "state.{f}"); }
    assert!(st.data()["reputation"]["tier"].is_string() && st.data()["reputation"]["score"].is_number());
    // fresh guests stay off the personal board until day 3
    let lb = t.get("/v1/leaderboard").await;
    assert_eq!(lb.data()["personal"].as_array().unwrap().len(), 0);
    let v = new_key(); t.login(&v, "v@example.com").await;
    assert_eq!(t.get("/v1/leaderboard").await.data()["personal"].as_array().unwrap().len(), 1);
    // guests can act at once and later save progress by email
    let mut a = Actor::new(&t, &k);
    assert!(a.act(json!({"type":"chama_create"})).await.ok());
    let r = t.call("POST", "/v1/auth/register", Some(json!({"email": "up@example.com", "pubkey": k.pubkey, "consent": true})), &[]).await;
    let c = t.call("POST", "/v1/auth/confirm", Some(json!({"token": r.data()["dev_token"], "pubkey": k.pubkey})), &[]).await;
    assert_eq!(c.data()["player_id"], g.data()["player_id"]);
    assert_eq!(t.get("/v1/leaderboard").await.data()["personal"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn one_account_per_email_and_new_device_revokes_old_key_at_once() {
    let t = start(&[]).await; let (k1, k2, other) = (new_key(), new_key(), new_key());
    let id1 = t.login(&k1, "same@example.com").await;
    let mut a1 = Actor::new(&t, &k1);
    assert!(a1.act(json!({"type":"chama_create"})).await.ok());
    // same email on a new key: same player, valid at once
    let id2 = t.login(&k2, "same@example.com").await; assert_eq!(id1, id2);
    assert_eq!(t.state(&k2).await.data()["chama_id"], t.state(&k1).await.data()["chama_id"]);
    assert_eq!(a1.act(adv()).await.code(), "NOT_MEMBER", "the old key is revoked as soon as the new device confirms");
    assert!(Actor::new(&t, &k2).act(json!({"type":"haggle","merchant":"njeri","good":"tomato"})).await.code() != "NOT_MEMBER");
    // a guest that already has its own player cannot claim an email that belongs to someone else
    t.guest(&other).await;
    let r = t.call("POST", "/v1/auth/register", Some(json!({"email": "same@example.com", "pubkey": other.pubkey, "consent": true})), &[]).await;
    let c = t.call("POST", "/v1/auth/confirm", Some(json!({"token": r.data()["dev_token"], "pubkey": other.pubkey})), &[]).await;
    assert!(!c.ok());
}

#[tokio::test]
async fn emails_are_limited_to_three_per_hour_with_retry_after() {
    let t = start(&[]).await; let k = new_key();
    for _ in 0..3 { assert!(t.call("POST", "/v1/auth/register", Some(json!({"email": "m@example.com", "pubkey": k.pubkey, "consent": true})), &[]).await.ok()); }
    let r = t.call("POST", "/v1/auth/register", Some(json!({"email": "M@example.com", "pubkey": k.pubkey, "consent": true})), &[]).await;
    assert_eq!(r.code(), "RATE_LIMITED"); assert_eq!(r.status, 429);
    assert!(r.json["error"]["retry_after_s"].as_u64().unwrap() > 0);
    assert!(r.headers.get("retry-after").is_some());
}

#[tokio::test]
async fn act_batch_runs_in_order_and_stops_at_first_failure() {
    let t = start(&[]).await; let k = new_key(); t.login(&k, "b@example.com").await;
    let item = |n: u64, a: serde_json::Value| { let exp = now() + 60_000; json!({"pubkey": k.pubkey, "nonce": n, "expires_ms": exp, "action_json": canon(&a), "sig": sign_canon(&k, n, exp, &canon(&a))}) };
    let r = t.call("POST", "/v1/act_batch", Some(json!({"actions": [
        item(1, adv()), item(2, buy("njeri", "tomato", 1, 99999)), item(3, buy("njeri", "tomato", 21, 99999)), item(4, buy("njeri", "tomato", 1, 99999))]})), &[]).await;
    assert!(r.ok(), "{}", r.json);
    let d = r.data();
    assert_eq!(d["completed"], 2); assert_eq!(d["stopped_at"], 2); assert_eq!(d["results"].as_array().unwrap().len(), 3);
    assert_eq!(d["results"][2]["error"]["code"], "NOT_ENOUGH_STOCK");
    assert_eq!(d["state"]["nonce"], 2); assert_eq!(d["state"]["stock"]["tomato"], 1);
    assert_eq!(t.state(&k).await.data()["nonce"], 2, "failed action did not consume its nonce");
    let many: Vec<_> = (0..11).map(|i| item(10 + i, adv())).collect();
    assert_eq!(t.call("POST", "/v1/act_batch", Some(json!({"actions": many})), &[]).await.code(), "INTERNAL");
}

#[tokio::test]
async fn act_response_has_full_state_tx_hash_and_events() {
    let t = start(&[]).await; let k = new_key(); t.login(&k, "r@example.com").await;
    let mut a = Actor::new(&t, &k);
    let r = a.act(adv()).await; let d = r.data();
    assert!(d["tx_hash"].is_string() && d["events"].is_array());
    assert_eq!(d["state"]["phase"], "midday"); assert_eq!(d["state"]["nonce"], 1); assert_eq!(d["state"]["player_id"], t.state(&k).await.data()["player_id"]);
}

#[tokio::test]
async fn events_long_poll_wakes_on_change() {
    let t = start(&[("EVENTS_WAIT_MS", "5000")]).await; let k = new_key(); t.login(&k, "e@example.com").await;
    let last = t.get("/v1/events?since=0").await.data()["last_id"].as_u64().unwrap();
    let mut a = Actor::new(&t, &k);
    let url = format!("/v1/events?since={last}");
    let (poll, _) = tokio::join!(t.get(&url), async { tokio::time::sleep(std::time::Duration::from_millis(300)).await; a.act(adv()).await });
    let ev = poll.data()["events"].as_array().unwrap().clone();
    assert!(ev.iter().any(|e| e["kind"] == "phase" && e["data"]["phase"] == "midday"), "{ev:?}");
    assert!(poll.data()["last_id"].as_u64().unwrap() > last);
}

#[tokio::test]
async fn reads_have_etag_304_and_gzip() {
    let t = start(&[]).await;
    let r = t.get("/v1/prices").await; let etag = r.headers.get("etag").unwrap().to_str().unwrap().to_string();
    let again = t.call("GET", "/v1/prices", None, &[("if-none-match", &etag)]).await;
    assert_eq!(again.status, 304);
    let gz = t.c.get(format!("{}/v1/prices", t.base)).header("accept-encoding", "gzip").send().await.unwrap();
    assert_eq!(gz.headers().get("content-encoding").unwrap(), "gzip");
    let item = &r.data()["merchants"]["njeri"]["goods"]["tomato"];
    assert!(item["history"].as_array().unwrap().len() > 0 && item["why"].as_array().unwrap().len() > 0);
}

#[tokio::test]
async fn chama_discovery_and_public_info() {
    let t = start(&[]).await; let k = new_key(); t.login(&k, "c@example.com").await;
    assert_eq!(t.get("/v1/chamas").await.data()["items"].as_array().unwrap().len(), 0);
    assert!(Actor::new(&t, &k).act(json!({"type":"chama_create"})).await.ok());
    let l = t.get("/v1/chamas").await; let c = &l.data()["items"][0];
    assert_eq!(c["members"], 1); assert_eq!(c["join_share"], 2000);
    let stranger = new_key(); t.guest(&stranger).await;
    assert_eq!(t.get(&format!("/v1/chama/{}", c["id"].as_str().unwrap())).await.data()["members"].as_array().unwrap().len(), 1);
    assert_eq!(t.get("/v1/chama/nope").await.code(), "NOT_MEMBER");
}

#[tokio::test]
async fn relayer_clock_timer_admin_trigger_and_forbidden_player_advance() {
    // demo + timer: the clock moves by itself and state shows the countdown
    let t = start(&[("PHASE_SECS", "1")]).await; let k = new_key(); t.login(&k, "t@example.com").await;
    assert!(t.state(&k).await.data()["next_phase_ms"].as_u64().unwrap() > now());
    tokio::time::sleep(std::time::Duration::from_millis(2600)).await;
    let h = t.get("/v1/health").await; assert!(h.data()["phase"] != "dawn" || h.data()["day"].as_u64().unwrap() > 0, "{}", h.json);
    // testnet: player advance is FORBIDDEN and burns no nonce; admin trigger needs the secret
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet"), ("ADMIN_TOKEN", "s3cret")], mock_opts(chain.clone())).await;
    let k = new_key(); t.app.test_bind(&k.pubkey).await;
    let mut a = Actor::new(&t, &k);
    assert_eq!(a.act(adv()).await.code(), "FORBIDDEN");
    assert_eq!(t.state(&k).await.data()["nonce"], 0);
    assert_eq!(chain.calls.lock().unwrap().len(), 0, "nothing relayed");
    assert_eq!(t.call("POST", "/v1/admin/advance", None, &[]).await.code(), "FORBIDDEN");
    assert_eq!(t.call("POST", "/v1/admin/advance", None, &[("x-admin-token", "wrong")]).await.code(), "FORBIDDEN");
    let ok = t.call("POST", "/v1/admin/advance", None, &[("x-admin-token", "s3cret")]).await;
    assert!(ok.ok(), "{}", ok.json); assert_eq!(ok.data()["phase"], "midday");
    assert!(a.act(json!({"type":"chama_create"})).await.ok(), "nonce 1 still free after the forbidden advance");
}

#[tokio::test]
async fn admin_disabled_without_token_and_kill_switch_pauses_writes() {
    let t = start(&[]).await;
    assert_eq!(t.call("POST", "/v1/admin/pause", Some(json!({"paused": true})), &[("x-admin-token", "x")]).await.code(), "FORBIDDEN");
    let t = start(&[("ADMIN_TOKEN", "s3cret")]).await; let k = new_key(); t.login(&k, "p@example.com").await;
    let mut a = Actor::new(&t, &k);
    assert!(t.call("POST", "/v1/admin/pause", Some(json!({"paused": true})), &[("x-admin-token", "s3cret")]).await.ok());
    assert_eq!(a.act(adv()).await.code(), "FORBIDDEN");
    assert!(t.call("POST", "/v1/admin/pause", Some(json!({"paused": false})), &[("x-admin-token", "s3cret")]).await.ok());
    assert!(a.act(adv()).await.ok());
}

#[tokio::test]
async fn per_ip_limit_returns_retry_after() {
    let t = start(&[("IP_RPM", "10")]).await;
    let mut hit = None;
    for _ in 0..15 { let r = t.get("/v1/health").await; if r.status == 429 { hit = Some(r); break; } }
    let r = hit.expect("limited"); assert_eq!(r.code(), "RATE_LIMITED"); assert!(r.json["error"]["retry_after_s"].as_u64().is_some());
}

#[test]
fn contract_panics_map_one_to_one() {
    use sokokuu_runner::chain::{parse_chain_error, ChainError};
    for c in ["WRONG_PHASE", "PRICE_MOVED", "FORBIDDEN", "NOT_ENOUGH_STOCK", "ALREADY_VOTED", "CREDIT_DENIED", "RATE_LIMITED", "NOT_MEMBER"] {
        let Some(ChainError::Reject { code, .. }) = parse_chain_error(&format!("Smart contract panicked: {c}")) else { panic!("{c}") };
        assert_eq!(code, c);
    }
}

#[test]
fn contract_panic_exact_near_text_and_bare_trap() {
    use sokokuu_runner::chain::{parse_chain_error, ChainError};
    // contract built with RUSTFLAGS="--cfg near": `Smart contract panicked: CODE: msg`, wrapped by the RPC status Debug output
    let t = r#"Failure(ActionError(ActionError { index: Some(0), kind: FunctionCallError(ExecutionError("Smart contract panicked: WRONG_PHASE: buy needs midday")) }))"#;
    let Some(ChainError::Reject { code, .. }) = parse_chain_error(t) else { panic!() };
    assert_eq!(code, "WRONG_PHASE");
    let Some(ChainError::Reject { msg, .. }) = parse_chain_error(t) else { panic!() };
    assert_eq!(msg, "buy needs midday", "no RPC debug wrapper in the user-visible text");
    let Some(ChainError::Reject { code, .. }) = parse_chain_error("Smart contract panicked: PRICE_MOVED: ask 4100 > max 3900") else { panic!() };
    assert_eq!(code, "PRICE_MOVED");
    // built without the flag: a bare trap carries no code and must be treated as chain trouble, not a game error
    assert!(parse_chain_error(r#"FunctionCallError(ExecutionError("Smart contract panicked: explicit guest panic"))"#).is_none());
    assert!(parse_chain_error("WebAssembly trap: An `unreachable` instruction was executed.").is_none());
}

/// Not a check: dumps real responses for runner/SHAPES.md. Run with `SHAPES_OUT=/path cargo test dump_shapes -- --ignored`.
#[tokio::test]
#[ignore]
async fn dump_shapes() {
    let Ok(out) = std::env::var("SHAPES_OUT") else { return };
    let t = start(&[("PHASE_SECS", "0")]).await;
    let ks: Vec<Key> = (0..4).map(|_| new_key()).collect();
    for (i, k) in ks.iter().enumerate() { t.login(k, &format!("s{i}@example.com")).await; }
    let mut a: Vec<Actor> = ks.iter().map(|k| Actor::new(&t, k)).collect();
    let mut o = serde_json::Map::new();
    a[0].act(json!({"type":"chama_create"})).await;
    for i in 1..4 { a[i].act(json!({"type":"chama_join","chama_id":"c1"})).await; }
    let adv_r = a[0].act(adv()).await; o.insert("act_advance".into(), adv_r.json.clone());
    o.insert("act_buy".into(), a[0].act(buy("njeri", "tomato", 3, 99999)).await.json);
    o.insert("act_haggle".into(), a[0].act(json!({"type":"haggle","merchant":"njeri","good":"fish"})).await.json);
    a[0].act(json!({"type":"credit_request","merchant":"njeri","good":"fish","qty":1})).await;
    a[0].act(json!({"type":"credit_request","merchant":"njeri","good":"sukuma","qty":6})).await;
    o.insert("state".into(), t.state(&ks[0]).await.json);
    o.insert("chama".into(), t.get("/v1/chama/c1").await.json);
    o.insert("chamas".into(), t.get("/v1/chamas").await.json);
    o.insert("prices".into(), t.get("/v1/prices").await.json);
    o.insert("news".into(), t.get("/v1/news").await.json);
    o.insert("ledger".into(), t.get(&format!("/v1/ledger?pubkey={}&day=0", ks[0].pubkey)).await.json);
    o.insert("report".into(), t.get(&format!("/v1/report?pubkey={}", ks[0].pubkey)).await.json);
    o.insert("leaderboard".into(), t.get("/v1/leaderboard").await.json);
    o.insert("health".into(), t.get("/v1/health").await.json);
    o.insert("events".into(), t.get("/v1/events?since=0").await.json);
    let item = |n: u64, act: serde_json::Value| { let exp = now() + 60_000; json!({"pubkey": ks[1].pubkey, "nonce": n, "expires_ms": exp, "action_json": canon(&act), "sig": sign_canon(&ks[1], n, exp, &canon(&act))}) };
    let n1 = t.state(&ks[1]).await.data()["nonce"].as_u64().unwrap();
    o.insert("act_batch".into(), t.call("POST", "/v1/act_batch", Some(json!({"actions": [item(n1 + 1, buy("njeri", "tomato", 1, 99999)), item(n1 + 2, buy("njeri", "tomato", 21, 99999))]})), &[]).await.json);
    o.insert("sim".into(), t.call("POST", "/v1/sim", Some(json!({"seed": 1, "days": 2})), &[]).await.json);
    o.insert("error_example".into(), a[0].act(buy("njeri", "tomato", 1, 1)).await.json);
    std::fs::write(out, serde_json::to_string_pretty(&serde_json::Value::Object(o)).unwrap()).unwrap();
}

#[tokio::test]
async fn new_device_key_is_rebound_on_chain_first() {
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet"), ("EMAILS_PER_HOUR", "20")], mock_opts(chain.clone())).await;
    let (k1, k2) = (new_key(), new_key());
    let login = |k: &Key| { let t = &t; let pk = k.pubkey.clone(); async move {
        let tok = t.app.test_register("dev@example.com", &pk).await.unwrap();
        t.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": pk})), &[]).await } };
    let first = login(&k1).await; assert!(first.ok());
    assert!(chain.rebinds.lock().unwrap().is_empty(), "first key is not a rebind");
    // the contract refuses: the new key is not accepted and the old one keeps working
    *chain.behave.lock().unwrap() = "reject";
    assert_eq!(login(&k2).await.code(), "FORBIDDEN");
    assert_eq!(t.state(&k2).await.status, 404);
    *chain.behave.lock().unwrap() = "reject_not_member";
    assert_eq!(login(&k2).await.code(), "NOT_MEMBER");
    assert_eq!(t.state(&k2).await.status, 404);
    assert!(Actor::new(&t, &k1).act(json!({"type":"chama_create"})).await.ok(), "old key unaffected by refused rebinds");
    *chain.behave.lock().unwrap() = "ok";
    let second = login(&k2).await; assert!(second.ok());
    // the new key inherits the old key's nonce floor
    assert_eq!(t.state(&k2).await.data()["nonce"], 1);
    assert_eq!(second.data()["player_id"], first.data()["player_id"]);
    assert_eq!(chain.rebinds.lock().unwrap().last().unwrap(), &(k1.pubkey.clone(), k2.pubkey.clone()));
    assert_eq!(Actor::new(&t, &k1).act(json!({"type":"chama_create"})).await.code(), "NOT_MEMBER");
    assert_ne!(Actor::new(&t, &k2).act(json!({"type":"chama_create"})).await.code(), "NOT_MEMBER", "the new key is accepted");
}

#[tokio::test]
async fn daily_new_account_cap() {
    let t = start(&[("MAX_NEW_ACCOUNTS_PER_DAY", "2")]).await;
    for _ in 0..2 { assert!(t.guest(&new_key()).await.ok()); }
    let r = t.guest(&new_key()).await;
    assert_eq!(r.code(), "RATE_LIMITED"); assert!(r.json["error"]["retry_after_s"].as_u64().unwrap() > 0);
    // an existing guest is not an extra account
    let k = new_key(); let t2 = start(&[("MAX_NEW_ACCOUNTS_PER_DAY", "1")]).await;
    assert!(t2.guest(&k).await.ok()); assert!(t2.guest(&k).await.ok());
}

#[tokio::test]
async fn relayer_balance_alarm_shows_in_health() {
    let chain = MockChain::new(0);
    *chain.balance.lock().unwrap() = Some(1_000_000_000_000_000_000_000_000); // 1 NEAR
    let t = start_with(&[("MODE", "testnet"), ("MIN_BALANCE_NEAR", "5")], mock_opts(chain.clone())).await;
    let mut alarm = serde_json::Value::Null;
    for _ in 0..20 { alarm = t.get("/v1/health").await.data()["relayer_balance_alarm"].clone(); if !alarm.is_null() { break; } tokio::time::sleep(std::time::Duration::from_millis(100)).await; }
    assert!(alarm.as_str().unwrap().contains("balance low"), "{alarm}");
}

#[tokio::test]
async fn chama_flow_shapes_discovery_vote_and_error_messages() {
    let t = start(&[]).await;
    let ks: Vec<Key> = (0..4).map(|_| new_key()).collect();
    for (i, k) in ks.iter().enumerate() { t.login(k, &format!("c{i}@example.com")).await; }
    let mut a: Vec<Actor> = ks.iter().map(|k| Actor::new(&t, k)).collect();
    assert_eq!(t.get("/v1/chamas").await.data()["items"].as_array().unwrap().len(), 0);
    assert_eq!(t.get("/v1/chama/c1").await.status, 404);
    // unknown merchant / chama / not in a chama: NOT_MEMBER with a message that says which
    assert!(a[0].act(adv()).await.ok()); // midday (the phase is checked before the merchant)
    let r = a[0].act(buy("nobody", "tomato", 1, 99999)).await; assert_eq!(r.code(), "NOT_MEMBER");
    assert!(r.json["error"]["message"].as_str().unwrap().contains("unknown merchant"), "{}", r.json);
    let r = a[0].act(json!({"type":"chama_join","chama_id":"c99"})).await; assert_eq!(r.code(), "NOT_MEMBER");
    assert!(r.json["error"]["message"].as_str().unwrap().contains("unknown chama"), "{}", r.json);
    assert_eq!(a[0].act(json!({"type":"chama_vote","offer_id":1,"vote":"yes"})).await.code(), "NOT_MEMBER");
    // create + join
    let c = a[0].act(json!({"type":"chama_create"})).await; assert!(c.ok(), "{}", c.json);
    assert_eq!(c.data()["state"]["chama_id"], "c1");
    let list = t.get("/v1/chamas").await;
    let it = &list.data()["items"][0];
    assert_eq!((it["id"].as_str(), it["members"].as_u64(), it["max_members"].as_u64(), it["open_offer"].as_bool()), (Some("c1"), Some(1), Some(8), Some(false)));
    for i in 1..4 { let j = a[i].act(json!({"type":"chama_join","chama_id":"c1"})).await; assert!(j.ok(), "{}", j.json); }
    let ch = t.get("/v1/chama/c1").await;
    assert_eq!(ch.data()["members"].as_array().unwrap().len(), 4);
    assert!(ch.data()["offer"].is_null(), "{}", ch.json);
    assert_eq!(ch.data()["cash"], 8000);
    // an offer opens when a request exceeds the personal credit limit
    assert!(a[0].act(json!({"type":"credit_request","merchant":"njeri","good":"fish","qty":1})).await.ok());
    assert!(a[0].act(json!({"type":"credit_request","merchant":"njeri","good":"sukuma","qty":6})).await.ok());
    let ch = t.get("/v1/chama/c1").await;
    let o = &ch.data()["offer"];
    for f in ["id", "borrower", "merchant", "good", "qty", "cost", "owed", "deadline_day", "votes"] { assert!(o.get(f).is_some(), "offer.{f}: {}", ch.json); }
    assert!(ch.data()["deadline_day"].is_u64());
    assert_eq!(t.get("/v1/chamas").await.data()["items"][0]["open_offer"], true);
    let oid = o["id"].as_u64().unwrap();
    let v = a[1].act(json!({"type":"chama_vote","offer_id":oid,"vote":"yes"})).await; assert!(v.ok(), "{}", v.json);
    assert_eq!(t.get("/v1/chama/c1").await.data()["offer"]["votes"].as_object().unwrap().len(), 1);
    assert!(a[2].act(json!({"type":"chama_vote","offer_id":oid,"vote":"yes"})).await.ok());
    let ch = t.get("/v1/chama/c1").await;
    assert!(ch.data()["offer"].is_null(), "offer resolved: {}", ch.json);
    assert!(t.state(&ks[0]).await.data()["loans"].as_array().unwrap().iter().any(|l| l["lender"] == "chama"));
}

/// The contract's world differs from the local mirror: after a relayed act the runner must replace its world with the
/// snapshot, keep players that have not acted yet, and show `chain_drift` only while out of sync.
#[tokio::test]
async fn world_snapshot_resync_when_contract_differs() {
    use econ::world::{Config, Player, World};
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet")], mock_opts(chain.clone())).await;
    let (k1, k2) = (new_key(), new_key());
    t.app.test_bind(&k1.pubkey).await;
    t.app.test_bind(&k2.pubkey).await;
    // The contract world: another seed, one day later, and player k1 already holds 12345 pts.
    let id1: String = bs58::decode(k1.pubkey.strip_prefix("ed25519:").unwrap()).into_vec().unwrap().iter().map(|b| format!("{b:02x}")).collect();
    let mut w = World::new(Config { seed: 7, players: 0, ..Config::default() });
    w.advance().unwrap(); w.advance().unwrap(); w.advance().unwrap();
    w.players.insert(id1.clone(), Player { id: id1.clone(), pts: 12345, ..Default::default() });
    *chain.hash.lock().unwrap() = sokokuu_runner::market::world_hash_hex(&w);
    *chain.snapshot.lock().unwrap() = Some(borsh::to_vec(&w).unwrap());
    let mut a = Actor::new(&t, &k1);
    // chama_create works in any phase; the contract's answer (snapshot) decides the final state
    assert!(a.act(json!({"type":"chama_create"})).await.ok());
    assert!(*chain.snapshot_fetches.lock().unwrap() >= 1, "snapshot fetched on hash mismatch");
    let s = t.state(&k1).await;
    assert_eq!(s.data()["day"], 1, "clock comes from the contract world");
    // the unacted guest k2 is still a member with the onboarding grant
    let s2 = t.state(&k2).await;
    assert!(s2.ok(), "pending player survives a resync");
    assert_eq!(s2.data()["pts"], 20000);
    // k2 is not in the contract hash, so the comparison ignores it: after the resync health shows no drift
    let h = t.call("GET", "/v1/health", None, &[]).await;
    assert_eq!(h.data()["chain_drift"], json!(null));
}

/// Hash equal to the local world: no snapshot is fetched. Views missing: behaviour unchanged (no fetch, no drift).
#[tokio::test]
async fn no_resync_when_in_sync_or_views_missing() {
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet")], mock_opts(chain.clone())).await;
    let k = new_key(); t.app.test_bind(&k.pubkey).await;
    let base = *chain.snapshot_fetches.lock().unwrap(); // startup asks once; the answer is None
    let mut a = Actor::new(&t, &k);
    assert!(a.act(json!({"type":"chama_create"})).await.ok());
    assert_eq!(*chain.snapshot_fetches.lock().unwrap(), base, "no views: nothing fetched after the act");
    assert_eq!(t.call("GET", "/v1/health", None, &[]).await.data()["chain_drift"], json!(null));
}

/// A refusal from the contract that the local rules did not predict means the mirror is stale: heal it from the snapshot.
#[tokio::test]
async fn chain_reject_triggers_resync() {
    use econ::world::{Config, World};
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet")], mock_opts(chain.clone())).await;
    let k = new_key(); t.app.test_bind(&k.pubkey).await;
    let id: String = bs58::decode(k.pubkey.strip_prefix("ed25519:").unwrap()).into_vec().unwrap().iter().map(|b| format!("{b:02x}")).collect();
    let mut w = World::new(Config { seed: 9, players: 0, ..Config::default() });
    w.players.insert(id.clone(), econ::world::Player { id: id.clone(), pts: 777, ..Default::default() });
    *chain.hash.lock().unwrap() = sokokuu_runner::market::world_hash_hex(&w);
    *chain.snapshot.lock().unwrap() = Some(borsh::to_vec(&w).unwrap());
    *chain.behave.lock().unwrap() = "reject";
    let base = *chain.snapshot_fetches.lock().unwrap();
    assert_eq!(Actor::new(&t, &k).act(json!({"type":"chama_create"})).await.code(), "BAD_NONCE");
    assert!(*chain.snapshot_fetches.lock().unwrap() > base, "snapshot fetched after the refusal");
    assert_eq!(t.state(&k).await.data()["pts"], 777);
}

fn tmp_dir(tag: &str) -> String {
    let d = std::env::temp_dir().join(format!("sokokuu-test-{tag}-{}", rand::random::<u64>()));
    d.to_string_lossy().into_owned()
}

/// A restart keeps what the contract does not hold: the email binding (as a hash), the ledger, nonces, guests that never acted.
#[tokio::test]
async fn restart_keeps_email_binding_ledger_and_guests() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tmp_dir("keep");
    let chain = MockChain::new(0);
    let t = start_with(&[("MODE", "testnet"), ("DATA_DIR", &dir)], mock_opts(chain.clone())).await;
    let k1 = new_key();
    let tok = t.app.test_register("keep@example.com", &k1.pubkey).await.unwrap();
    let r = t.call("POST", "/v1/auth/confirm", Some(json!({"token": tok, "pubkey": k1.pubkey})), &[]).await;
    assert!(r.ok());
    let pid = r.data()["player_id"].as_str().unwrap().to_string();
    let mut a = Actor::new(&t, &k1);
    assert!(a.act(json!({"type":"chama_create"})).await.ok());
    let kg = new_key(); // a guest that never acts
    let g = t.call("POST", "/v1/auth/guest", Some(json!({"pubkey": kg.pubkey, "age_confirmed": true})), &[]).await;
    let gid = g.data()["player_id"].as_str().unwrap().to_string();
    let before = t.get(&format!("/v1/ledger?pubkey={}&day=0", k1.pubkey)).await.json;
    assert!(before["data"]["entries"].as_array().unwrap().len() >= 2);
    t.app.flush_state().await;

    let file = std::path::Path::new(&dir).join("state.json");
    assert_eq!(std::fs::metadata(&file).unwrap().permissions().mode() & 0o777, 0o600);
    let raw = std::fs::read_to_string(&file).unwrap();
    assert!(!raw.contains("keep@example.com") && !raw.contains("example.com"), "no email in clear on disk");

    // "restart": a second runner on the same data dir, fresh memory
    let t2 = start_with(&[("MODE", "testnet"), ("DATA_DIR", &dir)], mock_opts(MockChain::new(1))).await;
    let after = t2.get(&format!("/v1/ledger?pubkey={}&day=0", k1.pubkey)).await.json;
    assert_eq!(before["data"]["entries"], after["data"]["entries"], "ledger history survives");
    assert_eq!(t2.state(&k1).await.data()["nonce"], 1, "nonce survives");
    assert_eq!(t2.state(&kg).await.data()["player_id"], json!(gid), "guest that never acted survives");
    // the same email on a new key joins the same player (hashed binding survived)
    let k2 = new_key();
    let tok2 = t2.app.test_register("keep@example.com", &k2.pubkey).await.unwrap();
    let r2 = t2.call("POST", "/v1/auth/confirm", Some(json!({"token": tok2, "pubkey": k2.pubkey})), &[]).await;
    assert_eq!(r2.data()["player_id"], json!(pid), "email binding survives a restart");
}

/// A damaged state file never crashes the runner: it starts fresh and keeps a copy.
#[tokio::test]
async fn corrupted_state_file_starts_fresh() {
    let dir = tmp_dir("bad");
    std::fs::create_dir_all(&dir).unwrap();
    for bad in ["{ not json", r#"{"v":1,"players":"oops"}"#, r#"{"v":99}"#, ""] {
        std::fs::write(std::path::Path::new(&dir).join("state.json"), bad).unwrap();
        let t = start_with(&[("MODE", "testnet"), ("DATA_DIR", &dir)], mock_opts(MockChain::new(0))).await;
        let k = new_key();
        let g = t.call("POST", "/v1/auth/guest", Some(json!({"pubkey": k.pubkey, "age_confirmed": true})), &[]).await;
        assert!(g.ok(), "fresh start works for {bad:?}");
        assert!(t.call("GET", "/v1/health", None, &[]).await.ok());
    }
    assert!(std::path::Path::new(&dir).join("state.json.corrupt").exists());
}
