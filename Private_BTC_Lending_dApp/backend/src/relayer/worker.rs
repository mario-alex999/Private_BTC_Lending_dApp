use anyhow::Result;
use tokio::time::{sleep, Duration};

use crate::relayer::queue::ProofRelayQueue;
use crate::types::BackendEvent;
use crate::AppState;

#[derive(Clone)]
pub struct ProofRelayWorker {
    state: AppState,
}

impl ProofRelayWorker {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }

    pub async fn run(&self) -> Result<()> {
        let queue = ProofRelayQueue::new(self.state.db.clone());

        loop {
            match queue.dequeue_next().await {
                Ok(Some(job)) => {
                    let submit_result = self
                        .state
                        .hub
                        .submit_proof_relay(
                            job.chain_id as u64,
                            job.asset_id as u16,
                            &job.public_input_hash,
                            &job.proof_payload,
                            &job.calldata,
                            &job.target_contract,
                        )
                        .await;

                    match submit_result {
                        Ok(tx_hash) => {
                            queue.mark_confirmed(job.id, &tx_hash).await?;
                            let _ = self.state.events.send(BackendEvent {
                                kind: "proof_relay_confirmed".to_string(),
                                deposit_id: Some(job.request_id.clone()),
                                chain_id: Some(job.chain_id as u64),
                                message: format!("proof relay confirmed: {tx_hash}"),
                            });
                        }
                        Err(err) => {
                            queue.mark_failed(job.id, &err.to_string()).await?;
                            let _ = self.state.events.send(BackendEvent {
                                kind: "proof_relay_failed".to_string(),
                                deposit_id: Some(job.request_id.clone()),
                                chain_id: Some(job.chain_id as u64),
                                message: err.to_string(),
                            });
                        }
                    }
                }
                Ok(None) => {
                    sleep(Duration::from_secs(
                        self.state.cfg.relayer_poll_interval_secs,
                    ))
                    .await;
                }
                Err(err) => {
                    tracing::error!(?err, "proof relay queue polling failed");
                    sleep(Duration::from_secs(
                        self.state.cfg.relayer_poll_interval_secs,
                    ))
                    .await;
                }
            }
        }
    }
}
