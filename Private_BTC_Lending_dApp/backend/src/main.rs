mod api;
mod chain;
mod config;
mod domain;
mod herodotus;
mod relayer;
mod starknet;
mod types;
mod watchers;

use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Result;
use axum::Router;
use config::AppConfig;
use relayer::worker::ProofRelayWorker;
use sqlx::postgres::PgPoolOptions;
use tokio::sync::broadcast;
use tracing::info;
use watchers::oracle_aggregator::OracleAggregator;
use watchers::reorg_watcher::ReorgWatcher;

use crate::chain::listener::CrossChainListener;
use crate::herodotus::client::HerodotusClient;
use crate::starknet::hub_client::HubClient;

#[derive(Clone)]
pub struct AppState {
    pub cfg: Arc<AppConfig>,
    pub db: sqlx::PgPool,
    pub events: broadcast::Sender<types::BackendEvent>,
    pub herodotus: HerodotusClient,
    pub hub: HubClient,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cfg = Arc::new(AppConfig::from_env()?);
    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&cfg.database_url)
        .await?;
    run_migrations(&db).await?;
    let (events_tx, _) = broadcast::channel::<types::BackendEvent>(1024);

    let state = AppState {
        cfg: cfg.clone(),
        db: db.clone(),
        events: events_tx.clone(),
        herodotus: HerodotusClient::new(
            cfg.herodotus_api_base.clone(),
            cfg.herodotus_api_key.clone(),
        ),
        hub: HubClient::new(
            cfg.starknet_rpc_url.clone(),
            cfg.hub_contract_address.clone(),
        ),
    };

    let listener = CrossChainListener::new(state.clone());
    let watcher = ReorgWatcher::new(state.clone());
    let relayer_worker = ProofRelayWorker::new(state.clone());
    let oracle_aggregator = OracleAggregator::new(state.clone());

    tokio::spawn(async move {
        if let Err(err) = listener.run().await {
            tracing::error!(?err, "cross-chain listener exited with error");
        }
    });

    tokio::spawn(async move {
        if let Err(err) = watcher.run().await {
            tracing::error!(?err, "reorg watcher exited with error");
        }
    });

    tokio::spawn(async move {
        if let Err(err) = relayer_worker.run().await {
            tracing::error!(?err, "proof relay worker exited with error");
        }
    });

    tokio::spawn(async move {
        if let Err(err) = oracle_aggregator.run().await {
            tracing::error!(?err, "oracle aggregator exited with error");
        }
    });

    let app: Router = api::router(state);
    let addr: SocketAddr = cfg.bind_address.parse()?;

    info!(%addr, "backend listening");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn run_migrations(db: &sqlx::PgPool) -> Result<()> {
    let migration = include_str!("../migrations/0001_multichain_private_lending.sql");

    for statement in migration
        .split(';')
        .map(str::trim)
        .filter(|segment| !segment.is_empty())
    {
        sqlx::query(statement).execute(db).await?;
    }

    Ok(())
}
