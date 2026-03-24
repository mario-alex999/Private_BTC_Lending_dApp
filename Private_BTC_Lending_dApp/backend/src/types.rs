use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SourceChain {
    Ethereum,
    Bnb,
    Solana,
    Xrp,
    Tron,
    Bitcoin,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepositEvent {
    pub deposit_id: String,
    pub chain: SourceChain,
    pub chain_id: u64,
    pub asset_id: u8,
    pub amount_native_18: String,
    pub starknet_user_hash: String,
    pub tx_hash: String,
    pub block_number: u64,
    pub observed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WitnessResponse {
    pub user: String,
    pub chain_id: u64,
    pub pool_liquidity_usd_18: String,
    pub base_rate_wad: String,
    pub utilization_wad: String,
    pub merkle_path: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackendEvent {
    pub kind: String,
    pub deposit_id: Option<String>,
    pub chain_id: Option<u64>,
    pub message: String,
}
