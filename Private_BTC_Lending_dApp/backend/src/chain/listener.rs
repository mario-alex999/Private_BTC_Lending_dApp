use anyhow::Result;
use chrono::Utc;
use tokio::time::{sleep, Duration};

use crate::domain::lending;
use crate::types::{BackendEvent, DepositEvent, SourceChain};
use crate::AppState;

#[derive(Clone)]
pub struct CrossChainListener {
    state: AppState,
}

impl CrossChainListener {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }

    pub async fn run(&self) -> Result<()> {
        loop {
            let events = self.poll_mock_events().await;
            for ev in events {
                self.process_deposit(ev).await?;
            }
            sleep(Duration::from_secs(
                self.state.cfg.listener_poll_interval_secs,
            ))
            .await;
        }
    }

    async fn process_deposit(&self, event: DepositEvent) -> Result<()> {
        let _job_id = self.state.herodotus.request_storage_proof(&event).await?;
        self.persist_deposit(&event).await?;

        let _ = self.state.events.send(BackendEvent {
            kind: "deposit_detected".to_string(),
            deposit_id: Some(event.deposit_id.clone()),
            chain_id: Some(event.chain_id),
            message: format!("deposit detected on chain {}", event.chain_id),
        });

        Ok(())
    }

    async fn persist_deposit(&self, event: &DepositEvent) -> Result<()> {
        let user_id = lending::ensure_user(&self.state.db, &event.starknet_user_hash).await?;
        let finality_target = finality_target_by_chain(event.chain_id);

        sqlx::query(
            r#"
            INSERT INTO deposits
                (deposit_id, user_id, chain_id, asset_id, tx_hash, block_number, amount_native_18, confirmation_depth, finality_target, status, proof_job_id)
            VALUES
                ($1, $2, $3, $4, $5, $6, $7::numeric, 0, $8, 'detected', $9)
            ON CONFLICT (deposit_id)
            DO UPDATE SET
                tx_hash = EXCLUDED.tx_hash,
                block_number = EXCLUDED.block_number,
                amount_native_18 = EXCLUDED.amount_native_18,
                updated_at = NOW()
            "#,
        )
        .bind(&event.deposit_id)
        .bind(user_id)
        .bind(event.chain_id as i64)
        .bind(event.asset_id as i16)
        .bind(&event.tx_hash)
        .bind(event.block_number as i64)
        .bind(&event.amount_native_18)
        .bind(finality_target)
        .bind(format!("proof-job:{}", event.deposit_id))
        .execute(&self.state.db)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO positions
                (user_id, chain_id, asset_id, collateral_amount_18, debt_usd_18, privacy_mode_enabled, health_factor_wad, liquidation_threshold_bps, max_ltv_bps)
            VALUES
                ($1, $2, $3, $4::numeric, 0, TRUE, 99000000000000000000, $5, $6)
            ON CONFLICT (user_id, chain_id, asset_id)
            DO UPDATE SET
                collateral_amount_18 = positions.collateral_amount_18 + EXCLUDED.collateral_amount_18,
                updated_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(event.chain_id as i64)
        .bind(event.asset_id as i16)
        .bind(&event.amount_native_18)
        .bind(lending::default_liquidation_threshold_bps(event.asset_id as i16))
        .bind(lending::default_max_ltv_bps(event.asset_id as i16))
        .execute(&self.state.db)
        .await?;

        let _ = sqlx::query(
            r#"
            UPDATE deposits
            SET confirmation_depth = confirmation_depth + 1,
                status = CASE
                    WHEN confirmation_depth + 1 >= finality_target THEN 'finalized'
                    ELSE status
                END,
                updated_at = NOW()
            WHERE deposit_id = $1
            "#,
        )
        .bind(&event.deposit_id)
        .execute(&self.state.db)
        .await?;

        Ok(())
    }

    async fn poll_mock_events(&self) -> Vec<DepositEvent> {
        let _ = &self.state;
        vec![DepositEvent {
            deposit_id: format!("mock-{}", Utc::now().timestamp()),
            chain: SourceChain::Ethereum,
            chain_id: 1,
            asset_id: 1,
            amount_native_18: "1000000000000000000".to_string(),
            starknet_user_hash: "0x123".to_string(),
            tx_hash: "0xabc".to_string(),
            block_number: 0,
            observed_at: Utc::now(),
        }]
    }
}

fn finality_target_by_chain(chain_id: u64) -> i32 {
    match chain_id {
        1 => 64,         // Ethereum
        56 => 15,        // BNB
        1399811149 => 1, // Solana
        144 => 3,        // XRP
        728126428 => 20, // TRON
        _ => 12,
    }
}
