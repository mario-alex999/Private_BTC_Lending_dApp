use axum::routing::{get, post};
use axum::Router;

use crate::api::routes::{
    borrow_limit, enqueue_proof_relay_job, graphql_endpoint, health, indexer_balances,
    latest_oracles, stream_ws, witness_for_user,
};
use crate::AppState;

pub mod graphql;
pub mod routes;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/graphql", post(graphql_endpoint))
        .route("/api/witness/:user", get(witness_for_user))
        .route("/api/oracles/latest", get(latest_oracles))
        .route("/api/indexer/balances", get(indexer_balances))
        .route("/api/borrow-limit", get(borrow_limit))
        .route("/api/proof-relay/jobs", post(enqueue_proof_relay_job))
        .route("/ws/events", get(stream_ws))
        .route(
            "/api/reorg/freeze",
            post(crate::watchers::reorg_watcher::manual_freeze),
        )
        .with_state(state)
}
