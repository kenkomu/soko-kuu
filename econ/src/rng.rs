//! Tiny deterministic PRNG (splitmix64). Free and seeded: no paid randomness anywhere.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Rng(pub u64);

impl Rng {
    pub fn new(seed: u64) -> Self { Rng(seed ^ 0x9E37_79B9_7F4A_7C15) }
    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    /// Uniform in [0, n). n must be > 0.
    pub fn below(&mut self, n: u64) -> u64 { self.next_u64() % n }
    /// Uniform in [lo, hi] inclusive.
    pub fn range(&mut self, lo: u64, hi: u64) -> u64 { lo + self.below(hi - lo + 1) }
}

/// Stateless hash of several values; used for deterministic haggle outcomes.
pub fn mix(parts: &[u64]) -> u64 {
    let mut r = Rng::new(0);
    for p in parts { r.0 ^= *p; r.next_u64(); }
    r.next_u64()
}

pub fn hash_str(s: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in s.bytes() { h ^= b as u64; h = h.wrapping_mul(0x100_0000_01b3); }
    h
}
