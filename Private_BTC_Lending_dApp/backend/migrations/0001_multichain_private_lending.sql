-- Core user identity and profile mapping
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  starknet_address TEXT NOT NULL UNIQUE,
  starknet_id_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Public and private position metadata
CREATE TABLE IF NOT EXISTS positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chain_id BIGINT NOT NULL,
  asset_id SMALLINT NOT NULL,
  collateral_amount_18 NUMERIC(78, 0) NOT NULL,
  debt_usd_18 NUMERIC(78, 0) NOT NULL,
  private_commitment_hash TEXT,
  privacy_mode_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  health_factor_wad NUMERIC(78, 0) NOT NULL DEFAULT 0,
  liquidation_threshold_bps INT NOT NULL,
  max_ltv_bps INT NOT NULL,
  is_frozen BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, chain_id, asset_id)
);

-- Deposit source tracking for reorg and freeze logic
CREATE TABLE IF NOT EXISTS deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deposit_id TEXT NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chain_id BIGINT NOT NULL,
  asset_id SMALLINT NOT NULL,
  tx_hash TEXT NOT NULL,
  block_number BIGINT NOT NULL,
  amount_native_18 NUMERIC(78, 0) NOT NULL,
  confirmation_depth INT NOT NULL DEFAULT 0,
  finality_target INT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('detected', 'finalized', 'reorged', 'frozen')),
  proof_job_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ZK proof relay queue for high-throughput borrow submission
CREATE TABLE IF NOT EXISTS proof_relay_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id TEXT NOT NULL UNIQUE,
  chain_id BIGINT NOT NULL,
  asset_id SMALLINT NOT NULL,
  public_input_hash TEXT NOT NULL,
  proof_payload JSONB NOT NULL,
  target_contract TEXT NOT NULL,
  calldata JSONB NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'processing', 'submitted', 'confirmed', 'failed', 'deadletter')),
  retry_count INT NOT NULL DEFAULT 0,
  max_retries INT NOT NULL DEFAULT 5,
  tx_hash TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Oracle cache with strict TTL enforcement
CREATE TABLE IF NOT EXISTS oracle_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  symbol TEXT NOT NULL,
  source TEXT NOT NULL,
  price_18 NUMERIC(78, 0) NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  UNIQUE (symbol, source)
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_positions_user ON positions(user_id);
CREATE INDEX IF NOT EXISTS idx_deposits_chain_status ON deposits(chain_id, status);
CREATE INDEX IF NOT EXISTS idx_jobs_status_created ON proof_relay_jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_oracle_cache_symbol ON oracle_cache(symbol, expires_at);
