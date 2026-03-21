use contracts::{
    BitcoinDepositProof, ILendingPoolDispatcher, ILendingPoolDispatcherTrait,
    IMockBtcProofVerifierAdminDispatcher, IMockBtcProofVerifierAdminDispatcherTrait,
    IStablecoinDispatcher, IStablecoinDispatcherTrait,
};
use snforge_std::{ContractClassTrait, DeclareResult, declare};

#[test]
fn test_private_borrow_with_oracle_and_garaga_adapter() {
    let borrower = starknet::get_contract_address();

    let btc_verifier_class = match declare("MockBtcProofVerifier").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let (btc_verifier_address, _) = btc_verifier_class.deploy(@ArrayTrait::new()).unwrap();
    let btc_verifier_admin = IMockBtcProofVerifierAdminDispatcher {
        contract_address: btc_verifier_address,
    };
    btc_verifier_admin.set_result(true);

    let stablecoin_class = match declare("MockStablecoin").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let (stablecoin_address, _) = stablecoin_class.deploy(@ArrayTrait::new()).unwrap();
    let stablecoin = IStablecoinDispatcher { contract_address: stablecoin_address };

    let pool_class = match declare("LendingPool").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let mut pool_constructor = ArrayTrait::new();
    pool_constructor.append(borrower.into()); // owner
    pool_constructor.append(btc_verifier_address.into()); // BTC proof verifier
    pool_constructor.append(stablecoin_address.into()); // stablecoin
    pool_constructor.append(0_u8.into()); // disbursal mode: mint
    pool_constructor.append(123); // vault script hash
    pool_constructor.append(6_000_000_000_000_u128.into());
    pool_constructor.append(7_000_u16.into());
    pool_constructor.append(8_000_u16.into());
    pool_constructor.append(1_100_000_000_000_000_000_u128.into());
    let (pool_address, _) = pool_class.deploy(@pool_constructor).unwrap();
    let pool = ILendingPoolDispatcher { contract_address: pool_address };

    let mock_price_oracle_class = match declare("MockPriceOracle").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let mut price_constructor = ArrayTrait::new();
    price_constructor.append(6_500_000_000_000_u128.into()); // $65,000
    let (price_oracle_address, _) = mock_price_oracle_class.deploy(@price_constructor).unwrap();
    pool.set_price_oracle(price_oracle_address);

    let mock_garaga_verifier_class = match declare("MockGaragaVerifier").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let mut garaga_verifier_constructor = ArrayTrait::new();
    garaga_verifier_constructor.append(1);
    let (garaga_verifier_address, _) = mock_garaga_verifier_class
        .deploy(@garaga_verifier_constructor)
        .unwrap();

    let ltv_adapter_class = match declare("GaragaInequalityVerifierAdapter").unwrap() {
        DeclareResult::Success(class) => class,
        DeclareResult::AlreadyDeclared(class) => class,
    };
    let mut ltv_adapter_constructor = ArrayTrait::new();
    ltv_adapter_constructor.append(borrower.into());
    ltv_adapter_constructor.append(garaga_verifier_address.into());
    let (ltv_adapter_address, _) = ltv_adapter_class.deploy(@ltv_adapter_constructor).unwrap();
    pool.set_ltv_proof_verifier(ltv_adapter_address);

    let proof = BitcoinDepositProof {
        txid: 12345,
        vout: 0,
        amount_sats: 200_000_000,
        btc_block_height: 950_000,
        vault_script_hash: 123,
    };
    let mut btc_proof_blob = ArrayTrait::new();
    btc_proof_blob.append(1);
    pool.deposit_collateral(proof, btc_proof_blob.span(), 999_111); // non-zero commitment

    let pulled_price = pool.get_btc_price_in_usd();
    assert(pulled_price == 6_500_000_000_000, 'BAD_ORACLE_PRICE');

    let mut private_proof = ArrayTrait::new();
    private_proof.append(7);
    private_proof.append(8);
    private_proof.append(9);

    let debt_amount = 1_000_000_000_000_u128;
    let valid = pool.verify_ltv_proof(borrower, debt_amount, private_proof.span());
    assert(valid, 'LTV_PROOF_SHOULD_PASS');

    pool.withdraw_debt_private(debt_amount, private_proof.span());

    let position = pool.get_position(borrower);
    assert(position.debt_usd_8 == debt_amount, 'BAD_PRIVATE_DEBT');

    let stablecoin_balance = stablecoin.balance_of(borrower);
    assert(stablecoin_balance.low == debt_amount, 'BAD_PRIVATE_MINT');
    assert(stablecoin_balance.high == 0, 'BAD_PRIVATE_MINT_HIGH');
}
