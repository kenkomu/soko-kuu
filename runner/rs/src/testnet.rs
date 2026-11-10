//! Real NEAR testnet adapter: the relayer account signs and pays gas for `act` on the contract.
//! Env: RELAYER_ACCOUNT_ID, RELAYER_KEY_FILE (path), CONTRACT_ID, NEAR_RPC_URL.
use crate::chain::Chain;
use std::collections::HashMap;
use std::sync::Arc;

#[cfg(not(feature = "testnet"))]
pub async fn connect(_env: &HashMap<String, String>) -> Result<Arc<dyn Chain>, String> {
    Err("testnet support not compiled in (build with --features testnet)".into())
}

/// Key source: RELAYER_KEY_FILE (path to a file holding `ed25519:...` or a near-cli credentials JSON with
/// `private_key`) is preferred; RELAYER_PRIVATE_KEY (the value itself) is a fallback for secret stores.
#[cfg(feature = "testnet")]
fn relayer_key(env: &HashMap<String, String>) -> Result<String, String> {
    if let Some(path) = env.get("RELAYER_KEY_FILE").filter(|v| !v.is_empty()) {
        let raw = std::fs::read_to_string(path).map_err(|e| format!("cannot read RELAYER_KEY_FILE {path}: {e}"))?;
        let t = raw.trim();
        if t.starts_with('{') {
            let v: serde_json::Value = serde_json::from_str(t).map_err(|_| "RELAYER_KEY_FILE is not valid JSON".to_string())?;
            let k = v.get("private_key").or_else(|| v.get("secret_key")).and_then(|k| k.as_str());
            return k.map(str::to_owned).ok_or_else(|| "RELAYER_KEY_FILE JSON has no private_key".to_string());
        }
        return Ok(t.to_owned());
    }
    env.get("RELAYER_PRIVATE_KEY").filter(|v| !v.is_empty()).cloned().ok_or_else(|| "RELAYER_KEY_FILE is required".to_string())
}

#[cfg(feature = "testnet")]
pub async fn connect(env: &HashMap<String, String>) -> Result<Arc<dyn Chain>, String> {
    let get = |k: &str| env.get(k).filter(|v| !v.is_empty()).cloned().ok_or_else(|| format!("{k} is required"));
    let account = get("RELAYER_ACCOUNT_ID")?;
    let key = relayer_key(env)?;
    let contract = get("CONTRACT_ID")?;
    let url = env.get("NEAR_RPC_URL").filter(|v| !v.is_empty()).cloned().unwrap_or_else(|| "https://rpc.testnet.near.org".into());
    let c = imp::NearChain::new(&url, &account, &key, &contract, env.get("GAS_TGAS").and_then(|g| g.parse().ok()).unwrap_or(100).min(300))?;
    c.ping().await?;
    Ok(Arc::new(c))
}

#[cfg(feature = "testnet")]
mod imp {
    use crate::chain::{parse_chain_error, Chain, ChainError, SubmitReq};
    use async_trait::async_trait;
    use near_jsonrpc_client::{methods, JsonRpcClient};
    use near_jsonrpc_primitives::types::query::QueryResponseKind;
    use near_primitives::gas::Gas;
    use near_primitives::transaction::{Action, FunctionCallAction, Transaction, TransactionV0};
    use near_primitives::types::{AccountId, Balance, BlockReference, FunctionArgs};
    use near_primitives::views::{FinalExecutionStatus, QueryRequest};
    use serde_json::json;

    pub struct NearChain {
        client: JsonRpcClient,
        signer: near_crypto::Signer,
        account: AccountId,
        contract: AccountId,
        /// serialises relayer transactions so access-key nonces stay in order
        tx_lock: tokio::sync::Mutex<()>,
        /// gas cap per call (Tgas), env GAS_TGAS, default 100
        gas_tgas: u64,
    }

    impl NearChain {
        pub fn new(url: &str, account: &str, secret: &str, contract: &str, gas_tgas: u64) -> Result<Self, String> {
            let account: AccountId = account.parse().map_err(|e| format!("bad RELAYER_ACCOUNT_ID: {e}"))?;
            let contract: AccountId = contract.parse().map_err(|e| format!("bad CONTRACT_ID: {e}"))?;
            let sk: near_crypto::SecretKey = secret.parse().map_err(|_| "bad RELAYER_PRIVATE_KEY".to_string())?;
            let signer = near_crypto::InMemorySigner::from_secret_key(account.clone(), sk);
            Ok(NearChain { client: JsonRpcClient::connect(url), signer, account, contract, tx_lock: tokio::sync::Mutex::new(()), gas_tgas })
        }
        /// Relayer account balance in yoctoNEAR (None if unreachable).
        pub async fn balance(&self) -> Option<u128> {
            let r = self.client.call(methods::query::RpcQueryRequest {
                block_reference: BlockReference::latest(),
                request: QueryRequest::ViewAccount { account_id: self.account.clone() },
            }).await.ok()?;
            match r.kind { QueryResponseKind::ViewAccount(a) => Some(a.amount.as_yoctonear()), _ => None }
        }
        /// Call a no-argument view; None on any error (older contract without the view, RPC trouble).
        async fn view(&self, method: &str) -> Option<serde_json::Value> {
            let r = self.client.call(methods::query::RpcQueryRequest {
                block_reference: BlockReference::latest(),
                request: QueryRequest::CallFunction { account_id: self.contract.clone(), method_name: method.into(), args: FunctionArgs::from(b"{}".to_vec()) },
            }).await.ok()?;
            match r.kind { QueryResponseKind::CallResult(c) => serde_json::from_slice(&c.result).ok(), _ => None }
        }
        pub async fn ping(&self) -> Result<(), String> {
            self.access_key().await.map(|_| ()).map_err(|e| format!("relayer key not usable: {e}"))
        }
        /// Sign and send one relayer function call; contract panics map to `Reject`, transport trouble to `Down`.
        async fn relay(&self, method: &str, args: Vec<u8>) -> Result<String, ChainError> {
            let _g = self.tx_lock.lock().await;
            let (nonce, block_hash) = self.access_key().await.map_err(ChainError::Down)?;
            let tx = TransactionV0 {
                signer_id: self.account.clone(), public_key: self.signer.public_key().clone(), nonce: nonce + 1,
                receiver_id: self.contract.clone(), block_hash,
                actions: vec![Action::FunctionCall(Box::new(FunctionCallAction {
                    method_name: method.into(), args, gas: Gas::from_teragas(self.gas_tgas), deposit: Balance::ZERO,
                }))],
            };
            let out = self.client.call(methods::broadcast_tx_commit::RpcBroadcastTxCommitRequest { signed_transaction: Transaction::V0(tx).sign(&self.signer) })
                .await.map_err(|e| ChainError::Down(e.to_string()))?;
            match &out.status {
                FinalExecutionStatus::SuccessValue(_) => Ok(out.transaction.hash.to_string()),
                other => { let t = format!("{other:?}"); Err(parse_chain_error(&t).unwrap_or(ChainError::Down(t.chars().take(200).collect()))) }
            }
        }
        async fn access_key(&self) -> Result<(u64, near_primitives::hash::CryptoHash), String> {
            let r = self.client.call(methods::query::RpcQueryRequest {
                block_reference: BlockReference::latest(),
                request: QueryRequest::ViewAccessKey { account_id: self.account.clone(), public_key: self.signer.public_key().clone() },
            }).await.map_err(|e| e.to_string())?;
            match r.kind { QueryResponseKind::AccessKey(k) => Ok((k.nonce, r.block_hash)), _ => Err("unexpected access key response".into()) }
        }
    }

    #[async_trait]
    impl Chain for NearChain {
        async fn submit(&self, req: &SubmitReq) -> Result<String, ChainError> {
            let args = json!({"pubkey": req.pubkey, "nonce": req.nonce, "expires_ms": req.expires_ms, "action": req.action, "sig": req.sig});
            self.relay("act", args.to_string().into_bytes()).await
        }
        async fn advance_clock(&self) -> Result<String, ChainError> { self.relay("advance_clock", b"{}".to_vec()).await }
        async fn rebind_key(&self, old: &str, new: &str) -> Result<String, ChainError> {
            self.relay("rebind_key", json!({"old_pubkey": old, "new_pubkey": new}).to_string().into_bytes()).await
        }
        async fn balance_yocto(&self) -> Option<u128> { self.balance().await }
        async fn pts_of(&self, pubkey: &str) -> Option<u64> {
            let r = self.client.call(methods::query::RpcQueryRequest {
                block_reference: BlockReference::latest(),
                request: QueryRequest::CallFunction {
                    account_id: self.contract.clone(), method_name: "pts_of".into(),
                    args: FunctionArgs::from(json!({"pubkey": pubkey}).to_string().into_bytes()),
                },
            }).await.ok()?;
            match r.kind { QueryResponseKind::CallResult(c) => serde_json::from_slice::<serde_json::Value>(&c.result).ok().and_then(|v| v.as_u64().or_else(|| v.as_str().and_then(|s| s.parse().ok()))), _ => None }
        }
        async fn world_hash(&self) -> Option<String> {
            let v = self.view("world_hash").await?;
            v.as_str().map(str::to_owned)
        }
        async fn world_snapshot(&self) -> Option<Vec<u8>> {
            use base64::Engine as _;
            let v = self.view("world_snapshot").await?;
            base64::engine::general_purpose::STANDARD.decode(v.as_str()?).ok()
        }
        async fn chain_clock(&self) -> Option<(u32, String)> {
            let r = self.client.call(methods::query::RpcQueryRequest {
                block_reference: BlockReference::latest(),
                request: QueryRequest::CallFunction { account_id: self.contract.clone(), method_name: "clock".into(), args: FunctionArgs::from(b"{}".to_vec()) },
            }).await.ok()?;
            let QueryResponseKind::CallResult(c) = r.kind else { return None };
            let v: serde_json::Value = serde_json::from_slice(&c.result).ok()?;
            Some((v.get(0)?.as_u64()? as u32, v.get(1)?.as_str()?.to_lowercase()))
        }
        async fn nonce_of(&self, pubkey: &str) -> Option<u64> {
            let r = self.client.call(methods::query::RpcQueryRequest {
                block_reference: BlockReference::latest(),
                request: QueryRequest::CallFunction {
                    account_id: self.contract.clone(), method_name: "nonce_of".into(),
                    args: FunctionArgs::from(json!({"pubkey": pubkey}).to_string().into_bytes()),
                },
            }).await.ok()?;
            match r.kind { QueryResponseKind::CallResult(c) => serde_json::from_slice::<serde_json::Value>(&c.result).ok().and_then(|v| v.as_u64().or_else(|| v.as_str().and_then(|s| s.parse().ok()))), _ => None }
        }
    }
}
