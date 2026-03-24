use async_graphql::{
    Context, EmptySubscription, Enum, Error, InputValueError, InputValueResult, Object, Scalar,
    ScalarType, Schema, SimpleObject, Value,
};
use chrono::{DateTime, Utc};
use serde_json::json;

use crate::domain::lending::{
    self, BorrowLimitRecord, DepositRecord, EnqueueProofRelayInput, PositionRecord,
};
use crate::AppState;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BigInt(pub String);

#[Scalar(name = "BigInt")]
impl ScalarType for BigInt {
    fn parse(value: Value) -> InputValueResult<Self> {
        match value {
            Value::String(s) => Ok(Self(s)),
            Value::Number(n) => Ok(Self(n.to_string())),
            _ => Err(InputValueError::custom("BigInt must be a string or number")),
        }
    }

    fn to_value(&self) -> Value {
        Value::String(self.0.clone())
    }
}

#[derive(Enum, Copy, Clone, Eq, PartialEq)]
pub enum PositionVisibility {
    Public,
    Private,
}

#[derive(SimpleObject, Clone)]
#[graphql(rename_fields = "camelCase")]
pub struct Position {
    pub id: String,
    pub starknet_address: String,
    pub chain_id: BigInt,
    pub asset_id: i32,
    pub collateral_amount_18: BigInt,
    pub debt_usd_18: BigInt,
    pub health_factor_wad: BigInt,
    pub max_ltv_bps: i32,
    pub liquidation_threshold_bps: i32,
    pub private_commitment_hash: Option<String>,
    pub visibility: PositionVisibility,
    pub frozen: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(SimpleObject, Clone)]
#[graphql(rename_fields = "camelCase")]
pub struct BorrowLimit {
    pub starknet_address: String,
    pub chain_id: BigInt,
    pub asset_id: i32,
    pub collateral_usd_18: BigInt,
    pub debt_usd_18: BigInt,
    pub max_borrowable_usd_18: BigInt,
    pub available_borrow_usd_18: BigInt,
    pub health_factor_wad: BigInt,
    pub privacy_mode: bool,
}

#[derive(SimpleObject, Clone)]
#[graphql(rename_fields = "camelCase")]
pub struct Deposit {
    pub deposit_id: String,
    pub chain_id: BigInt,
    pub asset_id: i32,
    pub tx_hash: String,
    pub confirmation_depth: i32,
    pub finality_target: i32,
    pub status: String,
}

pub type LendingSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

pub fn build_schema(state: AppState) -> LendingSchema {
    Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(state)
        .finish()
}

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn positions(
        &self,
        ctx: &Context<'_>,
        starknet_address: String,
    ) -> async_graphql::Result<Vec<Position>> {
        let state = ctx.data::<AppState>()?;
        let rows = lending::list_positions(&state.db, &starknet_address)
            .await
            .map_err(to_graphql_error)?;

        Ok(rows.into_iter().map(to_position).collect())
    }

    async fn borrow_limit(
        &self,
        ctx: &Context<'_>,
        starknet_address: String,
        chain_id: BigInt,
        asset_id: i32,
    ) -> async_graphql::Result<BorrowLimit> {
        let state = ctx.data::<AppState>()?;
        let chain_id_i64 = parse_i64(&chain_id.0)?;
        let asset_id_i16 = parse_i16(asset_id)?;

        let row =
            lending::get_borrow_limit(&state.db, &starknet_address, chain_id_i64, asset_id_i16)
                .await
                .map_err(to_graphql_error)?;

        Ok(to_borrow_limit(row))
    }

    async fn deposits(
        &self,
        ctx: &Context<'_>,
        starknet_address: String,
        status: Option<String>,
    ) -> async_graphql::Result<Vec<Deposit>> {
        let state = ctx.data::<AppState>()?;
        let rows = lending::list_deposits(&state.db, &starknet_address, status)
            .await
            .map_err(to_graphql_error)?;

        Ok(rows.into_iter().map(to_deposit).collect())
    }
}

pub struct MutationRoot;

#[Object]
impl MutationRoot {
    async fn enqueue_proof_relay(
        &self,
        ctx: &Context<'_>,
        request_id: String,
        starknet_address: String,
        chain_id: BigInt,
        asset_id: i32,
        public_input_hash: String,
        proof_payload: String,
    ) -> async_graphql::Result<String> {
        let state = ctx.data::<AppState>()?;
        let chain_id_i64 = parse_i64(&chain_id.0)?;
        let asset_id_i16 = parse_i16(asset_id)?;

        let parsed_payload: serde_json::Value =
            serde_json::from_str(&proof_payload).unwrap_or_else(|_| json!([proof_payload]));

        let input = EnqueueProofRelayInput {
            request_id,
            starknet_address,
            chain_id: chain_id_i64,
            asset_id: asset_id_i16,
            public_input_hash,
            proof_payload: parsed_payload,
            target_contract: state.cfg.hub_contract_address.clone(),
            calldata: json!({
                "chain_id": chain_id_i64,
                "asset_id": asset_id_i16,
            }),
        };

        let queued = lending::enqueue_proof_relay_job(&state.db, input)
            .await
            .map_err(to_graphql_error)?;

        Ok(queued.job_id)
    }
}

fn to_position(row: PositionRecord) -> Position {
    Position {
        id: row.id,
        starknet_address: row.starknet_address,
        chain_id: BigInt(row.chain_id.to_string()),
        asset_id: row.asset_id as i32,
        collateral_amount_18: BigInt(row.collateral_amount_18),
        debt_usd_18: BigInt(row.debt_usd_18),
        health_factor_wad: BigInt(row.health_factor_wad),
        max_ltv_bps: row.max_ltv_bps,
        liquidation_threshold_bps: row.liquidation_threshold_bps,
        private_commitment_hash: row.private_commitment_hash,
        visibility: if row.privacy_mode_enabled {
            PositionVisibility::Private
        } else {
            PositionVisibility::Public
        },
        frozen: row.is_frozen,
        updated_at: row.updated_at,
    }
}

fn to_borrow_limit(row: BorrowLimitRecord) -> BorrowLimit {
    BorrowLimit {
        starknet_address: row.starknet_address,
        chain_id: BigInt(row.chain_id.to_string()),
        asset_id: row.asset_id as i32,
        collateral_usd_18: BigInt(row.collateral_usd_18),
        debt_usd_18: BigInt(row.debt_usd_18),
        max_borrowable_usd_18: BigInt(row.max_borrowable_usd_18),
        available_borrow_usd_18: BigInt(row.available_borrow_usd_18),
        health_factor_wad: BigInt(row.health_factor_wad),
        privacy_mode: row.privacy_mode,
    }
}

fn to_deposit(row: DepositRecord) -> Deposit {
    Deposit {
        deposit_id: row.deposit_id,
        chain_id: BigInt(row.chain_id.to_string()),
        asset_id: row.asset_id as i32,
        tx_hash: row.tx_hash,
        confirmation_depth: row.confirmation_depth,
        finality_target: row.finality_target,
        status: row.status,
    }
}

fn parse_i16(value: i32) -> async_graphql::Result<i16> {
    i16::try_from(value).map_err(|_| Error::new("asset_id out of range"))
}

fn parse_i64(value: &str) -> async_graphql::Result<i64> {
    value
        .parse::<i64>()
        .map_err(|_| Error::new("chain_id must fit in signed 64-bit integer"))
}

fn to_graphql_error(err: impl std::fmt::Display) -> Error {
    Error::new(err.to_string())
}
