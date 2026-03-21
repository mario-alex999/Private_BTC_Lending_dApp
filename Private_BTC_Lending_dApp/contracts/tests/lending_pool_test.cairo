use contracts::{
    BitcoinDepositProof, ILendingPoolDispatcher, ILendingPoolDispatcherTrait,
    IMockIntegrityFactRegistryAdminDispatcher, IMockIntegrityFactRegistryAdminDispatcherTrait,
    IStablecoinDispatcher, IStablecoinDispatcherTrait, VerificationRecord,
};
use core::integer::u256;
use snforge_std::{ContractClassTrait, DeclareResult, declare};

fn deploy_registry_and_adapter(
    owner: starknet::ContractAddress,
    min_security_bits: u32,
    required_settings: felt252,
    domain_separator: felt252,
) -> (starknet::ContractAddress, starknet::ContractAddress) {
    let registry_class = match declare("MockIntegrityFactRegistry").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let (registry_address, _) = registry_class.deploy(@ArrayTrait::new()).unwrap();

    let adapter_class = match declare("HerodotusFactRegistryAdapter").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };

    let mut adapter_constructor = ArrayTrait::new();
    adapter_constructor.append(owner.into());
    adapter_constructor.append(registry_address.into());
    adapter_constructor.append(min_security_bits.into());
    adapter_constructor.append(required_settings);
    adapter_constructor.append(domain_separator);

    let (adapter_address, _) = adapter_class.deploy(@adapter_constructor).unwrap();
    (registry_address, adapter_address)
}

fn deploy_pool(
    owner: starknet::ContractAddress,
    proof_verifier: starknet::ContractAddress,
    stablecoin: starknet::ContractAddress,
    disbursal_mode: u8,
) -> ILendingPoolDispatcher {
    let pool_class = match declare("LendingPool").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };

    let mut constructor_calldata = ArrayTrait::new();
    constructor_calldata.append(owner.into());
    constructor_calldata.append(proof_verifier.into());
    constructor_calldata.append(stablecoin.into());
    constructor_calldata.append(disbursal_mode.into());
    constructor_calldata.append(123); // vault_script_hash
    constructor_calldata.append(6_000_000_000_000_u128.into()); // BTC = $60,000 with 8 decimals
    constructor_calldata.append(7_000_u16.into()); // max_ltv_bps
    constructor_calldata.append(8_000_u16.into()); // liquidation_threshold_bps
    constructor_calldata.append(1_100_000_000_000_000_000_u128.into()); // min HF = 1.1

    let (pool_address, _) = pool_class.deploy(@constructor_calldata).unwrap();
    ILendingPoolDispatcher { contract_address: pool_address }
}

#[test]
fn test_adapter_and_mint_disbursal_flow() {
    let borrower = starknet::get_contract_address();
    let verification_hash: felt252 = 555;
    let required_settings: felt252 = 77;
    let domain_separator: felt252 = 9_999;

    let stablecoin_class = match declare("MockStablecoin").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let (stablecoin_address, _) = stablecoin_class.deploy(@ArrayTrait::new()).unwrap();
    let stablecoin = IStablecoinDispatcher { contract_address: stablecoin_address };

    let (registry_address, adapter_address) = deploy_registry_and_adapter(
        borrower, 100_u32, required_settings, domain_separator,
    );

    let expected_fact_hash = 777
        + 0
        + 200_000_000
        + 900_000
        + 123
        + borrower.into()
        + domain_separator;

    let registry_admin = IMockIntegrityFactRegistryAdminDispatcher {
        contract_address: registry_address,
    };
    registry_admin
        .set_verification(
            verification_hash,
            VerificationRecord {
                fact_hash: expected_fact_hash, security_bits: 120, settings: required_settings,
            },
        );

    let pool = deploy_pool(borrower, adapter_address, stablecoin_address, 0_u8);

    let proof = BitcoinDepositProof {
        txid: 777,
        vout: 0,
        amount_sats: 200_000_000, // 2 BTC
        btc_block_height: 900_000,
        vault_script_hash: 123,
    };

    let mut proof_blob = ArrayTrait::new();
    proof_blob.append(verification_hash);
    proof_blob.append(required_settings);
    proof_blob.append(expected_fact_hash);

    pool.deposit_collateral(proof, proof_blob.span(), 999);

    let debt_amount = 1_000_000_000_000_u128;
    pool.withdraw_debt(debt_amount);

    let position = pool.get_position(borrower);
    assert(position.debt_usd_8 == debt_amount, 'BAD_DEBT');

    let stablecoin_balance = stablecoin.balance_of(borrower);
    assert(stablecoin_balance.low == debt_amount, 'BAD_MINT_BAL');
    assert(stablecoin_balance.high == 0, 'BAD_MINT_BAL_HI');
}

#[test]
fn test_adapter_and_transfer_disbursal_flow() {
    let borrower = starknet::get_contract_address();
    let verification_hash: felt252 = 7777;
    let required_settings: felt252 = 88;
    let domain_separator: felt252 = 7_777;

    let stablecoin_class = match declare("MockStablecoin").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let (stablecoin_address, _) = stablecoin_class.deploy(@ArrayTrait::new()).unwrap();
    let stablecoin = IStablecoinDispatcher { contract_address: stablecoin_address };

    let (registry_address, adapter_address) = deploy_registry_and_adapter(
        borrower, 100_u32, required_settings, domain_separator,
    );
    let registry_admin = IMockIntegrityFactRegistryAdminDispatcher {
        contract_address: registry_address,
    };

    let pool = deploy_pool(borrower, adapter_address, stablecoin_address, 1_u8);

    let expected_fact_hash = 555
        + 1
        + 150_000_000
        + 900_100
        + 123
        + borrower.into()
        + domain_separator;

    registry_admin
        .set_verification(
            verification_hash,
            VerificationRecord {
                fact_hash: expected_fact_hash, security_bits: 128, settings: required_settings,
            },
        );

    let proof = BitcoinDepositProof {
        txid: 555,
        vout: 1,
        amount_sats: 150_000_000, // 1.5 BTC
        btc_block_height: 900_100,
        vault_script_hash: 123,
    };

    let mut proof_blob = ArrayTrait::new();
    proof_blob.append(verification_hash);
    proof_blob.append(required_settings);
    proof_blob.append(expected_fact_hash);

    pool.deposit_collateral(proof, proof_blob.span(), 111);

    // Prefund the pool, then debt payout should transfer from pool balance.
    stablecoin.mint(pool.contract_address, u256 { low: 2_000_000_000_000, high: 0 });

    let debt_amount = 1_000_000_000_000_u128;
    pool.withdraw_debt(debt_amount);

    let borrower_balance = stablecoin.balance_of(borrower);
    assert(borrower_balance.low == debt_amount, 'BAD_TRANSFER_BAL');
    assert(borrower_balance.high == 0, 'BAD_TRANSFER_BAL_HI');

    let pool_balance = stablecoin.balance_of(pool.contract_address);
    assert(pool_balance.low == 1_000_000_000_000, 'BAD_POOL_BAL');
}
