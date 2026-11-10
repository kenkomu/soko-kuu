//! HTTP API (docs/API.md). Every response is `{ok:true,data}` or `{ok:false,error:{code,message}}`.
use crate::auth::{sha_hex, Auth, AuthErr, LogMailer, Mailer, WebhookMailer};
use crate::chain::{Chain, ChainError, DemoChain, SubmitReq};
use crate::market::{EconMarket, Market};
use crate::sig;
use axum::body::Bytes;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, Query, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::middleware::{from_fn_with_state, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use econ::events::EventKind;
use econ::sim::ScriptedEvent;
use econ::{Action, ErrorCode};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tower_http::compression::CompressionLayer;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::set_header::SetResponseHeaderLayer;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
const MAX_PLAYERS: usize = 300; // mirrors the contract's cap

pub fn now_ms() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0) }

// ---- errors / responses
pub struct ApiErr { status: StatusCode, code: String, msg: String, retry_after_s: Option<u64> }
fn err(code: &str, msg: impl Into<String>) -> ApiErr {
    let status = if code == "RATE_LIMITED" { StatusCode::TOO_MANY_REQUESTS } else { StatusCode::BAD_REQUEST };
    ApiErr { status, code: code.into(), msg: msg.into(), retry_after_s: None }
}
fn err404(code: &str, msg: &str) -> ApiErr { ApiErr { status: StatusCode::NOT_FOUND, code: code.into(), msg: msg.into(), retry_after_s: None } }
fn rate(retry: u64, msg: &str) -> ApiErr { ApiErr { status: StatusCode::TOO_MANY_REQUESTS, code: "RATE_LIMITED".into(), msg: msg.into(), retry_after_s: Some(retry) } }
fn code_str(c: ErrorCode) -> String { serde_json::to_value(c).ok().and_then(|v| v.as_str().map(String::from)).unwrap_or_else(|| "INTERNAL".into()) }
fn err_json(e: &ApiErr) -> Value {
    let mut v = json!({"code": e.code, "message": e.msg});
    if let Some(r) = e.retry_after_s { v["retry_after_s"] = json!(r); }
    v
}
impl IntoResponse for ApiErr {
    fn into_response(self) -> Response {
        let body = json!({"ok": false, "error": err_json(&self)});
        let mut r = (self.status, [(header::CACHE_CONTROL, "no-store")], Json(body)).into_response();
        if let Some(s) = self.retry_after_s { if let Ok(h) = HeaderValue::from_str(&s.to_string()) { r.headers_mut().insert(header::RETRY_AFTER, h); } }
        r
    }
}
type Res = Result<Response, ApiErr>;
fn ok(data: Value) -> Res { Ok(([(header::CACHE_CONTROL, "no-store")], Json(json!({"ok": true, "data": data}))).into_response()) }

/// GET reads: strong ETag over the body; `If-None-Match` gets 304.
fn read_ok(headers: &HeaderMap, data: Value) -> Res {
    let body = serde_json::to_vec(&json!({"ok": true, "data": data})).map_err(|_| err("INTERNAL", "encode"))?;
    let etag = format!("\"{}\"", &sha_hex(&String::from_utf8_lossy(&body))[..16]);
    let hit = headers.get(header::IF_NONE_MATCH).and_then(|v| v.to_str().ok()).is_some_and(|v| v.split(',').any(|t| t.trim().trim_start_matches("W/") == etag));
    let mut r = if hit { StatusCode::NOT_MODIFIED.into_response() } else { (StatusCode::OK, [(header::CONTENT_TYPE, "application/json")], body).into_response() };
    r.headers_mut().insert(header::ETAG, HeaderValue::from_str(&etag).unwrap());
    r.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("private, no-cache"));
    Ok(r)
}

// ---- config
pub struct Config {
    pub chain_id: String, pub contract_id: String, pub seed: u64, pub llm: String,
    pub dev_token: bool, pub cooldown_ms: u64, pub cors: Vec<String>,
    pub data_dir: Option<String>, pub max_new_accounts_day: usize, pub min_balance_near: f64,
    pub phase_secs: u64, pub admin_token: Option<String>, pub events_wait_ms: u64, pub ip_rpm: usize, pub trust_proxy: bool,
}

#[derive(Default)]
pub struct Options { pub mailer: Option<Arc<dyn Mailer>>, pub chain: Option<Arc<dyn Chain>>, pub market: Option<Box<dyn Market>> }

struct PlayerRec { id: String, nonce: u64, last_advance_ms: u64, revoke_at: Option<u64> }
struct Meta { created_day: u32, verified: bool }
struct Ev { id: u64, kind: String, day: u32, data: Value }
struct Cache { at: u64, version: u64, prices: Value, news: Value }

struct Inner {
    market: Box<dyn Market>,
    players: HashMap<String, PlayerRec>, // pubkey -> record (several keys may share one player id)
    meta: HashMap<String, Meta>,         // player id -> meta
    auth: Auth,
    chain: Arc<dyn Chain>,
    mode: String,
    degraded: Option<String>,
    events: Vec<Ev>,
    next_ev: u64,
    next_phase_ms: Option<u64>,
    version: u64,
    cache: Option<Cache>,
    paused: bool,
    /// (UTC day bucket, accounts created in it)
    new_accounts: (u64, usize),
    balance_low: Option<String>,
    /// set when the contract's balance for a player differs from the local engine after a relayed act
    drift: Option<String>,
    /// local players the contract has not seen yet (they register on their first relayed act)
    pending: HashSet<String>,
}

impl Inner {
    /// Create the player in the local engine; if the contract does not have it yet, remember it as pending until its first relayed act.
    fn register_local(&mut self, pubkey: &str) -> String {
        let before = self.market.player_count();
        let id = self.market.add_player(pubkey);
        if self.mode == "testnet" && self.market.player_count() > before { self.pending.insert(id.clone()); }
        id
    }
}

struct Limiter { max: usize, window_ms: u64, m: Mutex<HashMap<String, Vec<u64>>> }
impl Limiter {
    fn new(max: usize, window_ms: u64) -> Self { Limiter { max, window_ms, m: Mutex::new(HashMap::new()) } }
    /// Ok, or Err(retry_after_s).
    fn hit(&self, key: &str) -> Result<(), u64> {
        let t = now_ms(); let mut m = self.m.lock().unwrap();
        let a = m.entry(key.to_string()).or_default();
        a.retain(|x| t.saturating_sub(*x) < self.window_ms);
        if a.len() >= self.max { return Err(self.window_ms.saturating_sub(t.saturating_sub(a[0])) / 1000 + 1); }
        a.push(t);
        if m.len() > 5000 { m.retain(|_, v| v.last().is_some_and(|x| t.saturating_sub(*x) <= self.window_ms)); }
        Ok(())
    }
}

pub struct App {
    pub cfg: Config,
    inner: tokio::sync::Mutex<Inner>,
    notify: tokio::sync::Notify,
    write_min: Limiter, auth_limit: Limiter, ip_limit: Limiter,
    mailer: Arc<dyn Mailer>,
}

impl App {
    pub async fn build(env: &HashMap<String, String>, opts: Options) -> Arc<App> {
        let get = |k: &str| env.get(k).filter(|v| !v.is_empty()).cloned();
        let num = |k: &str, d: u64| get(k).and_then(|s| s.parse::<u64>().ok()).unwrap_or(d);
        let mut mode = if get("MODE").as_deref() == Some("testnet") { "testnet" } else { "demo" }.to_string();
        let cfg = Config {
            chain_id: get("CHAIN_ID").unwrap_or_else(|| "testnet".into()),
            contract_id: get("CONTRACT_ID").unwrap_or_else(|| "sokokuu.testnet".into()),
            seed: num("DEMO_SEED", 42),
            llm: get("LLM_PROVIDER").unwrap_or_else(|| "none".into()),
            dev_token: get("DEV_RETURN_TOKEN").as_deref() == Some("1") && mode == "demo",
            cooldown_ms: num("ADVANCE_COOLDOWN_MS", 1500),
            cors: get("CORS_ORIGINS").map(|s| s.split(',').map(|x| x.trim().to_string()).filter(|x| !x.is_empty()).collect()).unwrap_or_default(),
            data_dir: get("DATA_DIR"),
            max_new_accounts_day: num("MAX_NEW_ACCOUNTS_PER_DAY", 100) as usize,
            min_balance_near: get("MIN_BALANCE_NEAR").and_then(|v| v.parse::<f64>().ok()).filter(|v| *v >= 0.0).unwrap_or(0.5),
            phase_secs: num("PHASE_SECS", 0),
            admin_token: get("ADMIN_TOKEN"),
            events_wait_ms: num("EVENTS_WAIT_MS", 25_000),
            ip_rpm: num("IP_RPM", 120) as usize,
            trust_proxy: get("TRUST_PROXY").as_deref() == Some("1"),
        };
        let mut degraded = None;
        let mut chain: Arc<dyn Chain> = Arc::new(DemoChain);
        if mode == "testnet" {
            match opts.chain {
                Some(c) => chain = c,
                None => match crate::testnet::connect(env).await {
                    Ok(c) => chain = c,
                    Err(e) => { degraded = Some(format!("testnet unavailable: {e}")); mode = "demo".into(); }
                },
            }
        }
        let mailer: Arc<dyn Mailer> = opts.mailer.unwrap_or_else(|| match get("MAIL_WEBHOOK_URL") {
            Some(url) => Arc::new(WebhookMailer { url, client: reqwest::Client::new() }),
            None => Arc::new(LogMailer),
        });
        let mut market = opts.market.unwrap_or_else(|| Box::new(EconMarket::new(cfg.seed)));
        if mode == "testnet" { market.set_chain_ids(); }
        let mut auth = Auth::new(get("PUBLIC_CONFIRM_URL").unwrap_or_default());
        auth.mails_per_hour = num("EMAILS_PER_HOUR", 3) as usize;
        let mode_is_testnet = mode == "testnet";
        let next_phase_ms = (cfg.phase_secs > 0).then(|| now_ms() + cfg.phase_secs * 1000);
        let app = Arc::new(App {
            mailer, notify: tokio::sync::Notify::new(),
            write_min: Limiter::new(60, 60_000),
            auth_limit: Limiter::new(20, 60_000), ip_limit: Limiter::new(cfg.ip_rpm, 60_000),
            inner: tokio::sync::Mutex::new(Inner {
                market, players: HashMap::new(), meta: HashMap::new(), auth, chain, mode, degraded,
                events: vec![], next_ev: 1, next_phase_ms, version: 0, cache: None, paused: false, new_accounts: (0, 0), balance_low: None, drift: None, pending: HashSet::new(),
            }),
            cfg,
        });
        let persist_on = mode_is_testnet && app.cfg.data_dir.is_some();
        if persist_on {
            let mut g = app.inner.lock().await;
            load_state(&mut g, app.cfg.data_dir.as_deref().unwrap());
        }
        if mode_is_testnet {
            // The contract may already be past day 0 / dawn: bring the local engine to the same (day, phase) before serving.
            let mut g = app.inner.lock().await;
            if let Some((day, phase)) = g.chain.chain_clock().await {
                let want = phase.clone();
                for _ in 0..3000 {
                    let (d, p) = g.market.clock();
                    if d == day && format!("{p:?}").to_lowercase() == want { break; }
                    if d > day { eprintln!("WARN local engine is ahead of the contract clock (day {d} > {day})"); break; }
                    g.market.advance_clock();
                }
                let (d, p) = g.market.clock();
                eprintln!("clock synced from contract: day {d} {p:?} (contract: day {day} {phase})");
            }
            // Then take the contract's whole world (prices, stock, players, chamas, loans), if its views exist.
            if let Some(bytes) = g.chain.world_snapshot().await {
                match g.market.replace_world(&bytes) {
                    Ok(()) => eprintln!("world loaded from contract snapshot ({} bytes)", bytes.len()),
                    Err(e) => eprintln!("WARN {e}"),
                }
            } else { eprintln!("contract has no world_snapshot view: running as a mirror (drift is only detected through balances)"); }
            // Players we know from the data directory but the contract has not seen (guests that never acted) stay members.
            let ids: HashSet<String> = g.players.values().map(|r| r.id.clone()).collect();
            for id in ids { if !g.market.has_player(&id) { g.market.ensure_player(&id); g.pending.insert(id); } }
        }
        if mode_is_testnet {
            // Balance alarm: the relayer pays gas, so warn loudly (log + /v1/health) before it runs dry.
            let a = app.clone();
            tokio::spawn(async move {
                loop {
                    let chain = a.inner.lock().await.chain.clone();
                    if let Some(y) = chain.balance_yocto().await {
                        let near = y as f64 / 1e24;
                        let mut g = a.inner.lock().await;
                        if near < a.cfg.min_balance_near {
                            let m = format!("relayer balance low: {near:.2} NEAR (alarm below {})", a.cfg.min_balance_near);
                            if g.balance_low.is_none() { eprintln!("ALARM {m}"); }
                            g.balance_low = Some(m);
                        } else { g.balance_low = None; }
                    }
                    tokio::time::sleep(Duration::from_secs(60)).await;
                }
            });
        }
        if persist_on {
            // Debounced durable writes: every second, write only if the serialised state changed (temp file, then rename).
            let a = app.clone();
            tokio::spawn(async move {
                let dir = a.cfg.data_dir.clone().unwrap();
                let mut last = String::new();
                loop {
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    let txt = { let g = a.inner.lock().await; serde_json::to_string(&dump_state(&g)).unwrap_or_default() };
                    if txt.is_empty() || txt == last { continue; }
                    match write_atomic(&dir, &txt) { Ok(()) => last = txt, Err(e) => eprintln!("WARN cannot write state to {dir}: {e}") }
                }
            });
        }
        if app.cfg.phase_secs > 0 {
            // The relayer owns the clock: advance one phase every PHASE_SECS.
            let a = app.clone();
            tokio::spawn(async move {
                loop {
                    tokio::time::sleep(Duration::from_secs(a.cfg.phase_secs)).await;
                    if let Err(e) = relayer_advance(&a).await { eprintln!("clock advance failed: {} {}", e.code, e.msg); }
                }
            });
        }
        app
    }
    /// Test helper: start a login directly and return the raw token (testnet mode hides dev tokens).
    pub async fn test_register(&self, email: &str, pubkey: &str) -> Option<String> {
        self.inner.lock().await.auth.register(email, pubkey, true, now_ms()).ok().map(|(t, _)| t)
    }
    /// Test helper: revoke a key now.
    pub async fn test_expire_key(&self, pubkey: &str) {
        if let Some(r) = self.inner.lock().await.players.get_mut(pubkey) { r.revoke_at = Some(now_ms().saturating_sub(1)); }
    }
    /// Write the durable state now (used on shutdown and by tests); no-op when persistence is off.
    pub async fn flush_state(&self) {
        let Some(dir) = self.cfg.data_dir.clone() else { return };
        let txt = { let g = self.inner.lock().await; if g.mode != "testnet" { return; } serde_json::to_string(&dump_state(&g)).unwrap_or_default() };
        if !txt.is_empty() { if let Err(e) = write_atomic(&dir, &txt) { eprintln!("WARN cannot write state to {dir}: {e}"); } }
    }
    /// Test helper: create a player for a key without any HTTP round trip.
    pub async fn test_bind(&self, pubkey: &str) -> String {
        let mut g = self.inner.lock().await;
        let id = g.register_local(pubkey);
        g.players.insert(pubkey.into(), PlayerRec { id: id.clone(), nonce: 0, last_advance_ms: 0, revoke_at: None });
        g.meta.insert(id.clone(), Meta { created_day: 0, verified: true });
        id
    }
}

struct Checked { pid: String, pubkey: String, nonce: u64, expires_ms: u64, sig: String, message: String }

impl Inner {
    fn push_ev(&mut self, kind: &'static str, data: Value) {
        let day = self.market.clock().0;
        let id = self.next_ev; self.next_ev += 1;
        self.events.push(Ev { id, kind: kind.to_string(), day, data });
        if self.events.len() > 500 { self.events.remove(0); }
    }
    /// Emit change events after the clock moved.
    fn after_clock(&mut self, day0: u32, phase0: econ::Phase) {
        let (day, phase) = self.market.clock();
        self.version += 1;
        if (day, phase) == (day0, phase0) { return; }
        let pi = self.market.report(None)["price_index"].clone();
        self.push_ev("phase", json!({"day": day, "phase": phase, "price_index": pi}));
        if day != day0 {
            let news = self.market.news();
            let fresh: Vec<Value> = news["items"].as_array().cloned().unwrap_or_default().into_iter().filter(|n| n["day"].as_u64() == Some(day as u64)).collect();
            for n in fresh.into_iter().rev() { self.push_ev("news", n); }
            let ids: HashSet<String> = self.players.values().map(|r| r.id.clone()).collect();
            let mut reminders = vec![];
            for id in ids {
                if let Some(st) = self.market.state(&id) {
                    for l in st["loans"].as_array().cloned().unwrap_or_default() {
                        if l["due_day"].as_u64().is_some_and(|d| d <= day as u64 + 1) { reminders.push(json!({"player_id": id, "loan_id": l["id"], "due_day": l["due_day"], "owed": l["owed"]})); }
                    }
                }
            }
            for r in reminders { self.push_ev("loan_reminder", r); }
        }
    }
    fn player_state(&self, pubkey: &str) -> Option<Value> {
        let rec = self.players.get(pubkey)?;
        let mut s = self.market.state(&rec.id)?;
        s["nonce"] = json!(rec.nonce);
        s["next_phase_ms"] = json!(self.next_phase_ms);
        Some(s)
    }
    fn hidden_guests(&self) -> HashSet<String> {
        let day = self.market.clock().0;
        self.meta.iter().filter(|(_, m)| !m.verified && day < m.created_day + 3).map(|(k, _)| k.clone()).collect()
    }
    /// Per-UTC-day cap on new accounts (the relayer may pay storage for each one).
    fn take_account_slot(&mut self, cap: usize) -> Result<(), ApiErr> {
        let now = now_ms(); let day = now / 86_400_000;
        if self.new_accounts.0 != day { self.new_accounts = (day, 0); }
        if self.new_accounts.1 >= cap { return Err(rate((day + 1) * 86_400 - now / 1000, "Too many new accounts today. Try again tomorrow.")); }
        self.new_accounts.1 += 1;
        Ok(())
    }
    fn views(&mut self) -> (&Value, &Value) {
        let stale = self.cache.as_ref().is_none_or(|c| c.version != self.version || now_ms().saturating_sub(c.at) > 3000);
        if stale { self.cache = Some(Cache { at: now_ms(), version: self.version, prices: self.market.prices(), news: self.market.news() }); }
        let c = self.cache.as_ref().unwrap();
        (&c.prices, &c.news)
    }
    /// Signature, key status, expiry, nonce. `action_json` is the exact signed string.
    fn check_signed(&self, cfg: &Config, b: &Value, action_json: &str) -> Result<Checked, ApiErr> {
        let pubkey = b["pubkey"].as_str().filter(|p| sig::parse_pubkey(p).is_some()).ok_or_else(|| err("BAD_SIG", "Bad pubkey"))?;
        let sig_b64 = b["sig"].as_str().ok_or_else(|| err("BAD_SIG", "Missing sig"))?;
        let nonce = b["nonce"].as_u64().ok_or_else(|| err("BAD_SIG", "nonce must be an integer"))?;
        let exp = b["expires_ms"].as_u64().ok_or_else(|| err("BAD_SIG", "expires_ms must be an integer"))?;
        let msg = sig::signed_message(&cfg.chain_id, &cfg.contract_id, pubkey, nonce, exp, action_json);
        if !sig::verify(pubkey, &msg, sig_b64) { return Err(err("BAD_SIG", "Signature does not match")); }
        let rec = self.players.get(pubkey).ok_or_else(|| err("NOT_MEMBER", "Start as a guest or sign in first"))?;
        let now = now_ms();
        if rec.revoke_at.is_some_and(|t| now >= t) { return Err(err("NOT_MEMBER", "This device key was replaced by a newer one")); }
        if exp < now { return Err(err("EXPIRED", "Request expired")); }
        if exp > now + 120_000 { return Err(err("EXPIRED", "expires_ms must be within 2 minutes")); }
        if nonce <= rec.nonce { return Err(err("BAD_NONCE", format!("Nonce must be greater than {}", rec.nonce))); }
        Ok(Checked { pid: rec.id.clone(), pubkey: pubkey.into(), nonce, expires_ms: exp, sig: sig_b64.into(), message: msg })
    }
}

fn parse(body: &Bytes) -> Result<Value, ApiErr> {
    if body.is_empty() { return Ok(json!({})); }
    serde_json::from_slice(body).map_err(|_| err("INTERNAL", "Invalid JSON"))
}

fn origin_allowed(origin: &str, list: &[String]) -> bool {
    let rest = origin.strip_prefix("https://").or_else(|| origin.strip_prefix("http://")).unwrap_or(origin);
    let hostport = rest.split('/').next().unwrap_or("");
    let host = if hostport.starts_with('[') { hostport.split(']').next().map(|h| format!("{h}]")).unwrap_or_default() } else { hostport.split(':').next().unwrap_or("").to_string() };
    if host == "localhost" || host == "127.0.0.1" || host == "[::1]" { return true; }
    list.iter().any(|p| p == origin) // exact origins only; localhost is always allowed for dev
}

// ---- router
pub fn router(app: Arc<App>) -> Router {
    let list = app.cfg.cors.clone();
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(move |o: &HeaderValue, _| o.to_str().is_ok_and(|s| origin_allowed(s, &list))))
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE, header::IF_NONE_MATCH])
        .expose_headers([header::ETAG, header::RETRY_AFTER])
        .max_age(Duration::from_secs(600));
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/state", get(state))
        .route("/v1/prices", get(prices))
        .route("/v1/news", get(news))
        .route("/v1/chamas", get(chamas))
        .route("/v1/chama/{id}", get(chama))
        .route("/v1/ledger", get(ledger))
        .route("/v1/report", get(report))
        .route("/v1/leaderboard", get(leaderboard))
        .route("/v1/events", get(events))
        .route("/v1/auth/guest", post(guest))
        .route("/v1/auth/register", post(register))
        .route("/v1/auth/confirm", post(confirm))
        .route("/v1/auth/account", delete(delete_account))
        .route("/v1/act", post(act))
        .route("/v1/act_batch", post(act_batch))
        .route("/v1/sim", post(sim))
        .route("/v1/admin/advance", post(admin_advance))
        .route("/v1/admin/pause", post(admin_pause))
        .fallback(|| async { err404("INTERNAL", "Not found") })
        .layer(DefaultBodyLimit::max(64 * 1024))
        .layer(from_fn_with_state(app.clone(), ip_guard))
        .layer(CompressionLayer::new().gzip(true))
        .layer(SetResponseHeaderLayer::overriding(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff")))
        .layer(SetResponseHeaderLayer::overriding(header::STRICT_TRANSPORT_SECURITY, HeaderValue::from_static("max-age=31536000")))
        .layer(cors)
        .with_state(app)
}

fn client_ip(app: &App, headers: &HeaderMap, addr: &SocketAddr) -> String {
    if app.cfg.trust_proxy {
        if let Some(f) = headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()).and_then(|v| v.split(',').next_back()) { return f.trim().to_string(); }
    }
    addr.ip().to_string()
}

/// 120 requests/min per IP across the whole API (events long-polls count as one request).
async fn ip_guard(State(app): State<Arc<App>>, ConnectInfo(addr): ConnectInfo<SocketAddr>, req: Request, next: Next) -> Response {
    let ip = client_ip(&app, req.headers(), &addr);
    if let Err(s) = app.ip_limit.hit(&format!("ip:{ip}")) { return rate(s, "Too many requests from this address").into_response(); }
    next.run(req).await
}

type Q = Query<HashMap<String, String>>;
type S = State<Arc<App>>;

async fn health(State(app): S, h: HeaderMap) -> Res {
    let g = app.inner.lock().await; let (day, phase) = g.market.clock();
    read_ok(&h, json!({"version": VERSION, "chain_id": app.cfg.chain_id, "contract_id": app.cfg.contract_id, "mode": g.mode,
        "degraded": g.degraded, "llm_provider": app.cfg.llm, "day": day, "phase": phase, "next_phase_ms": g.next_phase_ms, "paused": g.paused, "relayer_balance_alarm": g.balance_low, "chain_drift": g.drift}))
}
async fn state(State(app): S, h: HeaderMap, Query(q): Q) -> Res {
    let g = app.inner.lock().await;
    let s = g.player_state(q.get("pubkey").map(String::as_str).unwrap_or("")).ok_or_else(|| err404("NOT_MEMBER", "Unknown pubkey"))?;
    read_ok(&h, s)
}
async fn prices(State(app): S, h: HeaderMap) -> Res { let mut g = app.inner.lock().await; let v = g.views().0.clone(); read_ok(&h, v) }
async fn news(State(app): S, h: HeaderMap) -> Res { let mut g = app.inner.lock().await; let v = g.views().1.clone(); read_ok(&h, v) }
async fn chamas(State(app): S, h: HeaderMap) -> Res { let g = app.inner.lock().await; read_ok(&h, g.market.chamas()) }
async fn chama(State(app): S, h: HeaderMap, Path(id): Path<String>) -> Res {
    let v = app.inner.lock().await.market.chama(&id).ok_or_else(|| err404("NOT_MEMBER", "No such chama"))?;
    read_ok(&h, v)
}
async fn ledger(State(app): S, h: HeaderMap, Query(q): Q) -> Res {
    let g = app.inner.lock().await;
    let rec = g.players.get(q.get("pubkey").map(String::as_str).unwrap_or("")).ok_or_else(|| err404("NOT_MEMBER", "Unknown pubkey"))?;
    let day = q.get("day").and_then(|d| d.parse().ok()).unwrap_or(g.market.clock().0);
    read_ok(&h, g.market.ledger(&rec.id, day))
}
async fn report(State(app): S, h: HeaderMap, Query(q): Q) -> Res {
    let g = app.inner.lock().await;
    let id = q.get("pubkey").and_then(|p| g.players.get(p)).map(|r| r.id.clone());
    read_ok(&h, g.market.report(id.as_deref()))
}
async fn leaderboard(State(app): S, h: HeaderMap) -> Res { let g = app.inner.lock().await; read_ok(&h, g.market.leaderboard(&g.hidden_guests())) }

/// Address the listener binds. `BIND_ADDR` wins; otherwise loopback in testnet mode (only the reverse proxy on the same
/// host may reach it) and 0.0.0.0 in demo/dev so phones and emulators on the LAN can reach a local demo.
pub fn bind_addr(env: &std::collections::HashMap<String, String>) -> String {
    match env.get("BIND_ADDR").map(|v| v.trim()).filter(|v| !v.is_empty()) {
        Some(v) => v.to_string(),
        None if env.get("MODE").map(String::as_str) == Some("testnet") => "127.0.0.1".into(),
        None => "0.0.0.0".into(),
    }
}

/// Long-poll: new news, phase/price changes, chama votes and loan reminders in one call.
async fn events(State(app): S, Query(q): Q) -> Res {
    let since: u64 = q.get("since").and_then(|s| s.parse().ok()).unwrap_or(0);
    let deadline = tokio::time::Instant::now() + Duration::from_millis(app.cfg.events_wait_ms);
    loop {
        let notified = app.notify.notified();
        tokio::pin!(notified);
        notified.as_mut().enable(); // register before checking so no wake-up is lost
        {
            let g = app.inner.lock().await;
            let fresh: Vec<Value> = g.events.iter().filter(|e| e.id > since).map(|e| json!({"id": e.id, "kind": e.kind, "day": e.day, "data": e.data})).collect();
            let last = g.events.last().map_or(0, |e| e.id).max(since);
            if !fresh.is_empty() || tokio::time::Instant::now() >= deadline {
                return ok(json!({"events": fresh, "last_id": last, "day": g.market.clock().0, "phase": g.market.clock().1}));
            }
        }
        if tokio::time::timeout_at(deadline, notified).await.is_err() { continue; }
    }
}

fn auth_err(e: AuthErr) -> ApiErr {
    match e {
        AuthErr::Invalid(m) => err("INTERNAL", m), AuthErr::Expired(m) => err("EXPIRED", m),
        AuthErr::BadKey(m) => err("BAD_SIG", m), AuthErr::Rate(s) => rate(s, "Too many sign-in emails for this address"),
    }
}

fn limited(app: &App, ip: &str, what: &str) -> Result<(), ApiErr> {
    app.auth_limit.hit(&format!("{what}:{ip}")).map_err(|s| rate(s, "Too many attempts"))
}

/// 18+ gate happens in the app first; guests play at once, email comes later.
async fn guest(State(app): S, ConnectInfo(addr): ConnectInfo<SocketAddr>, h: HeaderMap, body: Bytes) -> Res {
    limited(&app, &client_ip(&app, &h, &addr), "guest")?;
    let b = parse(&body)?;
    let pubkey = b["pubkey"].as_str().filter(|p| sig::parse_pubkey(p).is_some()).ok_or_else(|| err("BAD_SIG", "Invalid pubkey"))?.to_string();
    if b["age_confirmed"].as_bool() != Some(true) { return Err(err("FORBIDDEN", "Players must confirm they are 18 or older.")); }
    let mut g = app.inner.lock().await;
    if let Some(r) = g.players.get(&pubkey) { return ok(json!({"player_id": r.id})); }
    if g.market.player_count() >= MAX_PLAYERS { return Err(err("RATE_LIMITED", "This season is full.")); }
    g.take_account_slot(app.cfg.max_new_accounts_day)?;
    let id = g.register_local(&pubkey);
    let nonce = g.chain.clone().nonce_of(&pubkey).await.unwrap_or(0);
    let day = g.market.clock().0;
    g.players.insert(pubkey, PlayerRec { id: id.clone(), nonce, last_advance_ms: 0, revoke_at: None });
    g.meta.insert(id.clone(), Meta { created_day: day, verified: false });
    g.version += 1;
    ok(json!({"player_id": id}))
}

async fn register(State(app): S, ConnectInfo(addr): ConnectInfo<SocketAddr>, h: HeaderMap, body: Bytes) -> Res {
    limited(&app, &client_ip(&app, &h, &addr), "reg")?;
    let b = parse(&body)?;
    let (token, mail) = {
        let mut g = app.inner.lock().await;
        g.auth.register(b["email"].as_str().unwrap_or(""), b["pubkey"].as_str().unwrap_or(""), b["consent"].as_bool() == Some(true), now_ms()).map_err(auth_err)?
    };
    app.mailer.send(mail).await.map_err(|e| { eprintln!("mail error: {e}"); err("INTERNAL", "Could not send email") })?;
    let mut data = json!({"sent": true});
    if app.cfg.dev_token { data["dev_token"] = json!(token); }
    ok(data)
}

async fn confirm(State(app): S, ConnectInfo(addr): ConnectInfo<SocketAddr>, h: HeaderMap, body: Bytes) -> Res {
    limited(&app, &client_ip(&app, &h, &addr), "conf")?;
    let b = parse(&body)?;
    let pubkey = b["pubkey"].as_str().unwrap_or("").to_string();
    let mut g = app.inner.lock().await;
    let email_hash = g.auth.confirm(b["token"].as_str().unwrap_or(""), &pubkey, now_ms()).map_err(auth_err)?;
    let now = now_ms();
    let existing = g.auth.player_for(&email_hash).cloned();
    let id = match (g.players.get(&pubkey).map(|r| r.id.clone()), existing) {
        // a guest upgrades: this key's player gets the email
        (Some(mine), None) => { g.auth.bind(email_hash, mine.clone()); if let Some(m) = g.meta.get_mut(&mine) { m.verified = true; } mine }
        (Some(mine), Some(other)) if mine == other => mine,
        (Some(_), Some(_)) => return Err(err("INTERNAL", "This email already has an account. Sign in on a fresh key to use it.")),
        // new device for an existing account: same player; older keys are revoked at once
        (None, Some(other)) => {
            // move the on-chain identity first; if the contract refuses, nothing changes here
            let old = g.players.iter().find(|(_, r)| r.id == other && r.revoke_at.is_none()).map(|(k, _)| k.clone());
            let floor = old.as_ref().and_then(|o| g.players.get(o)).map_or(0, |r| r.nonce); // the new key inherits the old nonce floor
            if let Some(old) = old {
                let chain = g.chain.clone();
                match chain.rebind_key(&old, &pubkey).await {
                    Ok(_) => {}
                    Err(ChainError::Reject { code, msg }) => return Err(err(&code, msg)),
                    Err(ChainError::Down(m)) => { g.degraded = Some(format!("relayer/testnet error: {}", m.chars().take(120).collect::<String>())); g.chain = Arc::new(DemoChain); g.mode = "demo".into(); }
                }
            }
            for r in g.players.values_mut().filter(|r| r.id == other && r.revoke_at.is_none()) { r.revoke_at = Some(now); }
            let nonce = g.chain.clone().nonce_of(&pubkey).await.unwrap_or(floor).max(floor);
            g.players.insert(pubkey, PlayerRec { id: other.clone(), nonce, last_advance_ms: 0, revoke_at: None });
            other
        }
        // brand-new verified player
        (None, None) => {
            if g.market.player_count() >= MAX_PLAYERS { return Err(err("RATE_LIMITED", "This season is full.")); }
            g.take_account_slot(app.cfg.max_new_accounts_day)?;
            let id = g.register_local(&pubkey);
            let nonce = g.chain.clone().nonce_of(&pubkey).await.unwrap_or(0); // reconcile with the contract's nonce
            let day = g.market.clock().0;
            g.players.insert(pubkey, PlayerRec { id: id.clone(), nonce, last_advance_ms: 0, revoke_at: None });
            g.meta.insert(id.clone(), Meta { created_day: day, verified: true });
            g.auth.bind(email_hash, id.clone());
            id
        }
    };
    g.version += 1;
    ok(json!({"player_id": id}))
}

/// Keep the local engine equal to the contract after a relayed call. With the `world_hash` view: compare, and on a
/// difference replace the local world with `world_snapshot` (players that have not acted yet are re-added from our own
/// table). Without the views: fall back to checking one player's balance. `chain_drift` is set only while out of sync.
async fn sync_world(g: &mut Inner, pid: Option<&str>, pubkey: Option<&str>) {
    if g.mode != "testnet" { return; }
    if let Some(chain_hash) = g.chain.world_hash().await {
        if g.market.comparable_hash(&g.pending).as_deref() == Some(chain_hash.as_str()) { g.drift = None; return; }
        let Some(bytes) = g.chain.world_snapshot().await else { return };
        match g.market.replace_world(&bytes) {
            Ok(()) => {
                let pend: Vec<String> = g.pending.iter().cloned().collect();
                for id in pend { g.market.ensure_player(&id); }
                g.version += 1;
                let ok = g.market.comparable_hash(&g.pending).as_deref() == Some(chain_hash.as_str());
                eprintln!("resync: local world replaced from contract snapshot ({} bytes), now {}", bytes.len(), if ok { "in sync" } else { "STILL DIFFERENT" });
                g.drift = if ok { None } else { Some("engine/contract world differs after resync".into()) };
            }
            Err(e) => { eprintln!("WARN {e}"); g.drift = Some(e); }
        }
        return;
    }
    // views missing (older contract): balance check only
    if let (Some(pid), Some(pk)) = (pid, pubkey) {
        if let (Some(chain_pts), Some(local)) = (g.chain.pts_of(pk).await, g.market.state(pid).and_then(|s| s["pts"].as_u64())) {
            if chain_pts != local {
                let m = format!("engine/contract drift: player {pid} local pts {local} vs contract {chain_pts}");
                eprintln!("WARN {m}");
                g.drift = Some(m);
            } else { g.drift = None; }
        }
    }
}

/// Submit to the chain. A contract rejection is returned as an error; an outage degrades to demo.
async fn submit(g: &mut Inner, req: &SubmitReq) -> Result<String, ChainError> {
    match g.chain.submit(req).await {
        Ok(tx) => Ok(tx),
        Err(e @ ChainError::Reject { .. }) => Err(e),
        Err(ChainError::Down(m)) => {
            g.degraded = Some(format!("relayer/testnet error: {}", m.chars().take(120).collect::<String>()));
            g.chain = Arc::new(DemoChain); g.mode = "demo".into();
            g.chain.submit(req).await
        }
    }
}
fn chain_err(e: ChainError) -> ApiErr {
    match e { ChainError::Reject { code, msg } => err(&code, msg), ChainError::Down(m) => err("INTERNAL", m) }
}

async fn delete_account(State(app): S, body: Bytes) -> Res {
    let b = parse(&body)?;
    let mut g = app.inner.lock().await;
    if g.paused { return Err(err("FORBIDDEN", "Writes are paused")); }
    let c = g.check_signed(&app.cfg, &b, sig::DELETE_ACCOUNT_JSON)?;
    // The contract consumes a nonce for the signed delete_account; forward it so both counters stay aligned.
    let req = SubmitReq { pubkey: c.pubkey.clone(), nonce: c.nonce, expires_ms: c.expires_ms, action: sig::DELETE_ACCOUNT_JSON.into(), sig: c.sig.clone(), message: c.message.clone() };
    submit(&mut g, &req).await.map_err(chain_err)?;
    g.auth.unbind_player(&c.pid);
    g.players.retain(|_, r| r.id != c.pid);
    g.meta.remove(&c.pid);
    g.market.remove_player(&c.pid);
    g.version += 1;
    ok(json!({"deleted": true, "player_id": c.pid}))
}

/// NOT_MEMBER covers several cases in the contract; say which one the player hit.
fn refusal_message(m: &dyn Market, action: &Action, code: impl AsRef<str>) -> String {
    if code.as_ref() == "NOT_MEMBER" {
        let merchant = match action {
            Action::Buy { merchant, .. } | Action::Sell { merchant, .. } | Action::Haggle { merchant, .. }
            | Action::CreditRequest { merchant, .. } | Action::Invest { merchant, .. } => Some(merchant),
            _ => None,
        };
        if let Some(mid) = merchant {
            if m.prices()["merchants"].get(mid.as_str()).is_none() { return "unknown merchant".into(); }
        }
        if let Action::ChamaJoin { .. } = action { return "unknown chama".into(); }
        return "You need to be in a chama for that".into();
    }
    "Action refused by market rules".into()
}

/// One signed action, end to end. The caller holds the state lock, so ordering and rollback are safe.
async fn process_act(app: &App, g: &mut Inner, b: &Value) -> Result<Value, ApiErr> {
    let pk = b["pubkey"].as_str().unwrap_or("").to_string();
    if g.paused { return Err(err("FORBIDDEN", "Writes are paused")); }
    let action_json = b["action_json"].as_str().ok_or_else(|| err("INTERNAL", "action_json must be a string"))?.to_string();
    let c = g.check_signed(&app.cfg, b, &action_json)?;
    // Counted only after the signature verifies, so forged requests naming a victim cannot burn their quota.
    app.write_min.hit(&pk).map_err(|s| rate(s, "Too many actions per minute"))?;
    let action: Action = serde_json::from_str(&action_json).map_err(|_| err("INTERNAL", "Unknown action type or bad fields"))?;
    let now = now_ms();
    let is_adv = matches!(action, Action::Advance {});
    if is_adv {
        // testnet: the relayer owns the clock. demo: players may advance, with a cooldown.
        if g.mode == "testnet" { return Err(err("FORBIDDEN", "The market clock is run by the relayer.")); }
        let last = g.players[&pk].last_advance_ms;
        if app.cfg.cooldown_ms > 0 && last != 0 && now.saturating_sub(last) < app.cfg.cooldown_ms {
            return Err(rate(1, "The market clock was just moved. Wait a moment."));
        }
    }
    let (day0, phase0) = g.market.clock();
    let snap = g.market.boxed_clone();
    let out = match g.market.apply(&c.pid, &action) {
        Ok(o) => o,
        Err(code) => {
            g.market = snap;
            let msg = refusal_message(&*g.market, &action, code_str(code));
            return Err(err(&code_str(code), msg));
        }
    };
    let req = SubmitReq { pubkey: pk.clone(), nonce: c.nonce, expires_ms: c.expires_ms, action: action_json, sig: c.sig.clone(), message: c.message.clone() };
    let tx = match submit(g, &req).await {
        Ok(t) => t,
        Err(e) => {
            g.market = snap; // contract said no: roll the engine back
            // A refusal the local rules did not predict means our copy of the world is stale: heal it from the contract.
            if matches!(e, ChainError::Reject { .. }) { sync_world(g, None, None).await; }
            return Err(chain_err(e));
        }
    };
    let rec = g.players.get_mut(&pk).unwrap();
    rec.nonce = c.nonce;
    if is_adv { rec.last_advance_ms = now; if app.cfg.phase_secs > 0 { g.next_phase_ms = Some(now + app.cfg.phase_secs * 1000); } }
    if let Action::ChamaVote { offer_id, .. } = &action {
        let chama_id = g.market.state(&c.pid).and_then(|s| s["chama_id"].as_str().map(String::from));
        g.push_ev("chama_vote", json!({"chama_id": chama_id, "offer_id": offer_id, "player_id": c.pid}));
    }
    g.pending.remove(&c.pid);
    sync_world(g, Some(&c.pid), Some(&pk)).await;
    g.after_clock(day0, phase0);
    let mut delta = out.state_delta; delta["nonce"] = json!(c.nonce);
    let state = g.player_state(&pk);
    Ok(json!({"tx_hash": tx, "state": state, "state_delta": delta, "events": out.events}))
}

async fn act(State(app): S, ConnectInfo(addr): ConnectInfo<SocketAddr>, body: Bytes) -> Res {
    let b = parse(&body)?;
    let _ = addr;
    // Run detached: if the client disconnects mid chain call, the handler future is dropped, which must not
    // abandon the action half-applied (engine changed, nonce not). The spawned task always finishes.
    let a2 = app.clone();
    let r = tokio::spawn(async move {
        let mut g = a2.inner.lock().await;
        process_act(&a2, &mut g, &b).await
    }).await.map_err(|_| err("INTERNAL", "Internal error"))?;
    app.notify.notify_waiters();
    ok(r?)
}

/// Up to 10 signed actions, in order; stops at the first failure. Always 200 with per-action results.
async fn act_batch(State(app): S, body: Bytes) -> Res {
    let b = parse(&body)?;
    let items = b["actions"].as_array().ok_or_else(|| err("INTERNAL", "actions must be an array"))?;
    if items.is_empty() || items.len() > 10 { return Err(err("INTERNAL", "A batch holds 1 to 10 actions")); }
    let items = items.clone();
    let a2 = app.clone();
    let (results, stopped_at) = tokio::spawn(async move {
        let mut results = vec![]; let mut stopped_at = Value::Null;
        let mut g = a2.inner.lock().await;
        for (i, it) in items.iter().enumerate() {
            match process_act(&a2, &mut g, it).await {
                Ok(d) => results.push(json!({"ok": true, "data": d})),
                Err(e) => { results.push(json!({"ok": false, "error": err_json(&e)})); stopped_at = json!(i); break; }
            }
        }
        (results, stopped_at)
    }).await.map_err(|_| err("INTERNAL", "Internal error"))?;
    app.notify.notify_waiters();
    let completed = results.iter().filter(|r| r["ok"] == json!(true)).count();
    let state = results.iter().rev().find(|r| r["ok"] == json!(true)).map(|r| r["data"]["state"].clone()).unwrap_or(Value::Null);
    ok(json!({"results": results, "completed": completed, "stopped_at": stopped_at, "state": state}))
}

// ---- relayer-owned clock
async fn relayer_advance(app: &App) -> Result<Value, ApiErr> {
    let mut g = app.inner.lock().await;
    let (day0, phase0) = g.market.clock();
    let mut tx = None;
    if g.mode == "testnet" {
        match g.chain.advance_clock().await {
            Ok(t) => tx = Some(t),
            Err(ChainError::Reject { code, msg }) => return Err(err(&code, msg)),
            Err(ChainError::Down(m)) => { g.degraded = Some(format!("relayer/testnet error: {}", m.chars().take(120).collect::<String>())); g.chain = Arc::new(DemoChain); g.mode = "demo".into(); }
        }
    }
    let ev = g.market.advance_clock();
    sync_world(&mut g, None, None).await;
    if app.cfg.phase_secs > 0 { g.next_phase_ms = Some(now_ms() + app.cfg.phase_secs * 1000); }
    g.after_clock(day0, phase0);
    let (day, phase) = g.market.clock();
    drop(g);
    app.notify.notify_waiters();
    Ok(json!({"day": day, "phase": phase, "tx_hash": tx, "events": ev}))
}

fn admin_ok(app: &App, h: &HeaderMap) -> Result<(), ApiErr> {
    let want = app.cfg.admin_token.as_deref().ok_or_else(|| err("FORBIDDEN", "Admin is disabled"))?;
    let got = h.get("x-admin-token").and_then(|v| v.to_str().ok()).unwrap_or("");
    let (a, b) = (sha_hex(want), sha_hex(got));
    if a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0 { Ok(()) } else { Err(err("FORBIDDEN", "Bad admin token")) }
}
async fn admin_advance(State(app): S, h: HeaderMap) -> Res { admin_ok(&app, &h)?; ok(relayer_advance(&app).await?) }
/// Kill switch: `{paused:true}` rejects every write (FORBIDDEN) until `{paused:false}`.
async fn admin_pause(State(app): S, h: HeaderMap, body: Bytes) -> Res {
    admin_ok(&app, &h)?;
    let b = parse(&body)?;
    let mut g = app.inner.lock().await;
    g.paused = b["paused"].as_bool().unwrap_or(true);
    ok(json!({"paused": g.paused}))
}

async fn sim(State(app): S, ConnectInfo(addr): ConnectInfo<SocketAddr>, body: Bytes) -> Res {
    app.write_min.hit(&format!("sim:{}", addr.ip())).map_err(|s| rate(s, "Slow down"))?;
    let b = parse(&body)?;
    let seed = b["seed"].as_u64().unwrap_or(1);
    let days = b["days"].as_u64().unwrap_or(14).clamp(1, 120) as u32;
    let mut evs = vec![];
    for e in b["events"].as_array().map(|a| a.iter().take(200).collect::<Vec<_>>()).unwrap_or_default() {
        let (Some(day), Ok(kind)) = (e["day"].as_u64(), serde_json::from_value::<EventKind>(e["kind"].clone())) else { continue };
        if day < 1 || day > days as u64 { continue; }
        evs.push(ScriptedEvent { day: day as u32, kind, magnitude: e["magnitude"].as_u64().unwrap_or(20).clamp(1, 100) as u32 });
    }
    let frames = tokio::task::spawn_blocking(move || {
        let cfg = econ::world::Config { seed, players: 12, ..Default::default() };
        econ::sim::simulate(cfg, days, &evs).1
    }).await.map_err(|_| err("INTERNAL", "sim failed"))?;
    ok(json!({"seed": seed, "days": days, "frames": frames}))
}

// ---- durable runner-only state (what the contract does not hold). No emails in clear: auth keeps hashes only.
const STATE_FILE: &str = "state.json";

fn dump_state(g: &Inner) -> Value {
    let players: serde_json::Map<String, Value> = g.players.iter().map(|(k, r)|
        (k.clone(), json!({"id": r.id, "nonce": r.nonce, "last_advance_ms": r.last_advance_ms, "revoke_at": r.revoke_at}))).collect();
    let meta: serde_json::Map<String, Value> = g.meta.iter().map(|(k, m)| (k.clone(), json!({"created_day": m.created_day, "verified": m.verified}))).collect();
    let events: Vec<Value> = g.events.iter().map(|e| json!({"id": e.id, "kind": e.kind, "day": e.day, "data": e.data})).collect();
    json!({"v": 1, "players": players, "meta": meta, "auth": g.auth.export(), "new_accounts": [g.new_accounts.0, g.new_accounts.1],
           "next_ev": g.next_ev, "events": events, "market": g.market.export_extra()})
}

/// Parse into a staging copy first so a damaged file can never leave `g` half loaded.
type Loaded = (HashMap<String, PlayerRec>, HashMap<String, Meta>, Vec<Ev>, u64, (u64, usize));
fn parse_state(g: &Inner, v: &Value) -> Result<Loaded, String> {
    if v["v"] != json!(1) { return Err("unknown state version".into()); }
    let mut players = HashMap::new();
    for (k, r) in v["players"].as_object().ok_or("players")? {
        players.insert(k.clone(), PlayerRec {
            id: r["id"].as_str().ok_or("player id")?.to_string(), nonce: r["nonce"].as_u64().ok_or("nonce")?,
            last_advance_ms: r["last_advance_ms"].as_u64().unwrap_or(0), revoke_at: r["revoke_at"].as_u64(),
        });
    }
    let mut meta = HashMap::new();
    for (k, m) in v["meta"].as_object().ok_or("meta")? {
        meta.insert(k.clone(), Meta { created_day: m["created_day"].as_u64().unwrap_or(0) as u32, verified: m["verified"].as_bool().unwrap_or(false) });
    }
    let mut events = vec![];
    for e in v["events"].as_array().ok_or("events")? {
        events.push(Ev { id: e["id"].as_u64().ok_or("ev id")?, kind: e["kind"].as_str().ok_or("ev kind")?.to_string(), day: e["day"].as_u64().unwrap_or(0) as u32, data: e["data"].clone() });
    }
    let _ = g;
    let na = (v["new_accounts"][0].as_u64().unwrap_or(0), v["new_accounts"][1].as_u64().unwrap_or(0) as usize);
    Ok((players, meta, events, v["next_ev"].as_u64().unwrap_or(1), na))
}

fn load_state(g: &mut Inner, dir: &str) {
    let path = std::path::Path::new(dir).join(STATE_FILE);
    let txt = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => { eprintln!("data dir {dir}: no saved state, starting fresh"); return; }
        Err(e) => { eprintln!("WARN cannot read {}: {e}; starting fresh", path.display()); return; }
    };
    let res: Result<(), String> = (|| {
        let v: Value = serde_json::from_str(&txt).map_err(|e| e.to_string())?;
        let (players, meta, events, next_ev, na) = parse_state(g, &v)?;
        let mut auth = Auth::new(g.auth.confirm_url.clone());
        auth.mails_per_hour = g.auth.mails_per_hour;
        auth.import(v["auth"].clone())?;
        let mut market = g.market.boxed_clone();
        if !v["market"].is_null() { market.import_extra(v["market"].clone())?; }
        g.players = players; g.meta = meta; g.events = events; g.next_ev = next_ev; g.new_accounts = na; g.auth = auth; g.market = market;
        Ok(())
    })();
    match res {
        Ok(()) => eprintln!("data dir {dir}: loaded {} keys, {} players, {} events", g.players.len(), g.meta.len(), g.events.len()),
        Err(e) => {
            eprintln!("WARN {} is damaged ({e}); keeping a copy as state.json.corrupt and starting fresh", path.display());
            let _ = std::fs::rename(&path, path.with_extension("json.corrupt"));
        }
    }
}

fn write_atomic(dir: &str, txt: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    std::fs::create_dir_all(dir)?;
    let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
    let tmp = std::path::Path::new(dir).join(format!("{STATE_FILE}.tmp"));
    let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
    f.write_all(txt.as_bytes())?;
    f.sync_all()?;
    std::fs::rename(&tmp, std::path::Path::new(dir).join(STATE_FILE))
}

#[cfg(test)]
mod bind_tests {
    use super::bind_addr;
    use std::collections::HashMap;
    fn env(p: &[(&str, &str)]) -> HashMap<String, String> { p.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect() }
    #[test]
    fn testnet_defaults_to_loopback_demo_stays_open_and_override_wins() {
        assert_eq!(bind_addr(&env(&[("MODE", "testnet")])), "127.0.0.1");
        assert_eq!(bind_addr(&env(&[("MODE", "testnet"), ("BIND_ADDR", "")])), "127.0.0.1");
        assert_eq!(bind_addr(&env(&[("MODE", "demo")])), "0.0.0.0");
        assert_eq!(bind_addr(&env(&[])), "0.0.0.0");
        assert_eq!(bind_addr(&env(&[("MODE", "testnet"), ("BIND_ADDR", "0.0.0.0")])), "0.0.0.0");
        assert!("127.0.0.1".parse::<std::net::IpAddr>().unwrap().is_loopback());
    }
}
