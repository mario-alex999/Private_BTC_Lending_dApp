use anyhow::Result;
use reqwest::Client;
use serde_json::Value;
use tokio::time::{sleep, Duration};

use crate::domain::lending::{self, default_oracle_price_18};
use crate::AppState;

#[derive(Clone)]
pub struct OracleAggregator {
    state: AppState,
    http: Client,
}

impl OracleAggregator {
    pub fn new(state: AppState) -> Self {
        Self {
            state,
            http: Client::new(),
        }
    }

    pub async fn run(&self) -> Result<()> {
        loop {
            if let Err(err) = self.refresh_all().await {
                tracing::error!(?err, "oracle refresh failed");
            }
            sleep(Duration::from_secs(
                self.state.cfg.oracle_refresh_interval_secs,
            ))
            .await;
        }
    }

    async fn refresh_all(&self) -> Result<()> {
        self.refresh_symbol("BTC", self.state.cfg.oracle_btc_feed_url.as_deref())
            .await?;
        self.refresh_symbol("ETH", self.state.cfg.oracle_eth_feed_url.as_deref())
            .await?;
        self.refresh_symbol("SOL", self.state.cfg.oracle_sol_feed_url.as_deref())
            .await?;
        self.refresh_symbol("BNB", self.state.cfg.oracle_bnb_feed_url.as_deref())
            .await?;
        self.refresh_symbol("XRP", self.state.cfg.oracle_xrp_feed_url.as_deref())
            .await?;
        self.refresh_symbol("TRX", self.state.cfg.oracle_trx_feed_url.as_deref())
            .await?;
        Ok(())
    }

    async fn refresh_symbol(&self, symbol: &str, feed_url: Option<&str>) -> Result<()> {
        let fallback = default_oracle_price_18(symbol).to_string();

        let price_18 = if let Some(url) = feed_url {
            match self.fetch_price_from_feed(url).await {
                Ok(price_float) => {
                    lending::to_price_18_from_float(price_float).unwrap_or(fallback.clone())
                }
                Err(err) => {
                    tracing::warn!(?err, symbol, "oracle feed fetch failed, using fallback");
                    fallback.clone()
                }
            }
        } else {
            fallback
        };

        lending::upsert_oracle_price_18(&self.state.db, symbol, &price_18, "aggregator").await
    }

    async fn fetch_price_from_feed(&self, url: &str) -> Result<f64> {
        let body = self
            .http
            .get(url)
            .send()
            .await?
            .error_for_status()?
            .json::<Value>()
            .await?;

        lending::parse_price_float(&body)
    }
}
