//! CLI: `econ_sim stability [seeds] [days]` or `econ_sim sim <seed> <days> [events.json]` (frames as JSON on stdout).
use econ::sim::*;
use econ::world::Config;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("stability") => {
            let seeds = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(100);
            let days = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(60);
            println!("{}", serde_json::to_string_pretty(&stability(seeds, days)).unwrap());
        }
        Some("sim") => {
            let seed = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(1);
            let days = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(30);
            let ev: Vec<ScriptedEvent> = a.get(4).map(|p| serde_json::from_str(&std::fs::read_to_string(p).expect("events file")).expect("events json")).unwrap_or_default();
            let (_, frames) = simulate(Config { seed, ..Config::default() }, days, &ev);
            println!("{}", serde_json::to_string(&frames).unwrap());
        }
        _ => eprintln!("usage: econ_sim stability [seeds] [days] | sim <seed> <days> [events.json]"),
    }
}
