use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofRelayJob {
    pub id: Uuid,
    pub request_id: String,
    pub user_id: Uuid,
    pub chain_id: i64,
    pub asset_id: i16,
    pub public_input_hash: String,
    pub proof_payload: serde_json::Value,
    pub target_contract: String,
    pub calldata: serde_json::Value,
    pub status: String,
    pub retry_count: i32,
    pub max_retries: i32,
}

pub struct ProofRelayQueue {
    db: PgPool,
}

impl ProofRelayQueue {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn dequeue_next(&self) -> Result<Option<ProofRelayJob>> {
        let mut tx = self.db.begin().await?;

        let row = sqlx::query(
            r#"
            SELECT
                id,
                request_id,
                user_id,
                chain_id,
                asset_id,
                public_input_hash,
                proof_payload,
                target_contract,
                calldata,
                status,
                retry_count,
                max_retries
            FROM proof_relay_jobs
            WHERE status = 'queued'
            ORDER BY created_at ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
            "#,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let Some(row) = row else {
            tx.commit().await?;
            return Ok(None);
        };

        let id = row.get::<Uuid, _>("id");

        sqlx::query(
            r#"
            UPDATE proof_relay_jobs
            SET status = 'processing',
                updated_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        Ok(Some(ProofRelayJob {
            id,
            request_id: row.get("request_id"),
            user_id: row.get("user_id"),
            chain_id: row.get("chain_id"),
            asset_id: row.get("asset_id"),
            public_input_hash: row.get("public_input_hash"),
            proof_payload: row.get("proof_payload"),
            target_contract: row.get("target_contract"),
            calldata: row.get("calldata"),
            status: "processing".to_string(),
            retry_count: row.get("retry_count"),
            max_retries: row.get("max_retries"),
        }))
    }

    pub async fn mark_confirmed(&self, job_id: Uuid, tx_hash: &str) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE proof_relay_jobs
            SET status = 'confirmed',
                tx_hash = $2,
                updated_at = NOW(),
                error_message = NULL
            WHERE id = $1
            "#,
        )
        .bind(job_id)
        .bind(tx_hash)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    pub async fn mark_failed(&self, job_id: Uuid, error: &str) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE proof_relay_jobs
            SET
                retry_count = retry_count + 1,
                status = CASE
                    WHEN retry_count + 1 >= max_retries THEN 'deadletter'
                    ELSE 'queued'
                END,
                error_message = $2,
                updated_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(job_id)
        .bind(error)
        .execute(&self.db)
        .await?;

        Ok(())
    }
}
