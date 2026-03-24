# Data & Intelligence API Specification

## GraphQL Endpoint

- `POST /graphql`
- schema: `backend/schema.graphql`
- resolver implementation: `backend/src/api/graphql.rs`

### Query: `borrowLimit`

```graphql
query BorrowLimit($address: String!, $chainId: BigInt!, $assetId: Int!) {
  borrowLimit(starknetAddress: $address, chainId: $chainId, assetId: $assetId) {
    collateralUsd18
    debtUsd18
    maxBorrowableUsd18
    availableBorrowUsd18
    healthFactorWad
    privacyMode
  }
}
```

Response semantics:

- `collateralUsd18`: collateral value in normalized 1e18 USD units
- `maxBorrowableUsd18`: limit after risk params + chain debt ceiling checks
- `availableBorrowUsd18`: `maxBorrowableUsd18 - debtUsd18` (min 0)

## REST Endpoints

### `GET /api/borrow-limit`

Query params:

- `address` (starknet address)
- `chain_id` (numeric)
- `asset_id` (numeric)

Response:

```json
{
  "address": "0x...",
  "chain_id": 1,
  "asset_id": 1,
  "collateral_usd_18": "1200000000000000000000",
  "debt_usd_18": "300000000000000000000",
  "max_borrowable_usd_18": "840000000000000000000",
  "available_borrow_usd_18": "540000000000000000000",
  "health_factor_wad": "2200000000000000000",
  "privacy_mode": true
}
```

### `GET /api/indexer/balances`

Query params:

- `address` (starknet address)

Response:

```json
{
  "ETH": "2.1500",
  "BNB": "12.4000",
  "SOL": "45.7800",
  "XRP": "3400.0000",
  "TRX": "25000.0000"
}
```

### `POST /api/proof-relay/jobs`

Queues a private proof relay job.

Request:

```json
{
  "request_id": "proof_17428173",
  "starknet_address": "0x...",
  "chain_id": 1,
  "asset_id": 1,
  "public_input_hash": "0x...",
  "proof_payload": ["0x...", "0x..."]
}
```

Response:

```json
{
  "job_id": "b77de4f3-...",
  "status": "queued"
}
```

### `GET /api/oracles/latest`

Returns cached prices (TTL <= 10 seconds):

```json
{
  "btc": 86000,
  "eth": 3400,
  "sol": 190,
  "bnb": 620,
  "xrp": 2.1,
  "trx": 0.19,
  "updated_at": "2026-03-24T10:00:00Z"
}
```

## Queue Guarantees (Proof Relayer)

- FIFO within `(starknet_address, chain_id, asset_id)` partition
- idempotency by `request_id`
- retries with exponential backoff, dead-letter after `max_retries`
- statuses: `queued -> processing -> submitted -> confirmed | failed | deadletter`

## Reorg Safety Rule

If source chain reorg invalidates a previously detected deposit:

1. mark deposit as `reorged`
2. invoke Starknet hub `freeze_deposit(deposit_id, true)`
3. recompute borrow limit and return `available_borrow_usd_18 = 0` for affected position until resolved
