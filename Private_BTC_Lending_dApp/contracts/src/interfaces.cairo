use core::integer::u256;

use crate::types::{
    BitcoinDepositProof, DataType, PragmaPricesResponse, UserPosition, VerificationRecord,
};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IHelloStarknet<TContractState> {
    fn increase_balance(ref self: TContractState, amount: felt252);
    fn decrease_balance(ref self: TContractState, amount: felt252);
    fn get_balance(self: @TContractState) -> felt252;
}

#[starknet::interface]
pub trait IIntegrityFactRegistry<TContractState> {
    fn get_verification(self: @TContractState, verification_hash: felt252) -> VerificationRecord;
}

#[starknet::interface]
pub trait IBtcProofVerifier<TContractState> {
    fn verify_deposit_proof(
        self: @TContractState,
        borrower: ContractAddress,
        txid: felt252,
        vout: u32,
        amount_sats: u128,
        btc_block_height: u64,
        vault_script_hash: felt252,
        proof_blob: Span<felt252>,
    ) -> bool;
}

#[starknet::interface]
pub trait IStablecoin<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IPriceOracle<TContractState> {
    fn get_btc_usd_price(self: @TContractState) -> u128;
}

#[starknet::interface]
pub trait IPragmaOracle<TContractState> {
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
}

#[starknet::interface]
pub trait ILtvProofVerifier<TContractState> {
    fn verify_ltv_proof(
        self: @TContractState,
        user: ContractAddress,
        public_input_hash: felt252,
        proof: Span<felt252>,
    ) -> bool;
}

#[starknet::interface]
pub trait IGaragaVerifier<TContractState> {
    fn verify(self: @TContractState, proof: Span<felt252>, public_inputs: Span<felt252>) -> bool;
}

#[starknet::interface]
pub trait ILendingPool<TContractState> {
    fn deposit_collateral(
        ref self: TContractState,
        proof: BitcoinDepositProof,
        proof_blob: Span<felt252>,
        encrypted_position_commitment: felt252,
    );
    fn withdraw_debt(ref self: TContractState, debt_amount_usd_8: u128);
    fn calculate_health_factor(self: @TContractState, user: ContractAddress) -> u128;
    fn get_position(self: @TContractState, user: ContractAddress) -> UserPosition;
    fn set_btc_price(ref self: TContractState, btc_price_usd_8: u128);
    fn set_stablecoin(ref self: TContractState, stablecoin: ContractAddress);
    fn set_debt_disbursal_mode(ref self: TContractState, mode: u8);
    fn get_btc_price_in_usd(self: @TContractState) -> u128;
    fn set_price_oracle(ref self: TContractState, oracle: ContractAddress);
    fn set_ltv_proof_verifier(ref self: TContractState, verifier: ContractAddress);
    fn verify_ltv_proof(
        self: @TContractState, user: ContractAddress, debt_amount_usd_8: u128, proof: Span<felt252>,
    ) -> bool;
    fn withdraw_debt_private(
        ref self: TContractState, debt_amount_usd_8: u128, proof: Span<felt252>,
    );
}

#[starknet::interface]
pub trait IHerodotusFactRegistryAdapterAdmin<TContractState> {
    fn set_fact_registry(ref self: TContractState, fact_registry: ContractAddress);
    fn set_min_security_bits(ref self: TContractState, min_security_bits: u32);
    fn set_required_settings(ref self: TContractState, required_settings: felt252);
    fn set_domain_separator(ref self: TContractState, domain_separator: felt252);
}

#[starknet::interface]
pub trait IMockIntegrityFactRegistryAdmin<TContractState> {
    fn set_verification(
        ref self: TContractState, verification_hash: felt252, record: VerificationRecord,
    );
}

#[starknet::interface]
pub trait IMockBtcProofVerifierAdmin<TContractState> {
    fn set_result(ref self: TContractState, result: bool);
}

#[starknet::interface]
pub trait IPragmaOracleAdapterAdmin<TContractState> {
    fn set_pragma_oracle(ref self: TContractState, pragma_oracle: ContractAddress);
    fn set_pair_id(ref self: TContractState, pair_id: felt252);
}

#[starknet::interface]
pub trait IGaragaInequalityVerifierAdapterAdmin<TContractState> {
    fn set_garaga_verifier(ref self: TContractState, verifier: ContractAddress);
}

#[starknet::interface]
pub trait IMockPriceOracleAdmin<TContractState> {
    fn set_price(ref self: TContractState, price: u128);
}

#[starknet::interface]
pub trait IMockGaragaVerifierAdmin<TContractState> {
    fn set_result(ref self: TContractState, result: bool);
}
