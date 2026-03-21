#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct UserPosition {
    pub collateral_sats: u128,
    pub debt_usd_8: u128,
    pub encrypted_position_commitment: felt252,
    pub last_btc_block_height: u64,
}

#[derive(Copy, Drop, Serde)]
pub struct BitcoinDepositProof {
    pub txid: felt252,
    pub vout: u32,
    pub amount_sats: u128,
    pub btc_block_height: u64,
    pub vault_script_hash: felt252,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct VerificationRecord {
    pub fact_hash: felt252,
    pub security_bits: u32,
    pub settings: felt252,
}

#[derive(Copy, Drop, Serde)]
pub enum DataType {
    SpotEntry: felt252,
}

#[derive(Copy, Drop, Serde)]
pub struct PragmaPricesResponse {
    pub price: u128,
}
