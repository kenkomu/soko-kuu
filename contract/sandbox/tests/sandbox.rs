//! Local sandbox integration test (near-workspaces). No testnet, no real keys: every key here is a throwaway.
//! Signatures are produced OUTSIDE the contract crate by $SIGNER_DIR/sign.mjs (near-api-js / @near-js/crypto, kept out of the repo).
//! Run: cargo build --release --target wasm32-unknown-unknown (in ..), then
//!      SIGNER_DIR=<dir with node_modules/@near-js/crypto and bs58> cargo test --release -- --nocapture --test-threads=1
use near_workspaces::{
    network::Sandbox,
    types::{AccessKey, NearToken, SecretKey},
    Account, AccountId, Worker,
};
use serde_json::{json, Value};
use std::io::Write;
use std::process::{Command, Stdio};

const CONTRACT: &str = "sokokuu.testnet";
const CHAIN: &str = "testnet";
const APP_PUB: &str = "ed25519:9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj";
const APP_MSG: &str = r#"sokokuu/v1|testnet|sokokuu.testnet|ed25519:9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj|42|1770000000000|{"good":"tomato","max_unit_price":3900,"merchant":"njeri","qty":3,"type":"buy"}"#;
const APP_SIG: &str = "4HR/iwG8OT4jMDhhK9vSPqWGcucCZVcYfa8F9OCyCDjh2prJEdZPVbAOd356V5T9hV+9AGi4d1hkat/CF3pSDw==";

fn seed_hex(n: u32) -> String {
    // n == 0 is the app vector seed (bytes 1..32); others are throwaway.
    if n == 0 {
        return (1u8..=32).map(|b| format!("{b:02x}")).collect();
    }
    let mut s = [7u8; 32];
    s[..4].copy_from_slice(&n.to_le_bytes());
    s.iter().map(|b| format!("{b:02x}")).collect()
}

struct Signed {
    pubkey: String,
    sig: String,
}

/// One node call signs many (seed, template) pairs; `{PUB}` in the template is replaced by the pubkey.
fn sign_many(items: &[(u32, String)]) -> Vec<Signed> {
    let dir = std::env::var("SIGNER_DIR").expect("SIGNER_DIR");
    let input: Vec<Value> = items.iter().map(|(n, t)| json!({"seedHex": seed_hex(*n), "template": t})).collect();
    let mut child = Command::new("node")
        .arg(format!("{dir}/sign.mjs"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| panic!("node: {e}"));
    child.stdin.take().unwrap().write_all(serde_json::to_string(&input).unwrap().as_bytes()).unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success(), "signer failed");
    let v: Vec<Value> = serde_json::from_slice(&out.stdout).unwrap();
    v.iter().map(|x| Signed { pubkey: x["pubkey"].as_str().unwrap().into(), sig: x["sig"].as_str().unwrap().into() }).collect()
}

fn msg(contract: &str, chain: &str, nonce: u64, exp: u64, action: &str) -> String {
    format!("sokokuu/v1|{chain}|{contract}|{{PUB}}|{nonce}|{exp}|{action}")
}

struct Env {
    worker: Worker<Sandbox>,
    owner: Account,
    relayer: Account,
    contract: AccountId,
}

async fn patched(worker: &Worker<Sandbox>, id: &str, code: Option<&[u8]>) -> Account {
    let sk = SecretKey::from_random(near_workspaces::types::KeyType::ED25519);
    let aid: AccountId = id.parse().unwrap();
    let mut p = worker.patch(&aid).account(near_workspaces::types::AccountDetailsPatch::default().balance(NearToken::from_near(1000))).access_key(sk.public_key(), AccessKey::full_access());
    if let Some(c) = code {
        p = p.code(c);
    }
    p.transact().await.unwrap();
    Account::from_secret_key(aid, sk, worker)
}

async fn setup() -> Env {
    let worker = near_workspaces::sandbox().await.expect("sandbox (needs the neard sandbox binary)");
    let wasm = std::fs::read(std::env::var("WASM").unwrap_or_else(|_| format!("{}/../target/wasm32-unknown-unknown/release/sokokuu_contract.wasm", env!("CARGO_MANIFEST_DIR")))).expect("build the wasm first");
    let c = patched(&worker, CONTRACT, Some(&wasm)).await;
    let owner = patched(&worker, "owner.testnet", None).await;
    let relayer = patched(&worker, "relayer.testnet", None).await;
    let r = owner
        .call(c.id(), "new")
        .args_json(json!({"chain_id": CHAIN, "seed": 1u64, "relayer": relayer.id()}))
        .max_gas()
        .transact()
        .await
        .unwrap();
    assert!(r.is_success(), "new failed: {:?}", r.failures());
    Env { worker, owner, relayer, contract: c.id().clone() }
}

async fn now_ms(w: &Worker<Sandbox>) -> u64 {
    w.view_block().await.unwrap().timestamp() / 1_000_000
}

async fn act(e: &Env, caller: &Account, pubkey: &str, nonce: u64, exp: u64, action: &str, sig: &str) -> near_workspaces::result::ExecutionFinalResult {
    caller
        .call(&e.contract, "act")
        .args_json(json!({"pubkey": pubkey, "nonce": nonce, "expires_ms": exp, "action": action, "sig": sig}))
        .max_gas()
        .transact()
        .await
        .unwrap()
}

fn err_text(r: &near_workspaces::result::ExecutionFinalResult) -> String {
    format!("{:?}", r.failures())
}

fn assert_code(r: &near_workspaces::result::ExecutionFinalResult, code: &str) {
    assert!(r.is_failure(), "expected {code} but call succeeded");
    assert!(err_text(r).contains(code), "expected {code}, got {}", err_text(r));
}

const CREATE: &str = r#"{"type":"chama_create"}"#;
const BUY: &str = r#"{"good":"tomato","max_unit_price":1000000,"merchant":"njeri","qty":1,"type":"buy"}"#;

async fn nonce_of(e: &Env, pk: &str) -> u64 {
    e.worker.view(&e.contract, "nonce_of").args_json(json!({"pubkey": pk})).await.unwrap().json().unwrap()
}

#[tokio::test]
async fn app_vector_and_act_rules() {
    let e = setup().await;

    // 1. The app's near-api-js vector: signature verifies, then the old expiry (Feb 2026) is rejected as EXPIRED, not BAD_SIG.
    let r = act(&e, &e.relayer, APP_PUB, 42, 1_770_000_000_000, r#"{"good":"tomato","max_unit_price":3900,"merchant":"njeri","qty":3,"type":"buy"}"#, APP_SIG).await;
    assert_code(&r, "EXPIRED");
    // sanity: the vector message really is what the app test pins
    assert!(APP_MSG.contains(APP_PUB));
    // tampered qty (3 -> 4) with the same signature: BAD_SIG
    let r = act(&e, &e.relayer, APP_PUB, 42, 1_770_000_000_000, r#"{"good":"tomato","max_unit_price":3900,"merchant":"njeri","qty":4,"type":"buy"}"#, APP_SIG).await;
    assert_code(&r, "BAD_SIG");

    // 2. Fresh signatures from near-api-js, same seed (key 9C6h...).
    let exp = now_ms(&e.worker).await + 60_000;
    let s = sign_many(&[
        (0, msg(CONTRACT, CHAIN, 1, exp, BUY)),                 // good
        (0, msg("other.testnet", CHAIN, 2, exp, BUY)),          // wrong contract id signed
        (0, msg(CONTRACT, "mainnet", 2, exp, BUY)),             // wrong chain id signed
        (0, msg(CONTRACT, CHAIN, 2, exp - 120_000, BUY)),       // expired when sent
        (0, msg(CONTRACT, CHAIN, 2, exp + 3_600_000, BUY)),     // expiry too far ahead
        (0, msg(CONTRACT, CHAIN, 2, exp, r#"{"type":"advance"}"#)), // player-signed advance
        (0, msg(CONTRACT, CHAIN, 3, exp, BUY)),                 // later accepted
    ]);
    assert_eq!(s[0].pubkey, APP_PUB);

    // not the relayer: FORBIDDEN even with a valid signature
    let r = act(&e, &e.owner, &s[0].pubkey, 1, exp, BUY, &s[0].sig).await;
    assert_code(&r, "FORBIDDEN");
    assert_eq!(nonce_of(&e, APP_PUB).await, 0);

    // buy needs midday: relayer moves the clock dawn -> midday
    assert!(e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap().is_success());
    // accepted
    let r = act(&e, &e.relayer, &s[0].pubkey, 1, exp, BUY, &s[0].sig).await;
    assert!(r.is_success(), "{:?}", r.failures());
    assert_eq!(nonce_of(&e, APP_PUB).await, 1);
    println!("GAS act(first, registers player) = {} Tgas", r.total_gas_burnt.as_gas() as f64 / 1e12);

    // replay
    let r = act(&e, &e.relayer, &s[0].pubkey, 1, exp, BUY, &s[0].sig).await;
    assert_code(&r, "BAD_NONCE");
    // tampered action under a valid sig
    let r = act(&e, &e.relayer, &s[0].pubkey, 1, exp, &BUY.replace("\"qty\":1", "\"qty\":2"), &s[0].sig).await;
    assert_code(&r, "BAD_SIG");
    // wrong contract / chain in the signed bytes
    assert_code(&act(&e, &e.relayer, &s[1].pubkey, 2, exp, BUY, &s[1].sig).await, "BAD_SIG");
    assert_code(&act(&e, &e.relayer, &s[2].pubkey, 2, exp, BUY, &s[2].sig).await, "BAD_SIG");
    // expiry
    assert_code(&act(&e, &e.relayer, &s[3].pubkey, 2, exp - 120_000, BUY, &s[3].sig).await, "EXPIRED");
    assert_code(&act(&e, &e.relayer, &s[4].pubkey, 2, exp + 3_600_000, BUY, &s[4].sig).await, "EXPIRED");
    // player-signed advance: FORBIDDEN, nonce not consumed
    assert_code(&act(&e, &e.relayer, &s[5].pubkey, 2, exp, r#"{"type":"advance"}"#, &s[5].sig).await, "FORBIDDEN");
    assert_eq!(nonce_of(&e, APP_PUB).await, 1);
    // none of the rejections consumed the nonce: nonce 3 (skipping 2) still works, nonce 2 then fails as stale
    let r = act(&e, &e.relayer, &s[6].pubkey, 3, exp, BUY, &s[6].sig).await;
    assert!(r.is_success(), "{:?}", r.failures());
    println!("GAS act(existing player) = {} Tgas", r.total_gas_burnt.as_gas() as f64 / 1e12);
    assert_eq!(nonce_of(&e, APP_PUB).await, 3);

    // 3. advance_clock: relayer only
    let before: Value = e.worker.view(&e.contract, "clock").await.unwrap().json().unwrap();
    assert!(e.owner.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap().is_failure());
    let r = e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap();
    assert!(r.is_success(), "{:?}", r.failures());
    let after: Value = e.worker.view(&e.contract, "clock").await.unwrap().json().unwrap();
    assert_ne!(before, after);
    println!("GAS advance_clock (1 player) = {} Tgas", r.total_gas_burnt.as_gas() as f64 / 1e12);

    // 4. rebind_key: relayer only; new key takes over nonce and balance; old key refused
    let pts_old: String = e.worker.view(&e.contract, "pts_of").args_json(json!({"pubkey": APP_PUB})).await.unwrap().json::<Value>().unwrap().to_string();
    let newk = sign_many(&[(900_001, "x".into())])[0].pubkey.clone();
    let r = e.owner.call(&e.contract, "rebind_key").args_json(json!({"old_pubkey": APP_PUB, "new_pubkey": newk})).max_gas().transact().await.unwrap();
    assert_code(&r, "FORBIDDEN");
    let r = e.relayer.call(&e.contract, "rebind_key").args_json(json!({"old_pubkey": APP_PUB, "new_pubkey": newk})).max_gas().transact().await.unwrap();
    assert!(r.is_success(), "{:?}", r.failures());
    println!("GAS rebind_key (1 player) = {} Tgas", r.total_gas_burnt.as_gas() as f64 / 1e12);
    assert_eq!(nonce_of(&e, &newk).await, 3);
    let pts_new: String = e.worker.view(&e.contract, "pts_of").args_json(json!({"pubkey": newk})).await.unwrap().json::<Value>().unwrap().to_string();
    assert_eq!(pts_old, pts_new);
    let exp = now_ms(&e.worker).await + 60_000;
    let s = sign_many(&[(0, msg(CONTRACT, CHAIN, 4, exp, BUY))]);
    assert_code(&act(&e, &e.relayer, &s[0].pubkey, 4, exp, BUY, &s[0].sig).await, "FORBIDDEN");

    // 5. pause: owner only; blocks act
    assert!(e.relayer.call(&e.contract, "pause").transact().await.unwrap().is_failure());
    assert!(e.owner.call(&e.contract, "pause").transact().await.unwrap().is_success());
    let exp = now_ms(&e.worker).await + 60_000;
    let s = sign_many(&[(900_001, msg(CONTRACT, CHAIN, 4, exp, BUY))]);
    assert_code(&act(&e, &e.relayer, &s[0].pubkey, 4, exp, BUY, &s[0].sig).await, "paused");
    assert!(e.owner.call(&e.contract, "unpause").transact().await.unwrap().is_success());
}

#[tokio::test]
async fn world_snapshot_matches_state() {
    use base64::Engine;
    use sha2::{Digest, Sha256};
    let e = setup().await;
    assert!(e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap().is_success()); // midday
    let exp = now_ms(&e.worker).await + 60_000;
    let s = sign_many(&[(11, msg(CONTRACT, CHAIN, 1, exp, BUY)), (12, msg(CONTRACT, CHAIN, 1, exp, CREATE)), (13, msg(CONTRACT, CHAIN, 1, exp, BUY))]);
    for (i, a) in [BUY, CREATE, BUY].iter().enumerate() {
        let r = act(&e, &e.relayer, &s[i].pubkey, 1, exp, a, &s[i].sig).await;
        assert!(r.is_success(), "{:?}", r.failures());
    }
    let b64: String = e.worker.view(&e.contract, "world_snapshot").await.unwrap().json().unwrap();
    let bytes = base64::engine::general_purpose::STANDARD.decode(&b64).unwrap();
    let w: econ::world::World = borsh::from_slice(&bytes).expect("snapshot decodes with the econ crate");
    let clock: Value = e.worker.view(&e.contract, "clock").await.unwrap().json().unwrap();
    assert_eq!(clock[0].as_u64().unwrap(), w.day as u64);
    assert_eq!(w.players.len(), 3);
    let supply: Value = e.worker.view(&e.contract, "supply").await.unwrap().json().unwrap();
    assert_eq!(supply.as_str().unwrap(), w.supply().to_string());
    for (n, sg) in s.iter().enumerate() {
        let pts: Value = e.worker.view(&e.contract, "pts_of").args_json(json!({"pubkey": sg.pubkey})).await.unwrap().json().unwrap();
        let on_world: Vec<String> = w.players.values().map(|p| p.pts.to_string()).collect();
        assert!(on_world.contains(&pts.as_str().unwrap().to_string()), "player {n} pts {pts} not in snapshot");
    }
    // re-encoding the decoded world gives the same bytes, and world_hash is sha256[..16] of them
    assert_eq!(borsh::to_vec(&w).unwrap(), bytes);
    let hash: String = e.worker.view(&e.contract, "world_hash").await.unwrap().json().unwrap();
    let want: String = Sha256::digest(&bytes)[..16].iter().map(|b| format!("{b:02x}")).collect();
    assert_eq!(hash, want);
    // a state change changes the hash
    assert!(e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap().is_success());
    let hash2: String = e.worker.view(&e.contract, "world_hash").await.unwrap().json().unwrap();
    assert_ne!(hash, hash2);
    println!("SNAPSHOT bytes={} base64_chars={} hash={hash}", bytes.len(), b64.len());
}

#[tokio::test]
async fn merchant_decide_and_crank() {
    let e = setup().await;
    let npc = patched(&e.worker, &format!("npc.{CONTRACT}"), None).await;
    let njeri = patched(&e.worker, &format!("njeri.npc.{CONTRACT}"), None).await;
    let otieno = patched(&e.worker, &format!("otieno.npc.{CONTRACT}"), None).await;
    let _ = npc;
    let ok = njeri.call(&e.contract, "decide").args_json(json!({"merchant": "njeri", "margin_bp": 900})).max_gas().transact().await.unwrap();
    assert!(ok.is_success(), "{:?}", ok.failures());
    println!("GAS decide (0 players) = {} Tgas", ok.total_gas_burnt.as_gas() as f64 / 1e12);
    assert!(ok.logs().iter().any(|l| l.contains("applied=900")));
    let c = njeri.call(&e.contract, "crank").args_json(json!({"merchant": "njeri"})).max_gas().transact().await.unwrap();
    assert!(c.is_success(), "{:?}", c.failures());
    // clamp
    let hi = njeri.call(&e.contract, "decide").args_json(json!({"merchant": "njeri", "margin_bp": 9000})).max_gas().transact().await.unwrap();
    assert!(hi.logs().iter().any(|l| l.contains("applied=4000")));
    // another merchant, owner and a random account cannot decide/crank for njeri
    for who in [&otieno, &e.owner] {
        let r = who.call(&e.contract, "decide").args_json(json!({"merchant": "njeri", "margin_bp": 900})).max_gas().transact().await.unwrap();
        assert_code(&r, "FORBIDDEN");
        let r = who.call(&e.contract, "crank").args_json(json!({"merchant": "njeri"})).max_gas().transact().await.unwrap();
        assert_code(&r, "FORBIDDEN");
    }
}

/// Gas at 1, 50 and 300 players. Registers players with real signed buys; 100 new players per day max, so the relayer advances
/// the clock (3 phases = 1 day) between batches.
#[tokio::test]
async fn gas_by_player_count() {
    let e = setup().await;
    let njeri = patched(&e.worker, &format!("njeri.npc.{CONTRACT}"), None).await;
    assert!(e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap().is_success()); // dawn -> midday
    let mut nonces = vec![0u64; 301];
    let mut registered = 0u32;
    for target in [1u32, 49, 297] {
        while registered < target {
            let batch_end = (registered + 25).min(target);
            let exp = now_ms(&e.worker).await + 100_000;
            let items: Vec<(u32, String)> = (registered + 1..=batch_end).map(|i| (i, msg(CONTRACT, CHAIN, 1, exp, CREATE))).collect();
            let sigs = sign_many(&items);
            for (k, sg) in sigs.iter().enumerate() {
                let i = registered as usize + 1 + k;
                let r = act(&e, &e.relayer, &sg.pubkey, 1, exp, CREATE, &sg.sig).await;
                if r.is_failure() && err_text(&r).contains("RATE_LIMITED") {
                    panic!("rate limited at player {i}: advance more days first");
                }
                assert!(r.is_success(), "player {i}: {:?}", r.failures());
                nonces[i] = 1;
            }
            registered = batch_end;
            if registered < target {
                for _ in 0..3 {
                    assert!(e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap().is_success());
                }
            }
        }
        // measurements at this size
        let exp = now_ms(&e.worker).await + 100_000;
        let n = 1u64;
        let s = sign_many(&[(5000 + registered, msg(CONTRACT, CHAIN, n, exp, CREATE))]);
        let a = act(&e, &e.relayer, &s[0].pubkey, n, exp, CREATE, &s[0].sig).await;
        assert!(a.is_success(), "{:?}", a.failures());
        let g_act = a.total_gas_burnt.as_gas() as f64 / 1e12;
        // advance_clock (may roll a day when phase is dusk)
        let mut g_adv_max = 0f64;
        for _ in 0..3 {
            let r = e.relayer.call(&e.contract, "advance_clock").max_gas().transact().await.unwrap();
            assert!(r.is_success(), "{:?}", r.failures());
            g_adv_max = g_adv_max.max(r.total_gas_burnt.as_gas() as f64 / 1e12);
        }
        let d = njeri.call(&e.contract, "decide").args_json(json!({"merchant": "njeri", "margin_bp": 800})).max_gas().transact().await.unwrap();
        assert!(d.is_success());
        let g_dec = d.total_gas_burnt.as_gas() as f64 / 1e12;
        let newk = sign_many(&[(800_000 + registered, "x".into())])[0].pubkey.clone();
        let old = sign_many(&[(registered, "x".into())])[0].pubkey.clone();
        let rb = e.relayer.call(&e.contract, "rebind_key").args_json(json!({"old_pubkey": old, "new_pubkey": newk})).max_gas().transact().await.unwrap();
        assert!(rb.is_success(), "{:?}", rb.failures());
        let g_rb = rb.total_gas_burnt.as_gas() as f64 / 1e12;
        let sn = e.owner.call(&e.contract, "world_snapshot").max_gas().transact().await.unwrap();
        assert!(sn.is_success(), "{:?}", sn.failures());
        let sn_gas = sn.total_gas_burnt.as_gas() as f64 / 1e12;
        let sn_len = sn.raw_bytes().map(|b| b.len()).unwrap_or(0);
        let hs = e.owner.call(&e.contract, "world_hash").max_gas().transact().await.unwrap();
        assert!(hs.is_success());
        let _v: String = e.worker.view(&e.contract, "world_snapshot").await.unwrap().json().unwrap(); // must fit the view gas limit
        println!("GASROW snapshot_gas={:.1} snapshot_json_bytes={sn_len} world_hash_gas={:.1}", sn_gas, hs.total_gas_burnt.as_gas() as f64 / 1e12);
        println!("GASROW players_total_incl_measure_player={}", registered + 1 + (target > 1) as u32 * 0); println!("GASROW players={registered} act={g_act:.1} advance_clock_max={g_adv_max:.1} decide={g_dec:.1} rebind_key={g_rb:.1} (Tgas; limit 300)");
    }
}
