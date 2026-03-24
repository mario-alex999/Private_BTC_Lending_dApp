use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::extract::ws::{Message, WebSocket};
use axum::extract::{Path, Query, State, WebSocketUpgrade};
use axum::response::{IntoResponse, Json, Response};
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::json;

use crate::api::graphql::build_schema;
use crate::domain::lending::{
    self, EnqueueProofRelayInput, EnqueueProofRelayResult, IndexerBalances,
};
use crate::types::WitnessResponse;
use crate::AppState;

pub async fn health() -> impl IntoResponse {
    Json(json!({ "ok": true }))
}

pub async fn witness_for_user(
    State(state): State<AppState>,
    Path(user): Path<String>,
) -> impl IntoResponse {
    let _ = state;
    Json(WitnessResponse {
        user,
        chain_id: 1,
        pool_liquidity_usd_18: "1000000000000000000000000".to_string(),
        base_rate_wad: "50000000000000000".to_string(),
        utilization_wad: "430000000000000000".to_string(),
        merkle_path: vec!["0xabc".to_string(), "0xdef".to_string()],
    })
}

pub async fn stream_ws(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    ws.on_upgrade(move |socket| stream_events(socket, state))
}

async fn stream_events(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();
    let mut event_rx = state.events.subscribe();

    tokio::spawn(async move {
        while let Some(msg) = receiver.next().await {
            if msg.is_err() {
                break;
            }
        }
    });

    while let Ok(evt) = event_rx.recv().await {
        let payload = serde_json::to_string(&evt).unwrap_or_else(|_| "{}".to_string());
        if sender.send(Message::Text(payload.into())).await.is_err() {
            break;
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct BorrowLimitQuery {
    pub address: String,
    pub chain_id: i64,
    pub asset_id: i16,
}

#[derive(Debug, Deserialize)]
pub struct IndexerBalancesQuery {
    pub address: String,
}

#[derive(Debug, Deserialize)]
pub struct ProofRelayJobRequest {
    pub request_id: String,
    pub starknet_address: String,
    pub chain_id: i64,
    pub asset_id: i16,
    pub public_input_hash: String,
    pub proof_payload: Vec<String>,
}

pub async fn latest_oracles(State(state): State<AppState>) -> impl IntoResponse {
    match lending::get_latest_oracle_bundle(&state.db).await {
        Ok(bundle) => Json(json!({
            "btc": bundle.btc,
            "eth": bundle.eth,
            "sol": bundle.sol,
            "bnb": bundle.bnb,
            "xrp": bundle.xrp,
            "trx": bundle.trx,
            "updated_at": bundle.updated_at.to_rfc3339(),
        })),
        Err(err) => Json(json!({
            "error": err.to_string()
        })),
    }
}

pub async fn borrow_limit(
    State(state): State<AppState>,
    Query(params): Query<BorrowLimitQuery>,
) -> impl IntoResponse {
    match lending::get_borrow_limit(&state.db, &params.address, params.chain_id, params.asset_id)
        .await
    {
        Ok(limit) => Json(json!({
            "address": limit.starknet_address,
            "chain_id": limit.chain_id,
            "asset_id": limit.asset_id,
            "collateral_usd_18": limit.collateral_usd_18,
            "debt_usd_18": limit.debt_usd_18,
            "max_borrowable_usd_18": limit.max_borrowable_usd_18,
            "available_borrow_usd_18": limit.available_borrow_usd_18,
            "health_factor_wad": limit.health_factor_wad,
            "privacy_mode": limit.privacy_mode,
        })),
        Err(err) => Json(json!({
            "error": err.to_string(),
        })),
    }
}

pub async fn indexer_balances(
    State(state): State<AppState>,
    Query(params): Query<IndexerBalancesQuery>,
) -> impl IntoResponse {
    let balances = lending::get_indexer_balances(&state.db, &params.address)
        .await
        .unwrap_or(IndexerBalances {
            eth: "0.0000".to_string(),
            bnb: "0.0000".to_string(),
            sol: "0.0000".to_string(),
            xrp: "0.0000".to_string(),
            trx: "0.0000".to_string(),
        });

    Json(json!({
        "ETH": balances.eth,
        "BNB": balances.bnb,
        "SOL": balances.sol,
        "XRP": balances.xrp,
        "TRX": balances.trx,
    }))
}

pub async fn enqueue_proof_relay_job(
    State(state): State<AppState>,
    Json(payload): Json<ProofRelayJobRequest>,
) -> impl IntoResponse {
    let input = EnqueueProofRelayInput {
        request_id: payload.request_id,
        starknet_address: payload.starknet_address,
        chain_id: payload.chain_id,
        asset_id: payload.asset_id,
        public_input_hash: payload.public_input_hash,
        proof_payload: json!(payload.proof_payload),
        target_contract: state.cfg.hub_contract_address.clone(),
        calldata: json!({
            "chain_id": payload.chain_id,
            "asset_id": payload.asset_id,
        }),
    };

    let result: Result<EnqueueProofRelayResult, _> =
        lending::enqueue_proof_relay_job(&state.db, input).await;

    match result {
        Ok(job) => Json(json!({
            "job_id": job.job_id,
            "status": job.status
        })),
        Err(err) => Json(json!({
            "error": err.to_string()
        })),
    }
}

pub async fn graphql_endpoint(
    State(state): State<AppState>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    let schema = build_schema(state);
    schema.execute(req.into_inner()).await.into()
}
