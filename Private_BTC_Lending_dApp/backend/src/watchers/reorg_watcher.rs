use anyhow::Result;
use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use tokio::time::{sleep, Duration};

use crate::types::BackendEvent;
use crate::AppState;

#[derive(Clone)]
pub struct ReorgWatcher {
    state: AppState,
}

impl ReorgWatcher {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }

    pub async fn run(&self) -> Result<()> {
        loop {
            // Placeholder logic:
            // In production, fetch latest indexed deposits, compare canonical blocks,
            // and freeze any affected deposit if a deep reorg is detected.
            sleep(Duration::from_secs(self.state.cfg.reorg_poll_interval_secs)).await;
        }
    }

    pub async fn freeze_on_reorg(&self, chain_id: u64, deposit_id: &str) -> Result<()> {
        self.state.hub.freeze_deposit(deposit_id).await?;
        sqlx::query(
            r#"
            UPDATE deposits
            SET status = 'reorged',
                updated_at = NOW()
            WHERE deposit_id = $1
            "#,
        )
        .bind(deposit_id)
        .execute(&self.state.db)
        .await?;

        sqlx::query(
            r#"
            UPDATE positions p
            SET is_frozen = TRUE,
                updated_at = NOW()
            WHERE p.chain_id = $1
              AND EXISTS (
                SELECT 1
                FROM deposits d
                WHERE d.deposit_id = $2
                  AND d.user_id = p.user_id
              )
            "#,
        )
        .bind(chain_id as i64)
        .bind(deposit_id)
        .execute(&self.state.db)
        .await?;

        let _ = self.state.events.send(BackendEvent {
            kind: "reorg_freeze".to_string(),
            deposit_id: Some(deposit_id.to_string()),
            chain_id: Some(chain_id),
            message: "deep reorg detected, borrowing frozen".to_string(),
        });

        Ok(())
    }
}

#[derive(Debug, Deserialize)]
pub struct ManualFreezeRequest {
    pub chain_id: u64,
    pub deposit_id: String,
}

pub async fn manual_freeze(
    State(state): State<crate::AppState>,
    Json(req): Json<ManualFreezeRequest>,
) -> impl IntoResponse {
    let watcher = ReorgWatcher::new(state.clone());
    let result = watcher.freeze_on_reorg(req.chain_id, &req.deposit_id).await;

    match result {
        Ok(_) => Json(json!({"ok": true, "frozen": req.deposit_id})),
        Err(err) => Json(json!({"ok": false, "error": err.to_string()})),
    }
}
