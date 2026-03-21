#[starknet::contract]
mod LendingPool {
    use core::integer::u256;

    use crate::interfaces::{
        IBtcProofVerifierDispatcher, IBtcProofVerifierDispatcherTrait, ILendingPool,
        ILtvProofVerifierDispatcher, ILtvProofVerifierDispatcherTrait, IPriceOracleDispatcher,
        IPriceOracleDispatcherTrait, IStablecoinDispatcher, IStablecoinDispatcherTrait,
    };
    use crate::types::{BitcoinDepositProof, UserPosition};
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    const SATS_PER_BTC: u128 = 100_000_000;
    const BPS_DENOMINATOR: u128 = 10_000;
    const WAD: u128 = 1_000_000_000_000_000_000;
    const NO_DEBT_HEALTH_FACTOR: u128 = 1_000_000_000_000_000_000_000_000;
    const MIN_PRIVATE_LTV_WAD: u128 = 1_500_000_000_000_000_000;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        proof_verifier: ContractAddress,
        price_oracle: ContractAddress,
        ltv_proof_verifier: ContractAddress,
        stablecoin: ContractAddress,
        debt_disbursal_mode: u8,
        vault_script_hash: felt252,
        btc_price_usd_8: u128,
        max_ltv_bps: u16,
        liquidation_threshold_bps: u16,
        min_health_factor_wad: u128,
        positions: Map<ContractAddress, UserPosition>,
        consumed_outpoints: Map<(felt252, u32), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CollateralDeposited: CollateralDeposited,
        DebtWithdrawn: DebtWithdrawn,
        BtcPriceUpdated: BtcPriceUpdated,
        PriceOracleSet: PriceOracleSet,
        LtvProofVerifierSet: LtvProofVerifierSet,
        StablecoinSet: StablecoinSet,
        DebtDisbursalModeUpdated: DebtDisbursalModeUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct CollateralDeposited {
        #[key]
        user: ContractAddress,
        txid: felt252,
        vout: u32,
        amount_sats: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct DebtWithdrawn {
        #[key]
        user: ContractAddress,
        amount_usd_8: u128,
        health_factor_wad: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct BtcPriceUpdated {
        price_usd_8: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct PriceOracleSet {
        oracle: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct LtvProofVerifierSet {
        verifier: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StablecoinSet {
        stablecoin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct DebtDisbursalModeUpdated {
        mode: u8,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        verifier: ContractAddress,
        stablecoin: ContractAddress,
        debt_disbursal_mode: u8,
        vault_script_hash: felt252,
        btc_price_usd_8: u128,
        max_ltv_bps: u16,
        liquidation_threshold_bps: u16,
        min_health_factor_wad: u128,
    ) {
        assert(owner != starknet::contract_address_const::<0>(), 'INVALID_OWNER');
        assert(verifier != starknet::contract_address_const::<0>(), 'INVALID_VERIFIER');
        assert(stablecoin != starknet::contract_address_const::<0>(), 'INVALID_STABLECOIN');
        assert(debt_disbursal_mode <= 1_u8, 'INVALID_MODE');
        assert(btc_price_usd_8 > 0, 'INVALID_PRICE');
        assert(max_ltv_bps > 0, 'INVALID_MAX_LTV');
        assert(liquidation_threshold_bps > 0, 'INVALID_LT');
        assert(max_ltv_bps <= liquidation_threshold_bps, 'LTV_GT_LT');
        assert(liquidation_threshold_bps <= 10_000_u16, 'LT_TOO_HIGH');
        assert(min_health_factor_wad >= WAD, 'HF_LT_ONE');

        self.owner.write(owner);
        self.proof_verifier.write(verifier);
        self.price_oracle.write(starknet::contract_address_const::<0>());
        self.ltv_proof_verifier.write(starknet::contract_address_const::<0>());
        self.stablecoin.write(stablecoin);
        self.debt_disbursal_mode.write(debt_disbursal_mode);
        self.vault_script_hash.write(vault_script_hash);
        self.btc_price_usd_8.write(btc_price_usd_8);
        self.max_ltv_bps.write(max_ltv_bps);
        self.liquidation_threshold_bps.write(liquidation_threshold_bps);
        self.min_health_factor_wad.write(min_health_factor_wad);
    }

    #[abi(embed_v0)]
    impl LendingPoolImpl of ILendingPool<ContractState> {
        fn deposit_collateral(
            ref self: ContractState,
            proof: BitcoinDepositProof,
            proof_blob: Span<felt252>,
            encrypted_position_commitment: felt252,
        ) {
            assert(proof.amount_sats > 0, 'ZERO_COLLATERAL');
            assert(proof.vault_script_hash == self.vault_script_hash.read(), 'WRONG_VAULT');
            assert(!self.consumed_outpoints.read((proof.txid, proof.vout)), 'OUTPOINT_USED');

            let borrower = get_caller_address();
            let verifier = IBtcProofVerifierDispatcher {
                contract_address: self.proof_verifier.read(),
            };
            let is_valid = verifier
                .verify_deposit_proof(
                    borrower,
                    proof.txid,
                    proof.vout,
                    proof.amount_sats,
                    proof.btc_block_height,
                    proof.vault_script_hash,
                    proof_blob,
                );
            assert(is_valid, 'INVALID_BTC_PROOF');

            self.consumed_outpoints.write((proof.txid, proof.vout), true);

            let mut position = self.positions.read(borrower);
            position.collateral_sats = position.collateral_sats + proof.amount_sats;
            position.encrypted_position_commitment = encrypted_position_commitment;
            position.last_btc_block_height = proof.btc_block_height;
            self.positions.write(borrower, position);

            self
                .emit(
                    Event::CollateralDeposited(
                        CollateralDeposited {
                            user: borrower,
                            txid: proof.txid,
                            vout: proof.vout,
                            amount_sats: proof.amount_sats,
                        },
                    ),
                );
        }

        fn withdraw_debt(ref self: ContractState, debt_amount_usd_8: u128) {
            assert(debt_amount_usd_8 > 0, 'ZERO_DEBT');

            let borrower = get_caller_address();
            let mut position = self.positions.read(borrower);
            assert(position.collateral_sats > 0, 'NO_COLLATERAL');

            let new_debt = position.debt_usd_8 + debt_amount_usd_8;
            let max_debt = InternalTrait::_max_borrowable_usd_8_from_collateral(
                @self, position.collateral_sats,
            );
            assert(new_debt <= max_debt, 'ABOVE_MAX_LTV');

            position.debt_usd_8 = new_debt;
            let health_factor_wad = InternalTrait::_health_factor_wad(@self, position);
            assert(health_factor_wad >= self.min_health_factor_wad.read(), 'HF_TOO_LOW');

            self.positions.write(borrower, position);
            InternalTrait::_disburse_debt(ref self, borrower, debt_amount_usd_8);

            self
                .emit(
                    Event::DebtWithdrawn(
                        DebtWithdrawn {
                            user: borrower, amount_usd_8: debt_amount_usd_8, health_factor_wad,
                        },
                    ),
                );
        }

        fn calculate_health_factor(self: @ContractState, user: ContractAddress) -> u128 {
            InternalTrait::_health_factor_wad(self, self.positions.read(user))
        }

        fn get_position(self: @ContractState, user: ContractAddress) -> UserPosition {
            self.positions.read(user)
        }

        fn set_btc_price(ref self: ContractState, btc_price_usd_8: u128) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            assert(btc_price_usd_8 > 0, 'INVALID_PRICE');
            self.btc_price_usd_8.write(btc_price_usd_8);
            self.emit(Event::BtcPriceUpdated(BtcPriceUpdated { price_usd_8: btc_price_usd_8 }));
        }

        fn set_stablecoin(ref self: ContractState, stablecoin: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            assert(stablecoin != starknet::contract_address_const::<0>(), 'INVALID_STABLECOIN');
            self.stablecoin.write(stablecoin);
            self.emit(Event::StablecoinSet(StablecoinSet { stablecoin }));
        }

        fn set_debt_disbursal_mode(ref self: ContractState, mode: u8) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            assert(mode <= 1_u8, 'INVALID_MODE');
            self.debt_disbursal_mode.write(mode);
            self.emit(Event::DebtDisbursalModeUpdated(DebtDisbursalModeUpdated { mode }));
        }

        fn get_btc_price_in_usd(self: @ContractState) -> u128 {
            InternalTrait::_get_btc_price_usd_8(self)
        }

        fn set_price_oracle(ref self: ContractState, oracle: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            self.price_oracle.write(oracle);
            self.emit(Event::PriceOracleSet(PriceOracleSet { oracle }));
        }

        fn set_ltv_proof_verifier(ref self: ContractState, verifier: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            self.ltv_proof_verifier.write(verifier);
            self.emit(Event::LtvProofVerifierSet(LtvProofVerifierSet { verifier }));
        }

        fn verify_ltv_proof(
            self: @ContractState,
            user: ContractAddress,
            debt_amount_usd_8: u128,
            proof: Span<felt252>,
        ) -> bool {
            InternalTrait::_verify_private_ltv(self, user, debt_amount_usd_8, proof)
        }

        fn withdraw_debt_private(
            ref self: ContractState, debt_amount_usd_8: u128, proof: Span<felt252>,
        ) {
            assert(debt_amount_usd_8 > 0, 'ZERO_DEBT');

            let borrower = get_caller_address();
            assert(
                InternalTrait::_verify_private_ltv(@self, borrower, debt_amount_usd_8, proof),
                'INVALID_PRIVATE_LTV_PROOF',
            );

            let mut position = self.positions.read(borrower);
            let new_debt = position.debt_usd_8 + debt_amount_usd_8;
            position.debt_usd_8 = new_debt;
            self.positions.write(borrower, position);

            InternalTrait::_disburse_debt(ref self, borrower, debt_amount_usd_8);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _max_borrowable_usd_8_from_collateral(
            self: @ContractState, collateral_sats: u128,
        ) -> u128 {
            let collateral_value_usd_8 = collateral_sats
                * InternalTrait::_get_btc_price_usd_8(self)
                / SATS_PER_BTC;
            collateral_value_usd_8 * self.max_ltv_bps.read().into() / BPS_DENOMINATOR
        }

        fn _health_factor_wad(self: @ContractState, position: UserPosition) -> u128 {
            if position.debt_usd_8 == 0 {
                return NO_DEBT_HEALTH_FACTOR;
            }

            let collateral_value_usd_8 = position.collateral_sats
                * InternalTrait::_get_btc_price_usd_8(self)
                / SATS_PER_BTC;
            let liquidation_adjusted_collateral = collateral_value_usd_8
                * self.liquidation_threshold_bps.read().into()
                / BPS_DENOMINATOR;

            liquidation_adjusted_collateral * WAD / position.debt_usd_8
        }

        fn _get_btc_price_usd_8(self: @ContractState) -> u128 {
            let oracle_address = self.price_oracle.read();
            if oracle_address == starknet::contract_address_const::<0>() {
                return self.btc_price_usd_8.read();
            }

            let oracle = IPriceOracleDispatcher { contract_address: oracle_address };
            oracle.get_btc_usd_price()
        }

        fn _verify_private_ltv(
            self: @ContractState,
            user: ContractAddress,
            debt_amount_usd_8: u128,
            proof: Span<felt252>,
        ) -> bool {
            let verifier_address = self.ltv_proof_verifier.read();
            if verifier_address == starknet::contract_address_const::<0>() {
                return false;
            }

            let position = self.positions.read(user);
            if position.encrypted_position_commitment == 0 {
                return false;
            }

            let debt_after = position.debt_usd_8 + debt_amount_usd_8;
            let price = InternalTrait::_get_btc_price_usd_8(self);
            let public_input_hash = InternalTrait::_private_ltv_public_input_hash(
                self, user, position.encrypted_position_commitment, debt_after, price,
            );

            let verifier = ILtvProofVerifierDispatcher { contract_address: verifier_address };
            verifier.verify_ltv_proof(user, public_input_hash, proof)
        }

        fn _private_ltv_public_input_hash(
            self: @ContractState,
            user: ContractAddress,
            encrypted_commitment: felt252,
            debt_after_usd_8: u128,
            btc_price_usd_8: u128,
        ) -> felt252 {
            // Keep this hash in sync with the off-chain Garaga/STARK circuit public inputs.
            user.into()
                + encrypted_commitment
                + debt_after_usd_8.into()
                + btc_price_usd_8.into()
                + MIN_PRIVATE_LTV_WAD.into()
        }

        fn _disburse_debt(ref self: ContractState, borrower: ContractAddress, amount_usd_8: u128) {
            let stablecoin = IStablecoinDispatcher { contract_address: self.stablecoin.read() };
            let amount = u256 { low: amount_usd_8, high: 0 };

            if self.debt_disbursal_mode.read() == 0_u8 {
                stablecoin.mint(borrower, amount);
                return;
            }

            let transferred = stablecoin.transfer(borrower, amount);
            assert(transferred, 'TRANSFER_FAILED');
        }
    }
}
