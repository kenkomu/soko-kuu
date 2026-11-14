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
        Some("few") => {
            let num = |i: usize, d: u64| a.get(i).and_then(|s| s.parse().ok()).unwrap_or(d);
            let r = few_player_health(num(2, 20), num(3, 180) as u32, num(4, 3) as usize, num(5, 1) as usize);
            println!("{}", serde_json::to_string_pretty(&r).unwrap());
        }
        Some("health") => {
            let num = |i: usize, d: u64| a.get(i).and_then(|s| s.parse().ok()).unwrap_or(d);
            let (_, _, hs) = simulate_active(Config { seed: num(2, 1), players: num(4, 3) as usize, ..Config::default() }, num(3, 180) as u32, &[], num(5, 1) as usize);
            println!("{}", serde_json::to_string(&hs).unwrap());
        }
        _ => eprintln!("usage: econ_sim stability [seeds] [days] | sim <seed> <days> [events.json] | few [seeds] [days] [players] [active] | health <seed> <days> [players] [active]"),
    }
}
