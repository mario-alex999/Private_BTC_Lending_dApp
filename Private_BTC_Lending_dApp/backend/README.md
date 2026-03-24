# Multi-Chain Indexer + Relayer (Rust)

This service provides:

- Cross-chain deposit listener
- Herodotus proof-job trigger
- GraphQL query/mutation API for positions and borrow limit
- Witness API for local ZK proving
- Proof relay queue worker (`queued -> processing -> confirmed/deadletter`)
- Oracle aggregator cache with 10-second TTL refresh
- Reorg watcher that can freeze deposit borrowing on Starknet
- WebSocket stream for frontend status updates

## Run

```bash
cd backend
cargo run
```

## Required env

- `DATABASE_URL`
- `HERODOTUS_API_BASE`
- `STARKNET_RPC_URL`
- `LENDING_POOL_ADDRESS` (or `HUB_CONTRACT_ADDRESS`)

Optional:

- `HERODOTUS_API_KEY`
- `BACKEND_BIND`
- `REORG_POLL_INTERVAL_SECS`
- `LISTENER_POLL_INTERVAL_SECS`
- `RELAYER_POLL_INTERVAL_SECS`
- `ORACLE_REFRESH_INTERVAL_SECS`
- `ORACLE_BTC_FEED_URL`
- `ORACLE_ETH_FEED_URL`
- `ORACLE_SOL_FEED_URL`
- `ORACLE_BNB_FEED_URL`
- `ORACLE_XRP_FEED_URL`
- `ORACLE_TRX_FEED_URL`
