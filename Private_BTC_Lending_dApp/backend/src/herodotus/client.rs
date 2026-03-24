use anyhow::Result;
use reqwest::Client;
use serde_json::json;

use crate::types::DepositEvent;

#[derive(Clone)]
pub struct HerodotusClient {
    base_url: String,
    api_key: String,
    http: Client,
}

impl HerodotusClient {
    pub fn new(base_url: String, api_key: String) -> Self {
        Self {
            base_url,
            api_key,
            http: Client::new(),
        }
    }

    pub async fn request_storage_proof(&self, deposit: &DepositEvent) -> Result<String> {
        let payload = json!({
            "chain_id": deposit.chain_id,
            "tx_hash": deposit.tx_hash,
            "deposit_id": deposit.deposit_id,
        });

        let mut req = self
            .http
            .post(format!("{}/proof-jobs", self.base_url))
            .json(&payload);

        if !self.api_key.is_empty() {
            req = req.header("x-api-key", self.api_key.clone());
        }

        let _ = req.send().await?;
        Ok(format!("proof-job:{}", deposit.deposit_id))
    }
}
