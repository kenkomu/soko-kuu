//! Soko Kuu contract. Players are ed25519 keys; the runner relays signed actions.
//! Points ("pts") are a NEP-245 multi-token balance that can never be transferred:
//! no transfer method is exposed and the transfer hook rejects any attempt.
//! There is no withdraw, cash-out or buy-points method.
use std::str::FromStr;

use econ::world::{Config, Player, World};
use econ::{Action, Phase};
use near_sdk::{
    borsh::BorshSerialize,
    env, near,
    store::{LookupMap, LookupSet},
    AccountId, BorshStorageKey, CurveType, PanicOnDefault, PublicKey,
};
use near_sdk_contract_tools::mt::{Nep245Burn, Nep245Controller, Nep245ControllerInternal, Nep245Mint, Nep245Transfer};
use near_sdk_contract_tools::hook::Hook;

/// Token id of the only multi-token id used for balances.
pub const PTS: &str = "pts";
/// Points granted once when a key first acts.
/// Signed no-op that consumes a nonce; the runner removes the email binding.
pub const DELETE_ACCOUNT: &str = r#"{"type":"delete_account"}"#;
/// Hard cap on registered players (whole World is one state blob; bounds per-call gas).
pub const MAX_PLAYERS: usize = 300;
/// New players accepted per game day (storage-DoS guard).
pub const MAX_NEW_PER_DAY: u32 = 100;
/// An action may only be valid for this long past the current block time.
pub const MAX_EXPIRY_MS: u64 = 120_000;
/// Merchant margin clamp (basis points): 2%..40%.
pub const MIN_MARGIN_BP: u64 = 200;
pub const MAX_MARGIN_BP: u64 = 4_000;

/// advance_clock stops mirroring goods eagerly once it has used this many Tgas (limit is 300).
pub const EAGER_SYNC_GAS_TGAS: u64 = 150;
/// ...and after this many goods mint/burn events (NEAR caps all log text of one call at 16 KiB).
pub const MAX_EAGER_EVENTS: usize = 40;
/// Display names for the goods tokens (token id = econ good id).
fn good_name(id: &str) -> &'static str {
    match id {
        "tomato" => "Tomatoes",
        "maize" => "Maize",
        "sukuma" => "Sukuma wiki",
        "onion" => "Onions",
        "fish" => "Fish",
        "charcoal" => "Charcoal",
        _ => "Item",
    }
}

/// Rejects every transfer, including internal ones.
pub struct DenyTransfer;
impl Hook<Contract, Nep245Transfer<'_>> for DenyTransfer {
    fn hook<R>(_: &mut Contract, _: &Nep245Transfer<'_>, _: impl FnOnce(&mut Contract) -> R) -> R {
        env::panic_str("NON_TRANSFERABLE: pts and goods cannot be transferred")
    }
}

#[derive(BorshSerialize, BorshStorageKey)]
#[borsh(crate = "near_sdk::borsh")]
enum Key {
    Nonces,
    Ids,
    Revoked,
}

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Contract {
    chain_id: String,
    /// Only account allowed to call `advance_clock`.
    relayer: AccountId,
    /// Can pause and unpause write methods.
    owner: AccountId,
    paused: bool,
    new_today: (u32, u32),
    /// Last accepted nonce per player key (absent = never acted).
    nonces: LookupMap<[u8; 32], u64>,
    /// Player id (balance owner / world key) per public key. Absent = the default id derived from the key.
    ids: LookupMap<[u8; 32], AccountId>,
    /// Keys retired by `rebind_key`; they can never act again.
    revoked: LookupSet<[u8; 32]>,
    /// Authoritative game state (econ rules). MultiToken `pts` balances mirror it for the acting player.
    world: World,
}

impl Nep245ControllerInternal for Contract {
    type MintHook = ();
    type TransferHook = DenyTransfer;
    type BurnHook = ();
    type LoadTokenMetadata = ();
}

/// Implicit-account style id (64 hex chars) derived from the player key; used as balance owner.
fn player_account(key: &[u8; 32]) -> AccountId {
    let hex: String = key.iter().map(|b| format!("{b:02x}")).collect();
    AccountId::from_str(&hex).unwrap()
}

fn parse_key(pubkey: &str) -> [u8; 32] {
    let pk = PublicKey::from_str(pubkey).unwrap_or_else(|_| fail("BAD_SIG", "bad pubkey"));
    if pk.curve_type() != CurveType::ED25519 {
        fail("BAD_SIG", "pubkey must be ed25519");
    }
    pk.as_bytes()[1..].try_into().unwrap_or_else(|_| fail("BAD_SIG", "pubkey length"))
}

/// Exact bytes the player signs (docs/API.md).
pub fn signed_message(chain_id: &str, contract_id: &str, pubkey: &str, nonce: u64, expires_ms: u64, action_json: &str) -> Vec<u8> {
    format!("sokokuu/v1|{chain_id}|{contract_id}|{pubkey}|{nonce}|{expires_ms}|{action_json}").into_bytes()
}

fn fail(code: &str, msg: &str) -> ! {
    env::panic_str(&format!("{code}: {msg}"))
}

#[near]
impl Contract {
    #[init]
    pub fn new(chain_id: String, seed: u64, relayer: AccountId) -> Self {
        let mut c = Self { chain_id, relayer, owner: env::predecessor_account_id(), paused: false, new_today: (0, 0), nonces: LookupMap::new(Key::Nonces), ids: LookupMap::new(Key::Ids), revoked: LookupSet::new(Key::Revoked), world: World::new(Config { seed, players: 0, ..Config::default() }) };
        Nep245Controller::create_token(&mut c, PTS.to_string()).unwrap_or_else(|e| fail("INTERNAL", &e.to_string()));
        c
    }

    /// Submit a player-signed action. Only the relayer account may call; the signature is the authority.
    /// `action_json` must be the exact canonical JSON that was signed. Panics are prefixed with an API error code.
    pub fn act(&mut self, pubkey: String, nonce: u64, expires_ms: u64, action: String, sig: near_sdk::json_types::Base64VecU8) {
        self.assert_not_paused();
        if env::predecessor_account_id() != self.relayer {
            fail("FORBIDDEN", "only the relayer may call act");
        }
        let pk = PublicKey::from_str(&pubkey).unwrap_or_else(|_| fail("BAD_SIG", "bad pubkey"));
        if pk.curve_type() != CurveType::ED25519 || String::from(&pk) != pubkey {
            fail("BAD_SIG", "pubkey must be canonical ed25519");
        }
        let key: [u8; 32] = pk.as_bytes()[1..].try_into().unwrap_or_else(|_| fail("BAD_SIG", "pubkey length"));
        let sig: [u8; 64] = sig.0.try_into().unwrap_or_else(|_| fail("BAD_SIG", "signature length"));

        let action_json = action;
        let msg = signed_message(&self.chain_id, env::current_account_id().as_str(), &pubkey, nonce, expires_ms, &action_json);
        if !env::ed25519_verify(&sig, &msg, &key) {
            fail("BAD_SIG", "signature does not verify");
        }
        if self.revoked.contains(&key) {
            fail("FORBIDDEN", "key was revoked by a rebind");
        }
        let now = env::block_timestamp_ms();
        if now > expires_ms {
            fail("EXPIRED", "action expired");
        }
        if expires_ms > now + MAX_EXPIRY_MS {
            fail("EXPIRED", "expiry too far in the future (max 2 minutes)");
        }
        let last = self.nonces.get(&key).copied();
        if nonce <= last.unwrap_or(0) {
            fail("BAD_NONCE", "nonce must be greater than the last accepted nonce");
        }
        let is_delete = action_json == DELETE_ACCOUNT;
        let action: Option<Action> = if is_delete { None } else { Some(serde_json::from_str(&action_json).unwrap_or_else(|_| fail("INTERNAL", "unparseable action"))) };

        self.nonces.insert(key, nonce);
        let who = self.player_id(&key);
        // delete_account only consumes a nonce; the email binding lives in the runner.
        if let Some(a) = action {
            if matches!(a, Action::Advance {}) {
                fail("FORBIDDEN", "advance is relayer-only; use advance_clock");
            }
            self.register(&who);
            if self.ids.get(&key).is_none() {
                self.ids.insert(key, who.clone());
            }
            self.sync_player(&who);
            // A chama vote can pay out to the borrower, so mirror whoever changed; otherwise only the actor does.
            let before = matches!(a, Action::ChamaVote { .. }).then(|| self.holdings());
            match self.world.apply(who.as_str(), &a) {
                Ok(r) => {
                    match before {
                        Some(b) => self.sync_changed(b, true),
                        None => self.sync_player(&who),
                    }
                    for line in r.ledger.iter().filter(|l| l.pts != 0) {
                        env::log_str(&format!("ledger|{}|{}", line.pts, line.cause));
                    }
                    for e in r.events {
                        env::log_str(&format!("event|{e}"));
                    }
                }
                // Panic reverts everything, including the nonce bump, so rejected actions are free to retry.
                Err(code) => {
                    let c = serde_json::to_string(&code).unwrap_or_default();
                    fail(c.trim_matches('"'), "action rejected by rules")
                }
            }
        }
    }

    /// Move the clock to the next phase (a new day after dusk). Relayer only.
    pub fn advance_clock(&mut self) {
        self.assert_not_paused();
        if env::predecessor_account_id() != self.relayer {
            fail("FORBIDDEN", "only the relayer may advance the clock");
        }
        let before = self.holdings();
        let r = self.world.advance().unwrap_or_else(|_| fail("INTERNAL", "advance failed"));
        // Spoilage, consumption, loan settlement: burn/mint so token balances follow the world.
        self.sync_changed(before, false);
        for e in r.events {
            env::log_str(&format!("event|{e}"));
        }
    }

    /// Merchant decision. Caller must be the merchant's own sub-account (`<id>.npc.<contract>`).
    /// `margin_bp` is clamped to 2%..40%; the +-20%/day price move is enforced by the econ quote (ref_mid).
    pub fn decide(&mut self, merchant: String, margin_bp: u64) {
        self.assert_not_paused();
        self.assert_merchant(&merchant);
        let mi = self.world.merchant_idx(&merchant).unwrap_or_else(|| fail("INTERNAL", "unknown merchant"));
        let m = margin_bp.clamp(MIN_MARGIN_BP, MAX_MARGIN_BP);
        self.world.merchants[mi].spread_bp = m;
        env::log_str(&format!("event|decision|{merchant}|asked={margin_bp}|applied={m}"));
    }

    /// Merchant heartbeat; the only other method a merchant key may call. State-neutral (the clock is relayer-only).
    pub fn crank(&mut self, merchant: String) {
        self.assert_not_paused();
        self.assert_merchant(&merchant);
        env::log_str(&format!("event|crank|{merchant}|day={}", self.world.day));
    }

    // ---- NEP-245 views (standard shapes; ids are the player hex account) ----
    pub fn mt_balance_of(&self, account_id: AccountId, token_id: String) -> near_sdk::json_types::U128 {
        Nep245Controller::balance_of(self, &token_id, &account_id).into()
    }
    pub fn mt_batch_balance_of(&self, account_id: AccountId, token_ids: Vec<String>) -> Vec<near_sdk::json_types::U128> {
        token_ids.iter().map(|t| Nep245Controller::balance_of(self, t, &account_id).into()).collect()
    }
    pub fn mt_supply(&self, token_id: String) -> Option<near_sdk::json_types::U128> {
        Some(self.supply_of(&token_id)?.into())
    }
    pub fn mt_batch_supply(&self, token_ids: Vec<String>) -> Vec<Option<near_sdk::json_types::U128>> {
        token_ids.iter().map(|t| self.supply_of(t).map(Into::into)).collect()
    }
    /// NEP-245 `mt_token`: known ids only (`pts` and the goods). `owner_id` is null (fungible-style ids).
    pub fn mt_token(&self, token_ids: Vec<String>) -> Vec<Option<serde_json::Value>> {
        token_ids.iter().map(|t| Self::is_token_id(t).then(|| serde_json::json!({ "token_id": t, "owner_id": null }))).collect()
    }
    /// NEP-245 metadata extension: contract level.
    pub fn mt_metadata_contract(&self) -> serde_json::Value {
        serde_json::json!({ "spec": "mt-1.0.0", "name": "Soko Kuu", "symbol": "SOKO" })
    }
    /// Per-token metadata for `pts` and the goods (also served under the shorter name `mt_metadata`).
    pub fn mt_metadata_base_by_token_id(&self, token_ids: Vec<String>) -> Vec<Option<serde_json::Value>> {
        self.metadata_for(&token_ids)
    }
    pub fn mt_metadata(&self, token_ids: Vec<String>) -> Vec<Option<serde_json::Value>> {
        self.metadata_for(&token_ids)
    }

    /// Device recovery: move the player behind `old_pubkey` to `new_pubkey`. Relayer only.
    /// The player id, world record and pts balance stay put (only the key mapping moves); the old key is
    /// revoked at once and the new key inherits the old nonce floor.
    pub fn rebind_key(&mut self, old_pubkey: String, new_pubkey: String) {
        self.assert_not_paused();
        if env::predecessor_account_id() != self.relayer {
            fail("FORBIDDEN", "only the relayer may rebind keys");
        }
        let old = parse_key(&old_pubkey);
        let new = parse_key(&new_pubkey);
        let who = self.player_id(&old);
        if old == new || !self.world.players.contains_key(who.as_str()) || self.revoked.contains(&old) {
            if old == new {
                fail("FORBIDDEN", "old and new keys are the same");
            }
            fail("NOT_MEMBER", "old key has no player");
        }
        if self.revoked.contains(&new)
            || self.ids.get(&new).is_some()
            || self.nonces.get(&new).is_some()
            || self.world.players.contains_key(player_account(&new).as_str())
        {
            fail("FORBIDDEN", "new key already has a player");
        }
        let floor = self.nonces.get(&old).copied().unwrap_or(0);
        self.ids.insert(new, who.clone());
        self.ids.remove(&old);
        self.nonces.insert(new, floor);
        self.nonces.remove(&old);
        self.revoked.insert(old);
        env::log_str(&format!("event|rebind|{who}|{old_pubkey}|{new_pubkey}"));
    }

    /// Owner-only kill switch for the write methods (`act`, `advance_clock`).
    pub fn pause(&mut self) {
        self.assert_owner();
        self.paused = true;
        env::log_str("event|paused");
    }
    pub fn unpause(&mut self) {
        self.assert_owner();
        self.paused = false;
        env::log_str("event|unpaused");
    }

    /// pts can never be transferred. These exist only to answer NEP-245 callers with a clear error.
    pub fn mt_transfer(&mut self) {
        fail("NON_TRANSFERABLE", "pts and goods cannot be transferred");
    }
    pub fn mt_batch_transfer(&mut self) {
        fail("NON_TRANSFERABLE", "pts and goods cannot be transferred");
    }

    // ---- views ----
    pub fn is_paused(&self) -> bool {
        self.paused
    }
    pub fn nonce_of(&self, pubkey: String) -> u64 {
        let key = parse_key(&pubkey);
        self.nonces.get(&key).copied().unwrap_or(0)
    }
    pub fn pts_of(&self, pubkey: String) -> near_sdk::json_types::U128 {
        let key = parse_key(&pubkey);
        if self.revoked.contains(&key) {
            return 0.into();
        }
        self.world.players.get(self.player_id(&key).as_str()).map_or(0, |p| p.pts as u128).into()
    }
    pub fn clock(&self) -> (u32, Phase) {
        (self.world.day, self.world.phase)
    }
    /// Borsh bytes of the whole econ `World`, returned as a base64 string in JSON (Base64VecU8). Pure view.
    pub fn world_snapshot(&self) -> near_sdk::json_types::Base64VecU8 {
        near_sdk::borsh::to_vec(&self.world).unwrap_or_else(|_| fail("INTERNAL", "world serialisation")).into()
    }
    /// First 16 bytes of sha256(Borsh(World)) as 32 lowercase hex characters, for cheap drift detection.
    pub fn world_hash(&self) -> String {
        let bytes = near_sdk::borsh::to_vec(&self.world).unwrap_or_else(|_| fail("INTERNAL", "world serialisation"));
        env::sha256(&bytes)[..16].iter().map(|b| format!("{b:02x}")).collect()
    }
    pub fn supply(&self) -> near_sdk::json_types::U128 {
        (self.world.supply() as u128).into()
    }
    pub fn relayer(&self) -> AccountId {
        self.relayer.clone()
    }
    pub fn chain_id(&self) -> String {
        self.chain_id.clone()
    }
}

impl Contract {
    /// Player id behind a key: the rebound/registered id, else the default derived from the key.
    fn player_id(&self, key: &[u8; 32]) -> AccountId {
        self.ids.get(key).cloned().unwrap_or_else(|| player_account(key))
    }
    fn assert_owner(&self) {
        if env::predecessor_account_id() != self.owner {
            fail("FORBIDDEN", "owner only");
        }
    }
    fn assert_merchant(&self, merchant: &str) {
        let want = format!("{merchant}.npc.{}", env::current_account_id());
        if env::predecessor_account_id().as_str() != want && env::predecessor_account_id() != self.relayer {
            fail("FORBIDDEN", "only the merchant's own account may call this");
        }
    }
    fn assert_not_paused(&self) {
        if self.paused {
            fail("FORBIDDEN", "contract is paused");
        }
    }

    fn is_token_id(t: &str) -> bool {
        t == PTS || econ::pricing::good(t).is_some()
    }

    /// Supply of a known token id; 0 before its first mint (goods tokens are created lazily).
    fn supply_of(&self, t: &str) -> Option<u128> {
        if !Self::is_token_id(t) {
            return None;
        }
        Some(Nep245Controller::supply(self, t).unwrap_or(0))
    }

    fn metadata_for(&self, token_ids: &[String]) -> Vec<Option<serde_json::Value>> {
        token_ids
            .iter()
            .map(|t| {
                Self::is_token_id(t).then(|| {
                    let (title, desc) = if t == PTS {
                        ("Soko pts".to_string(), "Game score. Not money; never transferable.".to_string())
                    } else {
                        (good_name(t).to_string(), "Market good held by a player. Not transferable; bought and sold only through the market rules.".to_string())
                    };
                    serde_json::json!({ "title": title, "description": desc, "transferable": false })
                })
            })
            .collect()
    }

    fn mint_token(&mut self, token: &str, who: &AccountId, amount: u128, memo: &str) {
        if !Nep245Controller::token_exists(self, token) {
            Nep245Controller::create_token(self, token.to_string()).unwrap_or_else(|e| fail("INTERNAL", &e.to_string()));
        }
        Nep245Controller::mint(self, &Nep245Mint::single(token, amount, who).memo(memo))
            .unwrap_or_else(|e| fail("INTERNAL", &e.to_string()));
    }

    fn burn_token(&mut self, token: &str, who: &AccountId, amount: u128, memo: &str) {
        Nep245Controller::burn(self, &Nep245Burn::single(token, amount, who).memo(memo))
            .unwrap_or_else(|_| fail("INTERNAL", "goods balance below burn"));
    }

    /// Make the player's goods token balances equal the world stock (mint or burn the difference).
    fn sync_goods(&mut self, who: &AccountId) -> usize {
        let mut ops = 0;
        for g in econ::pricing::GOODS.iter() {
            let want = self.world.players.get(who.as_str()).and_then(|p| p.stock.get(g.id)).copied().unwrap_or(0) as u128;
            let have = Nep245Controller::balance_of(self, g.id, who);
            if want > have {
                self.mint_token(g.id, who, want - have, "sync");
            } else if have > want {
                self.burn_token(g.id, who, have - want, "sync");
            }
            ops += (want != have) as usize;
        }
        ops
    }

    fn sync_player(&mut self, who: &AccountId) {
        self.sync_pts(who);
        self.sync_goods(who);
    }

    /// In-memory copy of every player's (pts, stock); no storage reads.
    fn holdings(&self) -> Vec<(String, econ::Pts, std::collections::BTreeMap<String, u32>)> {
        self.world.players.iter().map(|(k, p)| (k.clone(), p.pts, p.stock.clone())).collect()
    }

    /// Mirror only the players whose pts or stock changed since `before` (keeps gas flat at 300 players).
    /// With `with_pts` false only goods are mirrored (day rolls move every chama member's pts weekly; that
    /// would cost ~1 Tgas per player, so pts heal lazily at the player's next act).
    fn sync_changed(&mut self, before: Vec<(String, econ::Pts, std::collections::BTreeMap<String, u32>)>, with_pts: bool) {
        let mut ops = 0;
        for (id, pts, stock) in before {
            let (pts_changed, stock_changed) = match self.world.players.get(&id) {
                Some(p) => (p.pts != pts, p.stock != stock),
                None => continue,
            };
            if stock_changed || (with_pts && pts_changed) {
                // Gas guard: ~1 Tgas per changed holder. Past the budget, the rest heal at their next act.
                // Log budget: NEAR caps total log text at 16 KiB and each NEP-245 event is ~250 bytes.
                if !with_pts && (ops >= MAX_EAGER_EVENTS || env::used_gas() > near_sdk::Gas::from_tgas(EAGER_SYNC_GAS_TGAS)) {
                    break;
                }
                if let Ok(a) = AccountId::from_str(&id) {
                    if with_pts {
                        self.sync_pts(&a);
                    }
                    ops += self.sync_goods(&a);
                }
            }
        }
    }

    fn mint_pts(&mut self, who: &AccountId, amount: u128, memo: &str) {
        Nep245Controller::mint(self, &Nep245Mint::single(PTS, amount, who).memo(memo))
            .unwrap_or_else(|e| fail("INTERNAL", &e.to_string()));
    }

    fn burn_pts(&mut self, who: &AccountId, amount: u128, memo: &str) {
        Nep245Controller::burn(self, &Nep245Burn::single(PTS, amount, who).memo(memo))
            .unwrap_or_else(|_| fail("NOT_ENOUGH_PTS", "insufficient pts"));
    }

    /// Create the player in the econ world on first sight, minting their starting pts into the economy.
    fn register(&mut self, who: &AccountId) {
        if self.world.players.contains_key(who.as_str()) {
            return;
        }
        if self.world.players.len() >= MAX_PLAYERS {
            fail("RATE_LIMITED", "player cap reached");
        }
        let start = self.world.cfg.start_pts;
        let day = self.world.day;
        if self.new_today.0 != day {
            self.new_today = (day, 0);
        }
        if self.new_today.1 >= MAX_NEW_PER_DAY {
            fail("RATE_LIMITED", "daily new-player cap reached");
        }
        self.new_today.1 += 1;
        self.world.players.insert(who.to_string(), Player { id: who.to_string(), pts: start, ..Default::default() });
        self.world.minted += start;
        self.world.target_supply += start;
    }

    /// Make the MultiToken balance equal the world's pts for this player (mint or burn the difference).
    fn sync_pts(&mut self, who: &AccountId) {
        let want = self.world.players.get(who.as_str()).map_or(0, |p| p.pts as u128);
        let have = Nep245Controller::balance_of(self, PTS, who);
        if want > have {
            self.mint_pts(who, want - have, "sync");
        } else if have > want {
            self.burn_pts(who, have - want, "sync");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use near_sdk::{test_utils::VMContextBuilder, testing_env};

    const CONTRACT: &str = "sokokuu.testnet";
    const RELAYER: &str = "relayer.testnet";
    const ADV: &str = r#"{"type":"advance"}"#;

    fn setup(ts_ms: u64) -> Contract {
        testing_env!(VMContextBuilder::new()
            .current_account_id(CONTRACT.parse().unwrap())
            .block_timestamp(ts_ms * 1_000_000)
            .build());
        Contract::new("testnet".into(), 1, RELAYER.parse().unwrap())
    }
    fn sk() -> SigningKey {
        SigningKey::from_bytes(&[7u8; 32])
    }
    fn pk_str(sk: &SigningKey) -> String {
        format!("ed25519:{}", bs58(sk.verifying_key().as_bytes()))
    }
    fn bs58(b: &[u8]) -> String {
        String::from(&PublicKey::from_parts(CurveType::ED25519, b.to_vec()).unwrap())[8..].to_string()
    }
    fn call(c: &mut Contract, sk: &SigningKey, nonce: u64, exp: u64, json: &str) {
        let ts = near_sdk::env::block_timestamp();
        testing_env!(VMContextBuilder::new().current_account_id(CONTRACT.parse().unwrap())
            .predecessor_account_id(RELAYER.parse().unwrap()).block_timestamp(ts).build());
        let pk = pk_str(sk);
        let msg = signed_message("testnet", CONTRACT, &pk, nonce, exp, json);
        let sig = sk.sign(&msg).to_bytes().to_vec();
        c.act(pk, nonce, exp, json.into(), sig.into());
    }

    fn as_caller(who: &str) {
        testing_env!(VMContextBuilder::new()
            .current_account_id(CONTRACT.parse().unwrap())
            .predecessor_account_id(who.parse().unwrap())
            .block_timestamp(1000 * 1_000_000)
            .build());
    }

    #[test]
    fn relayer_can_advance() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 1, 5000, DELETE_ACCOUNT); // delete_account is a nonce-only no-op
        call(&mut c, &sk(), 2, 5000, r#"{"type":"chama_create"}"#); // registers the player
        as_caller(RELAYER);
        c.advance_clock();
        assert_eq!(c.clock().1, Phase::Midday);
    }

    #[test]
    fn clock_advances_with_no_players() {
        let mut c = setup(1000);
        as_caller(RELAYER);
        c.advance_clock();
        assert_eq!(c.clock().1, Phase::Midday);
        assert!(c.world.players.is_empty());
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn non_relayer_cannot_advance() {
        let mut c = setup(1000);
        as_caller("mallory.testnet");
        c.advance_clock();
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn player_signed_advance_rejected() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 1, 5000, ADV);
    }

    #[test]
    fn first_act_registers_with_starting_pts() {
        let mut c = setup(1000);
        let k = sk();
        call(&mut c, &k, 1, 5000, r#"{"type":"chama_create"}"#);
        assert_eq!(c.nonce_of(pk_str(&k)), 1);
        // 20,000 starting pts minus the chama join share
        let pts = c.pts_of(pk_str(&k)).0;
        assert!(pts > 0 && pts < 20_000);
        assert_eq!(c.supply().0, 4 * 120_000 + 20_000); // merchants + the one player
    }

    #[test]
    #[should_panic(expected = "BAD_NONCE")]
    fn replay_rejected() {
        let mut c = setup(1000);
        let k = sk();
        call(&mut c, &k, 1, 5000, DELETE_ACCOUNT);
        call(&mut c, &k, 1, 5000, DELETE_ACCOUNT);
    }

    #[test]
    fn large_nonce_jump_accepted() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 52, 5000, DELETE_ACCOUNT);
        assert_eq!(c.nonce_of(pk_str(&sk())), 52);
    }

    #[test]
    #[should_panic(expected = "BAD_NONCE")]
    fn equal_nonce_rejected() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 5, 5000, DELETE_ACCOUNT);
        call(&mut c, &sk(), 5, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "BAD_NONCE")]
    fn lower_nonce_rejected() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 5, 5000, DELETE_ACCOUNT);
        call(&mut c, &sk(), 4, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "BAD_NONCE")]
    fn zero_nonce_rejected() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 0, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "EXPIRED")]
    fn expiry_over_2_minutes_rejected() {
        let mut c = setup(1000);
        call(&mut c, &sk(), 1, 1000 + 120_001, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn paused_blocks_act() {
        let mut c = setup(1000); // predecessor in the default context is the owner
        c.pause();
        call(&mut c, &sk(), 1, 5000, DELETE_ACCOUNT);
    }

    #[test]
    fn unpause_restores_act() {
        let mut c = setup(1000);
        c.pause();
        c.unpause();
        call(&mut c, &sk(), 1, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn only_owner_can_pause() {
        let mut c = setup(1000);
        as_caller("mallory.testnet");
        c.pause();
    }

    #[test]
    #[should_panic(expected = "NON_TRANSFERABLE")]
    fn mt_transfer_method_panics() {
        setup(1000).mt_transfer();
    }

    #[test]
    #[should_panic(expected = "EXPIRED")]
    fn expired_rejected() {
        let mut c = setup(9000);
        call(&mut c, &sk(), 1, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "BAD_SIG")]
    fn tampered_action_rejected() {
        let mut c = setup(1000);
        let k = sk();
        let pk = pk_str(&k);
        let sig = k.sign(&signed_message("testnet", CONTRACT, &pk, 1, 5000, ADV)).to_bytes().to_vec();
        as_caller(RELAYER);
        c.act(pk, 1, 5000, r#"{"type":"advance" }"#.into(), sig.into());
    }

    #[test]
    #[should_panic(expected = "BAD_SIG")]
    fn wrong_contract_rejected() {
        let mut c = setup(1000);
        let k = sk();
        let pk = pk_str(&k);
        let sig = k.sign(&signed_message("testnet", "other.testnet", &pk, 1, 5000, ADV)).to_bytes().to_vec();
        as_caller(RELAYER);
        c.act(pk, 1, 5000, ADV.into(), sig.into());
    }

    #[test]
    #[should_panic(expected = "NON_TRANSFERABLE")]
    fn transfers_rejected() {
        let mut c = setup(1000);
        let a = player_account(&[1u8; 32]);
        let b = player_account(&[2u8; 32]);
        c.mint_pts(&a, 100, "t");
        let t = Nep245Transfer::single(a, b, PTS.to_string(), 10, None::<String>);
        let _ = Nep245Controller::transfer(&mut c, &t);
    }

    #[test]
    fn delete_account_consumes_nonce() {
        let mut c = setup(1000);
        let k = sk();
        call(&mut c, &k, 1, 5000, DELETE_ACCOUNT);
        assert_eq!(c.nonce_of(pk_str(&k)), 1);
    }

    fn to_midday(c: &mut Contract, k: &SigningKey) {
        call(c, k, 1, 5000, r#"{"type":"chama_create"}"#); // registers the player
        as_caller(RELAYER);
        c.advance_clock();
    }

    #[test]
    fn buy_at_midday_moves_pts_and_mirrors_token() {
        let mut c = setup(1000);
        let k = sk();
        to_midday(&mut c, &k);
        let buy = r#"{"good":"tomato","max_unit_price":100000,"merchant":"njeri","qty":3,"type":"buy"}"#;
        call(&mut c, &k, 2, 5000, buy);
        let pts = c.pts_of(pk_str(&k)).0;
        assert!(pts < 20_000);
        let who = player_account(&{
            let mut a = [0u8; 32];
            a.copy_from_slice(k.verifying_key().as_bytes());
            a
        });
        assert_eq!(Nep245Controller::balance_of(&c, PTS, &who), pts);
    }

    #[test]
    #[should_panic(expected = "WRONG_PHASE")]
    fn buy_at_dawn_rejected() {
        let mut c = setup(1000);
        let buy = r#"{"good":"tomato","max_unit_price":100000,"merchant":"njeri","qty":3,"type":"buy"}"#;
        call(&mut c, &sk(), 1, 5000, buy);
    }

    #[test]
    fn snapshot_matches_world_and_hash() {
        let c = setup(1000);
        let snap = c.world_snapshot().0;
        assert_eq!(snap, near_sdk::borsh::to_vec(&c.world).unwrap());
        let w: World = near_sdk::borsh::from_slice(&snap).unwrap();
        assert_eq!(w.day, c.world.day);
        assert_eq!(c.world_hash().len(), 32);
        assert_eq!(c.world_hash(), c.world_hash());
    }

    #[test]
    fn world_blob_size() {
        let mut c = setup(1000);
        for i in 0..MAX_PLAYERS {
            c.world.day = (i as u32) / MAX_NEW_PER_DAY; // stay under the daily new-player cap
            c.register(&player_account(&[(i % 250) as u8 + 1, (i / 250) as u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
        }
        let bytes = near_sdk::borsh::to_vec(&c.world).unwrap();
        println!("world borsh bytes with {} players: {}", c.world.players.len(), bytes.len());
        assert!(bytes.len() < 400_000);
    }

    #[test]
    #[should_panic(expected = "RATE_LIMITED")]
    fn daily_new_player_cap() {
        let mut c = setup(1000);
        for i in 0..=MAX_NEW_PER_DAY as u8 {
            c.register(&player_account(&[i + 1; 32]));
        }
    }

    // ---- inherited econ caps, exercised through signed `act` ----
    fn acct(k: &SigningKey) -> AccountId {
        player_account(k.verifying_key().as_bytes())
    }
    /// Registered player at midday with the given reputation score.
    fn midday_player(c: &mut Contract, k: &SigningKey, score: i32) {
        c.register(&acct(k));
        c.world.phase = Phase::Midday;
        c.world.players.get_mut(acct(k).as_str()).unwrap().score = score;
    }

    #[test]
    #[should_panic(expected = "CREDIT_DENIED")]
    fn sixth_open_loan_denied() {
        let mut c = setup(1000);
        let k = sk();
        midday_player(&mut c, &k, 15);
        let req = r#"{"good":"sukuma","merchant":"njeri","qty":1,"type":"credit_request"}"#;
        for n in 1..=5 {
            call(&mut c, &k, n, 5000, req);
        }
        assert_eq!(c.world.loans.len(), 5);
        call(&mut c, &k, 6, 5000, req);
    }

    #[test]
    #[should_panic(expected = "RATE_LIMITED")]
    fn sixth_investment_rate_limited() {
        let mut c = setup(1000);
        let k = sk();
        midday_player(&mut c, &k, 0);
        let inv = r#"{"merchant":"njeri","pts":100,"type":"invest"}"#;
        for n in 1..=5 {
            call(&mut c, &k, n, 5000, inv);
        }
        assert_eq!(c.world.investments.len(), 5);
        call(&mut c, &k, 6, 5000, inv);
    }

    fn guarantee_setup() -> (Contract, SigningKey, SigningKey) {
        let mut c = setup(1000);
        let (g, b) = (sk(), SigningKey::from_bytes(&[9u8; 32]));
        midday_player(&mut c, &g, 3); // tier 1 may guarantee
        midday_player(&mut c, &b, 0);
        for id in 1..=3u64 {
            c.world.loans.insert(id, econ::world::Loan {
                id, borrower: acct(&b).to_string(), lender: econ::world::Lender::Merchant("njeri".into()),
                merchant: "njeri".into(), good: "sukuma".into(), qty: 1, cost: 100, owed: 106, due_day: 5,
                guarantor: None, status: econ::credit::LoanStatus::Open,
            });
        }
        (c, g, b)
    }
    fn guarantee_json(b: &SigningKey, loan: u64) -> String {
        format!(r#"{{"borrower":"{}","loan_id":{loan},"type":"guarantee"}}"#, acct(b))
    }

    #[test]
    fn two_guarantees_allowed() {
        let (mut c, g, b) = guarantee_setup();
        call(&mut c, &g, 1, 5000, &guarantee_json(&b, 1));
        call(&mut c, &g, 2, 5000, &guarantee_json(&b, 2));
    }

    #[test]
    #[should_panic(expected = "CREDIT_DENIED")]
    fn third_guarantee_denied() {
        let (mut c, g, b) = guarantee_setup();
        for (n, l) in [(1, 1), (2, 2), (3, 3)] {
            call(&mut c, &g, n, 5000, &guarantee_json(&b, l));
        }
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn act_only_by_relayer() {
        let mut c = setup(1000);
        let k = sk();
        let pk = pk_str(&k);
        let sig = k.sign(&signed_message("testnet", CONTRACT, &pk, 1, 5000, DELETE_ACCOUNT)).to_bytes().to_vec();
        as_caller("mallory.testnet");
        c.act(pk, 1, 5000, DELETE_ACCOUNT.into(), sig.into());
    }

    #[test]
    fn rejected_action_keeps_nonce_state() {
        // Panics revert state on chain; here we check the rule path leaves nonce untouched before the check passes.
        let mut c = setup(1000);
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| call(&mut c, &sk(), 3, 999_999_999, DELETE_ACCOUNT)));
        assert!(r.is_err());
        assert_eq!(c.nonce_of(pk_str(&sk())), 0);
    }

    #[test]
    fn merchant_margin_clamped() {
        let mut c = setup(1000);
        testing_env!(VMContextBuilder::new().current_account_id(CONTRACT.parse().unwrap())
            .predecessor_account_id("njeri.npc.sokokuu.testnet".parse().unwrap()).build());
        c.decide("njeri".into(), 9_999);
        assert_eq!(c.world.merchants[c.world.merchant_idx("njeri").unwrap()].spread_bp, MAX_MARGIN_BP);
        c.decide("njeri".into(), 1);
        assert_eq!(c.world.merchants[c.world.merchant_idx("njeri").unwrap()].spread_bp, MIN_MARGIN_BP);
        c.crank("njeri".into());
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn decide_by_stranger_rejected() {
        let mut c = setup(1000);
        as_caller("mallory.testnet");
        c.decide("njeri".into(), 500);
    }

    // ---- rebind_key ----
    fn k2() -> SigningKey {
        SigningKey::from_bytes(&[9u8; 32])
    }
    fn registered_old(c: &mut Contract) -> SigningKey {
        let k = sk();
        call(c, &k, 1, 5000, r#"{"type":"chama_create"}"#);
        call(c, &k, 5, 5000, DELETE_ACCOUNT); // nonce floor 5
        k
    }
    fn as_relayer() {
        as_caller(RELAYER);
    }

    #[test]
    fn rebind_moves_player_nonce_and_balance() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        let pts = c.pts_of(pk_str(&old)).0;
        let id = acct(&old);
        as_relayer();
        c.rebind_key(pk_str(&old), pk_str(&k2()));
        assert_eq!(c.pts_of(pk_str(&k2())).0, pts);
        assert_eq!(c.pts_of(pk_str(&old)).0, 0);
        assert_eq!(c.nonce_of(pk_str(&k2())), 5);
        assert_eq!(Nep245Controller::balance_of(&c, PTS, &id), pts); // token balance stayed with the player id
        // new key continues from the old floor: 5 is rejected below, 6 works and acts as the same player
        call(&mut c, &k2(), 6, 5000, DELETE_ACCOUNT);
        assert_eq!(c.nonce_of(pk_str(&k2())), 6);
        assert_eq!(c.world.players.len(), 1);
    }

    #[test]
    #[should_panic(expected = "BAD_NONCE")]
    fn rebind_new_key_cannot_reuse_old_floor() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        as_relayer();
        c.rebind_key(pk_str(&old), pk_str(&k2()));
        call(&mut c, &k2(), 5, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn rebind_old_key_act_rejected() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        as_relayer();
        c.rebind_key(pk_str(&old), pk_str(&k2()));
        call(&mut c, &old, 6, 5000, DELETE_ACCOUNT);
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn rebind_old_key_cannot_reregister_as_new_player() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        as_relayer();
        c.rebind_key(pk_str(&old), pk_str(&k2()));
        call(&mut c, &old, 100, 5000, r#"{"type":"chama_create"}"#);
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn rebind_non_relayer_rejected() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        as_caller("mallory.testnet");
        c.rebind_key(pk_str(&old), pk_str(&k2()));
    }

    #[test]
    #[should_panic(expected = "NOT_MEMBER")]
    fn rebind_unknown_old_key_rejected() {
        let mut c = setup(1000);
        as_relayer();
        c.rebind_key(pk_str(&sk()), pk_str(&k2()));
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn rebind_to_key_with_player_rejected() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        call(&mut c, &k2(), 1, 5000, r#"{"type":"chama_create"}"#);
        as_relayer();
        c.rebind_key(pk_str(&old), pk_str(&k2()));
    }

    #[test]
    #[should_panic(expected = "FORBIDDEN")]
    fn rebind_blocked_when_paused() {
        let mut c = setup(1000);
        let old = registered_old(&mut c);
        let owner = c.owner.clone();
        as_caller(owner.as_str());
        c.pause();
        as_relayer();
        c.rebind_key(pk_str(&old), pk_str(&k2()));
    }

    #[test]
    fn burn_spends_pts() {
        let mut c = setup(1000);
        let a = player_account(&[1u8; 32]);
        c.mint_pts(&a, 100, "t");
        c.burn_pts(&a, 40, "sink");
        assert_eq!(Nep245Controller::balance_of(&c, PTS, &a), 60);
    }

    fn me(k: &SigningKey) -> AccountId {
        player_account(&k.verifying_key().to_bytes())
    }
    fn goods_total(c: &Contract, g: &str) -> u128 {
        c.world.players.values().map(|p| p.stock.get(g).copied().unwrap_or(0) as u128).sum()
    }

    #[test]
    fn buy_mints_goods_sell_burns_and_events_have_event_field() {
        let mut c = setup(1000);
        let k = sk();
        to_midday(&mut c, &k);
        near_sdk::test_utils::get_logs();
        call(&mut c, &k, 2, 5000, r#"{"good":"tomato","max_unit_price":100000,"merchant":"njeri","qty":3,"type":"buy"}"#);
        let logs = near_sdk::test_utils::get_logs().join("\n");
        println!("{logs}");
        assert!(logs.contains(r#""standard":"nep245""#) && logs.contains(r#""event":"mt_mint""#), "mint event must carry the event field");
        assert_eq!(c.mt_balance_of(me(&k), "tomato".into()).0, 3);
        assert_eq!(c.mt_supply("tomato".into()).unwrap().0, 3);
        call(&mut c, &k, 3, 5000, r#"{"good":"tomato","merchant":"njeri","qty":2,"type":"sell"}"#);
        let logs = near_sdk::test_utils::get_logs().join("\n");
        assert!(logs.contains(r#""event":"mt_burn""#), "{logs}");
        assert_eq!(c.mt_balance_of(me(&k), "tomato".into()).0, 1);
        assert_eq!(c.mt_supply("tomato".into()).unwrap().0, goods_total(&c, "tomato"));
    }

    #[test]
    fn spoilage_burns_goods_and_supply_mirrors_world() {
        let mut c = setup(1000);
        let k = sk();
        to_midday(&mut c, &k);
        call(&mut c, &k, 2, 5000, r#"{"good":"fish","max_unit_price":1000000,"merchant":"njeri","qty":2,"type":"buy"}"#);
        as_relayer();
        for _ in 0..6 {
            c.advance_clock();
        }
        for g in ["tomato", "maize", "sukuma", "onion", "fish", "charcoal"] {
            assert_eq!(c.mt_supply(g.into()).unwrap().0, goods_total(&c, g), "{g}");
        }
        let have = c.world.players[me(&k).as_str()].stock.get("fish").copied().unwrap_or(0) as u128;
        assert!(have < 2);
        assert_eq!(c.mt_balance_of(me(&k), "fish".into()).0, have);
    }

    #[test]
    fn goods_cannot_be_transferred() {
        let mut c = setup(1000);
        let k = sk();
        to_midday(&mut c, &k);
        call(&mut c, &k, 2, 5000, r#"{"good":"tomato","max_unit_price":100000,"merchant":"njeri","qty":3,"type":"buy"}"#);
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let t = Nep245Transfer::single(me(&k), "b.near".parse::<AccountId>().unwrap(), "tomato".to_string(), 1, None::<String>);
            let _ = Nep245Controller::transfer(&mut c, &t);
        }));
        assert!(r.is_err());
        assert_eq!(c.mt_balance_of(me(&k), "tomato".into()).0, 3);
    }

    #[test]
    fn token_views_and_metadata() {
        let c = setup(1000);
        let ids: Vec<String> = ["pts", "tomato", "nope"].iter().map(|s| s.to_string()).collect();
        let t = c.mt_token(ids.clone());
        assert!(t[0].is_some() && t[1].is_some() && t[2].is_none());
        let sup = c.mt_batch_supply(ids.clone());
        assert_eq!(sup[1].unwrap().0, 0);
        assert!(sup[2].is_none());
        let m = c.mt_metadata(ids);
        assert_eq!(m[1].as_ref().unwrap()["title"], "Tomatoes");
        assert_eq!(c.mt_metadata_contract()["spec"], "mt-1.0.0");
    }
}
