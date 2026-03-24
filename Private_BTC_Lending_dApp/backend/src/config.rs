use anyhow::{Context, Result};
use std::env;

#[derive(Debug, Clone)]
pub struct AppConfig {
    pub bind_address: String,
    pub database_url: String,
    pub herodotus_api_base: String,
    pub herodotus_api_key: String,
    pub starknet_rpc_url: String,
    pub hub_contract_address: String,
    pub reorg_poll_interval_secs: u64,
    pub listener_poll_interval_secs: u64,
    pub relayer_poll_interval_secs: u64,
    pub oracle_refresh_interval_secs: u64,
    pub oracle_btc_feed_url: Option<String>,
    pub oracle_eth_feed_url: Option<String>,
    pub oracle_sol_feed_url: Option<String>,
    pub oracle_bnb_feed_url: Option<String>,
    pub oracle_xrp_feed_url: Option<String>,
    pub oracle_trx_feed_url: Option<String>,
}

impl AppConfig {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            bind_address: env::var("BACKEND_BIND").unwrap_or_else(|_| "0.0.0.0:8080".to_string()),
            database_url: env::var("DATABASE_URL").context("DATABASE_URL missing")?,
            herodotus_api_base: env::var("HERODOTUS_API_BASE")
                .context("HERODOTUS_API_BASE missing")?,
            herodotus_api_key: env::var("HERODOTUS_API_KEY").unwrap_or_default(),
            starknet_rpc_url: env::var("STARKNET_RPC_URL").context("STARKNET_RPC_URL missing")?,
            hub_contract_address: env::var("LENDING_POOL_ADDRESS")
                .or_else(|_| env::var("HUB_CONTRACT_ADDRESS"))
                .context("LENDING_POOL_ADDRESS/HUB_CONTRACT_ADDRESS missing")?,
            reorg_poll_interval_secs: env::var("REORG_POLL_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
            listener_poll_interval_secs: env::var("LISTENER_POLL_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(5),
            relayer_poll_interval_secs: env::var("RELAYER_POLL_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(2),
            oracle_refresh_interval_secs: env::var("ORACLE_REFRESH_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
            oracle_btc_feed_url: env::var("ORACLE_BTC_FEED_URL")
                .ok()
                .filter(|v| !v.is_empty()),
            oracle_eth_feed_url: env::var("ORACLE_ETH_FEED_URL")
                .ok()
                .filter(|v| !v.is_empty()),
            oracle_sol_feed_url: env::var("ORACLE_SOL_FEED_URL")
                .ok()
                .filter(|v| !v.is_empty()),
            oracle_bnb_feed_url: env::var("ORACLE_BNB_FEED_URL")
                .ok()
                .filter(|v| !v.is_empty()),
            oracle_xrp_feed_url: env::var("ORACLE_XRP_FEED_URL")
                .ok()
                .filter(|v| !v.is_empty()),
            oracle_trx_feed_url: env::var("ORACLE_TRX_FEED_URL")
                .ok()
                .filter(|v| !v.is_empty()),
        })
    }
}
