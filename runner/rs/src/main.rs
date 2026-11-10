use sokokuu_runner::app::{router, App, Options};
use std::collections::HashMap;
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let mut env: HashMap<String, String> = std::env::vars().collect();
    // Real runs keep runner-only state (ledgers, email bindings, ...) in ./data unless DATA_DIR says otherwise.
    if env.get("MODE").map(String::as_str) == Some("testnet") && env.get("DATA_DIR").is_none_or(|v| v.is_empty()) { env.insert("DATA_DIR".into(), "./data".into()); }
    let app = App::build(&env, Options::default()).await;
    let port: u16 = env.get("PORT").and_then(|p| p.parse().ok()).unwrap_or(8787);
    let listener = tokio::net::TcpListener::bind((sokokuu_runner::app::bind_addr(&env), port)).await.expect("bind");
    println!("soko-kuu runner {} on {}:{port} chain={} contract={}", sokokuu_runner::app::VERSION, sokokuu_runner::app::bind_addr(&env), app.cfg.chain_id, app.cfg.contract_id);
    let a2 = app.clone();
    let shutdown = async move {
        let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).expect("sigterm");
        tokio::select! { _ = term.recv() => {}, _ = tokio::signal::ctrl_c() => {} }
        eprintln!("shutting down: saving state");
        a2.flush_state().await;
    };
    axum::serve(listener, router(app).into_make_service_with_connect_info::<SocketAddr>()).with_graceful_shutdown(shutdown).await.expect("serve");
}
