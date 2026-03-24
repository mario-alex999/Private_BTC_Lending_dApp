use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

const E18_NUMERIC: &str = "1000000000000000000";
const PRICE_SOURCE_AGGREGATOR: &str = "aggregator";
const ORACLE_TTL_SECONDS: i64 = 10;

#[derive(Debug, Clone)]
pub struct PositionRecord {
    pub id: String,
    pub starknet_address: String,
    pub chain_id: i64,
    pub asset_id: i16,
    pub collateral_amount_18: String,
    pub debt_usd_18: String,
    pub health_factor_wad: String,
    pub max_ltv_bps: i32,
    pub liquidation_threshold_bps: i32,
    pub private_commitment_hash: Option<String>,
    pub privacy_mode_enabled: bool,
    pub is_frozen: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub struct DepositRecord {
    pub deposit_id: String,
    pub chain_id: i64,
    pub asset_id: i16,
    pub tx_hash: String,
    pub confirmation_depth: i32,
    pub finality_target: i32,
    pub status: String,
}

#[derive(Debug, Clone)]
pub struct BorrowLimitRecord {
    pub starknet_address: String,
    pub chain_id: i64,
    pub asset_id: i16,
    pub collateral_usd_18: String,
    pub debt_usd_18: String,
    pub max_borrowable_usd_18: String,
    pub available_borrow_usd_18: String,
    pub health_factor_wad: String,
    pub privacy_mode: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct OracleBundle {
    pub btc: f64,
    pub eth: f64,
    pub sol: f64,
    pub bnb: f64,
    pub xrp: f64,
    pub trx: f64,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct IndexerBalances {
    pub eth: String,
    pub bnb: String,
    pub sol: String,
    pub xrp: String,
    pub trx: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EnqueueProofRelayInput {
    pub request_id: String,
    pub starknet_address: String,
    pub chain_id: i64,
    pub asset_id: i16,
    pub public_input_hash: String,
    pub proof_payload: Value,
    pub target_contract: String,
    pub calldata: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct EnqueueProofRelayResult {
    pub job_id: String,
    pub status: String,
}

pub fn normalize_address(address: &str) -> String {
    address.trim().to_lowercase()
}

pub fn symbol_for_asset(asset_id: i16) -> &'static str {
    match asset_id {
        1 => "ETH",
        2 => "BNB",
        3 => "SOL",
        4 => "XRP",
        5 => "TRX",
        6 => "BTC",
        _ => "ETH",
    }
}

pub fn default_max_ltv_bps(asset_id: i16) -> i32 {
    match asset_id {
        1 => 8000,
        2 => 7500,
        3 => 7200,
        4 => 7000,
        5 => 6000,
        6 => 7000,
        _ => 6000,
    }
}

pub fn default_liquidation_threshold_bps(asset_id: i16) -> i32 {
    match asset_id {
        1 => 8500,
        2 => 8000,
        3 => 7600,
        4 => 7400,
        5 => 6500,
        6 => 7800,
        _ => 6500,
    }
}

pub fn chain_debt_ceiling_18(chain_id: i64) -> &'static str {
    match chain_id {
        1 => "100000000000000000000000000",         // 100m
        56 => "60000000000000000000000000",         // 60m
        1399811149 => "50000000000000000000000000", // 50m
        144 => "30000000000000000000000000",        // 30m
        728126428 => "20000000000000000000000000",  // 20m
        _ => "15000000000000000000000000",          // 15m
    }
}

pub fn default_oracle_price_18(symbol: &str) -> &'static str {
    match symbol {
        "BTC" => "86000000000000000000000",
        "ETH" => "3400000000000000000000",
        "SOL" => "190000000000000000000",
        "BNB" => "620000000000000000000",
        "XRP" => "2100000000000000000",
        "TRX" => "190000000000000000",
        _ => "1000000000000000000",
    }
}

pub async fn ensure_user(db: &PgPool, starknet_address: &str) -> Result<Uuid> {
    let normalized = normalize_address(starknet_address);
    let user_id = Uuid::new_v4();

    let row = sqlx::query(
        r#"
        INSERT INTO users (id, starknet_address)
        VALUES ($1, $2)
        ON CONFLICT (starknet_address)
        DO UPDATE SET updated_at = NOW()
        RETURNING id
        "#,
    )
    .bind(user_id)
    .bind(normalized)
    .fetch_one(db)
    .await?;

    Ok(row.get::<Uuid, _>("id"))
}

pub async fn maybe_user_id(db: &PgPool, starknet_address: &str) -> Result<Option<Uuid>> {
    let normalized = normalize_address(starknet_address);

    let row = sqlx::query("SELECT id FROM users WHERE starknet_address = $1")
        .bind(normalized)
        .fetch_optional(db)
        .await?;

    Ok(row.map(|r| r.get::<Uuid, _>("id")))
}

pub async fn list_positions(db: &PgPool, starknet_address: &str) -> Result<Vec<PositionRecord>> {
    let normalized = normalize_address(starknet_address);

    let rows = sqlx::query(
        r#"
        SELECT
            p.id::text AS id,
            u.starknet_address,
            p.chain_id,
            p.asset_id,
            p.collateral_amount_18::text AS collateral_amount_18,
            p.debt_usd_18::text AS debt_usd_18,
            p.health_factor_wad::text AS health_factor_wad,
            p.max_ltv_bps,
            p.liquidation_threshold_bps,
            p.private_commitment_hash,
            p.privacy_mode_enabled,
            p.is_frozen,
            p.updated_at
        FROM positions p
        JOIN users u ON u.id = p.user_id
        WHERE u.starknet_address = $1
        ORDER BY p.updated_at DESC
        "#,
    )
    .bind(normalized)
    .fetch_all(db)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push(PositionRecord {
            id: row.get("id"),
            starknet_address: row.get("starknet_address"),
            chain_id: row.get("chain_id"),
            asset_id: row.get("asset_id"),
            collateral_amount_18: row.get("collateral_amount_18"),
            debt_usd_18: row.get("debt_usd_18"),
            health_factor_wad: row.get("health_factor_wad"),
            max_ltv_bps: row.get("max_ltv_bps"),
            liquidation_threshold_bps: row.get("liquidation_threshold_bps"),
            private_commitment_hash: row.get("private_commitment_hash"),
            privacy_mode_enabled: row.get("privacy_mode_enabled"),
            is_frozen: row.get("is_frozen"),
            updated_at: row.get("updated_at"),
        });
    }

    Ok(out)
}

pub async fn list_deposits(
    db: &PgPool,
    starknet_address: &str,
    status: Option<String>,
) -> Result<Vec<DepositRecord>> {
    let normalized = normalize_address(starknet_address);

    let rows = sqlx::query(
        r#"
        SELECT
            d.deposit_id,
            d.chain_id,
            d.asset_id,
            d.tx_hash,
            d.confirmation_depth,
            d.finality_target,
            d.status
        FROM deposits d
        JOIN users u ON u.id = d.user_id
        WHERE u.starknet_address = $1
          AND ($2::text IS NULL OR d.status = $2)
        ORDER BY d.updated_at DESC
        "#,
    )
    .bind(normalized)
    .bind(status)
    .fetch_all(db)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push(DepositRecord {
            deposit_id: row.get("deposit_id"),
            chain_id: row.get("chain_id"),
            asset_id: row.get("asset_id"),
            tx_hash: row.get("tx_hash"),
            confirmation_depth: row.get("confirmation_depth"),
            finality_target: row.get("finality_target"),
            status: row.get("status"),
        });
    }

    Ok(out)
}

pub async fn upsert_oracle_price_18(
    db: &PgPool,
    symbol: &str,
    price_18: &str,
    source: &str,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO oracle_cache (symbol, source, price_18, fetched_at, expires_at)
        VALUES ($1, $2, $3::numeric, NOW(), NOW() + ($4::text || ' seconds')::interval)
        ON CONFLICT (symbol, source)
        DO UPDATE SET
          price_18 = EXCLUDED.price_18,
          fetched_at = EXCLUDED.fetched_at,
          expires_at = EXCLUDED.expires_at
        "#,
    )
    .bind(symbol)
    .bind(source)
    .bind(price_18)
    .bind(ORACLE_TTL_SECONDS.to_string())
    .execute(db)
    .await?;

    Ok(())
}

pub async fn get_or_seed_oracle_price_18(db: &PgPool, symbol: &str) -> Result<String> {
    let latest = sqlx::query(
        r#"
        SELECT price_18::text AS price_18
        FROM oracle_cache
        WHERE symbol = $1
          AND expires_at > NOW()
        ORDER BY fetched_at DESC
        LIMIT 1
        "#,
    )
    .bind(symbol)
    .fetch_optional(db)
    .await?;

    if let Some(row) = latest {
        return Ok(row.get::<String, _>("price_18"));
    }

    let fallback = default_oracle_price_18(symbol);
    upsert_oracle_price_18(db, symbol, fallback, PRICE_SOURCE_AGGREGATOR).await?;
    Ok(fallback.to_string())
}

pub async fn get_borrow_limit(
    db: &PgPool,
    starknet_address: &str,
    chain_id: i64,
    asset_id: i16,
) -> Result<BorrowLimitRecord> {
    let normalized = normalize_address(starknet_address);
    let max_ltv_default = default_max_ltv_bps(asset_id);
    let lt_default = default_liquidation_threshold_bps(asset_id);

    let Some(user_id) = maybe_user_id(db, &normalized).await? else {
        return Ok(BorrowLimitRecord {
            starknet_address: normalized,
            chain_id,
            asset_id,
            collateral_usd_18: "0".to_string(),
            debt_usd_18: "0".to_string(),
            max_borrowable_usd_18: "0".to_string(),
            available_borrow_usd_18: "0".to_string(),
            health_factor_wad: "99000000000000000000".to_string(),
            privacy_mode: false,
        });
    };

    let position = sqlx::query(
        r#"
        SELECT
            collateral_amount_18::text AS collateral_amount_18,
            debt_usd_18::text AS debt_usd_18,
            privacy_mode_enabled,
            is_frozen,
            max_ltv_bps,
            liquidation_threshold_bps
        FROM positions
        WHERE user_id = $1
          AND chain_id = $2
          AND asset_id = $3
        LIMIT 1
        "#,
    )
    .bind(user_id)
    .bind(chain_id)
    .bind(asset_id)
    .fetch_optional(db)
    .await?;

    let (collateral_amount_18, debt_usd_18, privacy_mode, is_frozen, max_ltv_bps, lt_bps) =
        if let Some(row) = position {
            (
                row.get::<String, _>("collateral_amount_18"),
                row.get::<String, _>("debt_usd_18"),
                row.get::<bool, _>("privacy_mode_enabled"),
                row.get::<bool, _>("is_frozen"),
                row.get::<i32, _>("max_ltv_bps"),
                row.get::<i32, _>("liquidation_threshold_bps"),
            )
        } else {
            (
                "0".to_string(),
                "0".to_string(),
                false,
                false,
                max_ltv_default,
                lt_default,
            )
        };

    let chain_usage_18 = sqlx::query(
        r#"
        SELECT COALESCE(SUM(debt_usd_18), 0)::text AS chain_usage_18
        FROM positions
        WHERE chain_id = $1
          AND is_frozen = FALSE
        "#,
    )
    .bind(chain_id)
    .fetch_one(db)
    .await?
    .get::<String, _>("chain_usage_18");

    let chain_ceiling_18 = chain_debt_ceiling_18(chain_id).to_string();
    let oracle_symbol = symbol_for_asset(asset_id);
    let price_18 = get_or_seed_oracle_price_18(db, oracle_symbol).await?;

    let calc = sqlx::query(
        r#"
        WITH params AS (
            SELECT
                $1::numeric AS collateral_amount_18,
                $2::numeric AS debt_usd_18,
                $3::numeric AS price_18,
                $4::int AS max_ltv_bps,
                $5::numeric AS chain_usage_18,
                $6::numeric AS chain_ceiling_18,
                $7::boolean AS is_frozen,
                $8::int AS lt_bps
        ),
        valueset AS (
            SELECT
                (collateral_amount_18 * price_18 / $9::numeric) AS collateral_usd_18,
                debt_usd_18,
                max_ltv_bps,
                chain_usage_18,
                chain_ceiling_18,
                is_frozen,
                lt_bps
            FROM params
        ),
        derived AS (
            SELECT
                collateral_usd_18,
                debt_usd_18,
                (collateral_usd_18 * max_ltv_bps / 10000)::numeric AS max_borrowable_usd_18,
                chain_usage_18,
                chain_ceiling_18,
                is_frozen,
                lt_bps
            FROM valueset
        )
        SELECT
            collateral_usd_18::text AS collateral_usd_18,
            debt_usd_18::text AS debt_usd_18,
            max_borrowable_usd_18::text AS max_borrowable_usd_18,
            CASE
                WHEN is_frozen THEN '0'
                WHEN chain_usage_18 >= chain_ceiling_18 THEN '0'
                ELSE GREATEST(
                    LEAST(max_borrowable_usd_18 - debt_usd_18, chain_ceiling_18 - chain_usage_18),
                    0
                )::text
            END AS available_borrow_usd_18,
            CASE
                WHEN debt_usd_18 = 0 THEN '99000000000000000000'
                ELSE (
                    ((collateral_usd_18 * lt_bps / 10000) * $9::numeric) / debt_usd_18
                )::text
            END AS health_factor_wad
        FROM derived
        "#,
    )
    .bind(collateral_amount_18)
    .bind(debt_usd_18)
    .bind(price_18)
    .bind(max_ltv_bps)
    .bind(chain_usage_18)
    .bind(chain_ceiling_18)
    .bind(is_frozen)
    .bind(lt_bps)
    .bind(E18_NUMERIC)
    .fetch_one(db)
    .await?;

    Ok(BorrowLimitRecord {
        starknet_address: normalized,
        chain_id,
        asset_id,
        collateral_usd_18: calc.get("collateral_usd_18"),
        debt_usd_18: calc.get("debt_usd_18"),
        max_borrowable_usd_18: calc.get("max_borrowable_usd_18"),
        available_borrow_usd_18: calc.get("available_borrow_usd_18"),
        health_factor_wad: calc.get("health_factor_wad"),
        privacy_mode,
    })
}

pub async fn enqueue_proof_relay_job(
    db: &PgPool,
    input: EnqueueProofRelayInput,
) -> Result<EnqueueProofRelayResult> {
    let user_id = ensure_user(db, &input.starknet_address).await?;
    let job_id = Uuid::new_v4();

    let row = sqlx::query(
        r#"
        INSERT INTO proof_relay_jobs
            (id, user_id, request_id, chain_id, asset_id, public_input_hash, proof_payload, target_contract, calldata, status, retry_count, max_retries)
        VALUES
            ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9::jsonb, 'queued', 0, 5)
        ON CONFLICT (request_id)
        DO UPDATE SET
            proof_payload = EXCLUDED.proof_payload,
            public_input_hash = EXCLUDED.public_input_hash,
            calldata = EXCLUDED.calldata,
            updated_at = NOW()
        RETURNING id::text AS id, status
        "#,
    )
    .bind(job_id)
    .bind(user_id)
    .bind(&input.request_id)
    .bind(input.chain_id)
    .bind(input.asset_id)
    .bind(&input.public_input_hash)
    .bind(input.proof_payload)
    .bind(input.target_contract)
    .bind(input.calldata)
    .fetch_one(db)
    .await?;

    Ok(EnqueueProofRelayResult {
        job_id: row.get("id"),
        status: row.get("status"),
    })
}

pub async fn get_indexer_balances(db: &PgPool, starknet_address: &str) -> Result<IndexerBalances> {
    let normalized = normalize_address(starknet_address);

    let rows = sqlx::query(
        r#"
        SELECT p.asset_id, COALESCE(SUM(p.collateral_amount_18), 0)::text AS collateral_amount_18
        FROM positions p
        JOIN users u ON u.id = p.user_id
        WHERE u.starknet_address = $1
        GROUP BY p.asset_id
        "#,
    )
    .bind(normalized)
    .fetch_all(db)
    .await?;

    let mut eth = "0.0000".to_string();
    let mut bnb = "0.0000".to_string();
    let mut sol = "0.0000".to_string();
    let mut xrp = "0.0000".to_string();
    let mut trx = "0.0000".to_string();

    for row in rows {
        let asset_id: i16 = row.get("asset_id");
        let amount_18: String = row.get("collateral_amount_18");
        let formatted = format_18_decimal(&amount_18, 4)?;

        match symbol_for_asset(asset_id) {
            "ETH" => eth = formatted,
            "BNB" => bnb = formatted,
            "SOL" => sol = formatted,
            "XRP" => xrp = formatted,
            "TRX" => trx = formatted,
            _ => {}
        }
    }

    Ok(IndexerBalances {
        eth,
        bnb,
        sol,
        xrp,
        trx,
    })
}

pub async fn get_latest_oracle_bundle(db: &PgPool) -> Result<OracleBundle> {
    let btc_18 = get_or_seed_oracle_price_18(db, "BTC").await?;
    let eth_18 = get_or_seed_oracle_price_18(db, "ETH").await?;
    let sol_18 = get_or_seed_oracle_price_18(db, "SOL").await?;
    let bnb_18 = get_or_seed_oracle_price_18(db, "BNB").await?;
    let xrp_18 = get_or_seed_oracle_price_18(db, "XRP").await?;
    let trx_18 = get_or_seed_oracle_price_18(db, "TRX").await?;

    let updated_at = sqlx::query(
        r#"
        SELECT COALESCE(MAX(fetched_at), NOW()) AS updated_at
        FROM oracle_cache
        WHERE symbol IN ('BTC', 'ETH', 'SOL', 'BNB', 'XRP', 'TRX')
        "#,
    )
    .fetch_one(db)
    .await?
    .get::<DateTime<Utc>, _>("updated_at");

    Ok(OracleBundle {
        btc: to_float_price(&btc_18)?,
        eth: to_float_price(&eth_18)?,
        sol: to_float_price(&sol_18)?,
        bnb: to_float_price(&bnb_18)?,
        xrp: to_float_price(&xrp_18)?,
        trx: to_float_price(&trx_18)?,
        updated_at,
    })
}

pub fn to_price_18_from_float(price: f64) -> Result<String> {
    if !price.is_finite() || price < 0.0 {
        return Err(anyhow!("invalid oracle price"));
    }

    let scaled = (price * 1e18_f64).round();
    if scaled < 0.0 {
        return Err(anyhow!("invalid oracle price"));
    }

    Ok(format!("{scaled:.0}"))
}

pub fn parse_price_float(payload: &Value) -> Result<f64> {
    if let Some(n) = payload.get("price").and_then(Value::as_f64) {
        return Ok(n);
    }

    if let Some(s) = payload.get("price").and_then(Value::as_str) {
        return s.parse::<f64>().context("price string parse failed");
    }

    if let Some(n) = payload
        .get("result")
        .and_then(|v| v.get("price"))
        .and_then(Value::as_f64)
    {
        return Ok(n);
    }

    Err(anyhow!("price field missing"))
}

fn to_float_price(price_18: &str) -> Result<f64> {
    let raw = price_18
        .parse::<f64>()
        .with_context(|| format!("failed to parse price_18={price_18}"))?;

    Ok(raw / 1e18_f64)
}

fn format_18_decimal(value_18: &str, scale: usize) -> Result<String> {
    let trimmed = value_18.trim();
    if trimmed.is_empty() {
        return Err(anyhow!("empty amount_18"));
    }

    let is_negative = trimmed.starts_with('-');
    let digits = if is_negative { &trimmed[1..] } else { trimmed };

    if digits.chars().any(|c| !c.is_ascii_digit()) {
        return Err(anyhow!("invalid amount_18 string"));
    }

    let mut padded = digits.to_string();
    if padded.len() <= 18 {
        let zeros = "0".repeat(19 - padded.len());
        padded = format!("{zeros}{padded}");
    }

    let split = padded.len() - 18;
    let int_part = &padded[..split];
    let frac_part = &padded[split..];
    let frac = &frac_part[..scale.min(frac_part.len())];

    let sign = if is_negative { "-" } else { "" };
    Ok(format!("{sign}{int_part}.{frac}"))
}
