//! Decodes a base64 world snapshot fetched from a live contract: SNAPSHOT_FILE=<path> cargo test --release --test decode -- --nocapture
use base64::Engine;
use sha2::{Digest, Sha256};
#[test]
fn decode_live_snapshot() {
    let Ok(p) = std::env::var("SNAPSHOT_FILE") else { return };
    let b = base64::engine::general_purpose::STANDARD.decode(std::fs::read_to_string(p).unwrap().trim()).unwrap();
    let w: econ::world::World = borsh::from_slice(&b).expect("decodes with econ");
    assert_eq!(borsh::to_vec(&w).unwrap(), b);
    let h: String = Sha256::digest(&b)[..16].iter().map(|x| format!("{x:02x}")).collect();
    println!("DECODED day={} phase={:?} players={} bytes={} hash={h}", w.day, w.phase, w.players.len(), b.len());
}
