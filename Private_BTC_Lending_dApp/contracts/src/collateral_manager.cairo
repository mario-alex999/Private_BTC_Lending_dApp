use starknet::ContractAddress;

#[derive(Copy, Drop, Serde)]
pub enum CollateralType {
    Bitcoin: (),
    Ethereum: (),
    BNB: (),
    XRP: (),
    Solana: (),
    Tron: (),
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct OracleFeed {
    pub provider: u8,
    pub oracle: ContractAddress,
    pub feed_id: felt252,
    pub feed_decimals: u8,
    pub is_active: bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct RiskParams {
    pub max_ltv_bps: u16,
    pub liquidation_threshold_bps: u16,
    pub chain_debt_ceiling_usd_18: u128,
    pub is_active: bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ChainSecurityConfig {
    pub min_confirmations: u32,
    pub freeze_on_reorg: bool,
    pub is_active: bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Position {
    pub collateral_amount_18: u128,
    pub debt_usd_18: u128,
    pub commitment: felt252,
}

#[starknet::interface]
pub trait ICrossChainDepositVerifier<TContractState> {
    fn verify_deposit(
        self: @TContractState,
        chain_id: u64,
        asset_id: u8,
        user: ContractAddress,
        deposit_id: felt252,
        amount_native_18: u128,
        proof_payload: Span<felt252>,
    ) -> bool;
}

#[starknet::interface]
pub trait IPragmaSpotFeed<TContractState> {
    fn get_spot_price(self: @TContractState, feed_id: felt252) -> u128;
}

#[starknet::interface]
pub trait IPythSpotFeed<TContractState> {
    fn get_price_unsafe(self: @TContractState, feed_id: felt252) -> u128;
}

#[starknet::interface]
pub trait ILtvProofVerifierV2<TContractState> {
    fn verify_ltv_proof(
        self: @TContractState,
        user: ContractAddress,
        public_input_hash: felt252,
        proof: Span<felt252>,
    ) -> bool;
}

#[starknet::interface]
pub trait ICollateralManager<TContractState> {
    fn set_chain_verifier(ref self: TContractState, chain_id: u64, verifier: ContractAddress);
    fn set_chain_security(
        ref self: TContractState,
        chain_id: u64,
        min_confirmations: u32,
        freeze_on_reorg: bool,
        is_active: bool,
    );
    fn set_oracle_feed(
        ref self: TContractState,
        asset: CollateralType,
        provider: u8,
        oracle: ContractAddress,
        feed_id: felt252,
        feed_decimals: u8,
        is_active: bool,
    );
    fn set_risk_params(ref self: TContractState, asset: CollateralType, params: RiskParams);
    fn set_ltv_proof_verifier(ref self: TContractState, verifier: ContractAddress);
    fn freeze_chain(ref self: TContractState, chain_id: u64, frozen: bool);
    fn freeze_deposit(ref self: TContractState, deposit_id: felt252, frozen: bool);
    fn verify_cross_chain_deposit(
        ref self: TContractState,
        chain_id: u64,
        asset: CollateralType,
        deposit_id: felt252,
        amount_native_18: u128,
        starknet_user: ContractAddress,
        confirmation_depth: u32,
        proof_payload: Span<felt252>,
        commitment: felt252,
    );
    fn borrow(
        ref self: TContractState,
        chain_id: u64,
        asset: CollateralType,
        debt_to_add_usd_18: u128,
        proof: Span<felt252>,
    );
    fn get_price_18(self: @TContractState, asset: CollateralType) -> u128;
    fn get_health_factor_wad(
        self: @TContractState,
        user: ContractAddress,
        chain_id: u64,
        asset: CollateralType,
    ) -> u128;
}

#[starknet::contract]
mod CollateralManager {
    use super::{
        ChainSecurityConfig, CollateralType, ICollateralManager,
        ICrossChainDepositVerifierDispatcher, ICrossChainDepositVerifierDispatcherTrait,
        ILtvProofVerifierV2Dispatcher, ILtvProofVerifierV2DispatcherTrait,
        IPythSpotFeedDispatcher, IPythSpotFeedDispatcherTrait,
        IPragmaSpotFeedDispatcher, IPragmaSpotFeedDispatcherTrait, OracleFeed, Position,
        RiskParams,
    };
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    const WAD: u128 = 1_000_000_000_000_000_000;
    const BPS_DENOMINATOR: u128 = 10_000;
    const NO_DEBT_HEALTH_FACTOR: u128 = 1_000_000_000_000_000_000_000_000;
    const PROVIDER_PRAGMA: u8 = 1;
    const PROVIDER_PYTH: u8 = 2;
    const LTV_PROOF_DOMAIN_SEPARATOR: felt252 = 0x4d554c54495f4c54565f4831;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        ltv_proof_verifier: ContractAddress,
        chain_verifier: Map<u64, ContractAddress>,
        chain_security: Map<u64, ChainSecurityConfig>,
        chain_frozen: Map<u64, bool>,
        frozen_deposits: Map<felt252, bool>,
        risk_params: Map<u8, RiskParams>,
        oracle_feeds: Map<u8, OracleFeed>,
        chain_backed_debt_usd_18: Map<u64, u128>,
        positions: Map<(ContractAddress, u64, u8), Position>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DepositVerified: DepositVerified,
        Borrowed: Borrowed,
        ChainFrozen: ChainFrozen,
        DepositFrozen: DepositFrozen,
        ChainVerifierSet: ChainVerifierSet,
        ChainSecuritySet: ChainSecuritySet,
        OracleFeedSet: OracleFeedSet,
        RiskParamsSet: RiskParamsSet,
        LtvProofVerifierSet: LtvProofVerifierSet,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositVerified {
        #[key]
        user: ContractAddress,
        chain_id: u64,
        asset_id: u8,
        deposit_id: felt252,
        amount_native_18: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrowed {
        #[key]
        user: ContractAddress,
        chain_id: u64,
        asset_id: u8,
        debt_added_usd_18: u128,
        health_factor_wad: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct ChainFrozen {
        chain_id: u64,
        frozen: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositFrozen {
        deposit_id: felt252,
        frozen: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct ChainVerifierSet {
        chain_id: u64,
        verifier: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ChainSecuritySet {
        chain_id: u64,
        min_confirmations: u32,
        freeze_on_reorg: bool,
        is_active: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct OracleFeedSet {
        asset_id: u8,
        provider: u8,
        oracle: ContractAddress,
        feed_id: felt252,
        decimals: u8,
        is_active: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct RiskParamsSet {
        asset_id: u8,
        max_ltv_bps: u16,
        liquidation_threshold_bps: u16,
        chain_debt_ceiling_usd_18: u128,
        is_active: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct LtvProofVerifierSet {
        verifier: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, ltv_verifier: ContractAddress) {
        assert(owner != starknet::contract_address_const::<0>(), 'INVALID_OWNER');
        self.owner.write(owner);
        self.ltv_proof_verifier.write(ltv_verifier);
    }

    #[abi(embed_v0)]
    impl CollateralManagerImpl of ICollateralManager<ContractState> {
        fn set_chain_verifier(ref self: ContractState, chain_id: u64, verifier: ContractAddress) {
            InternalTrait::_only_owner(@self);
            assert(verifier != starknet::contract_address_const::<0>(), 'INVALID_VERIFIER');
            self.chain_verifier.write(chain_id, verifier);
            self.emit(Event::ChainVerifierSet(ChainVerifierSet { chain_id, verifier }));
        }

        fn set_chain_security(
            ref self: ContractState,
            chain_id: u64,
            min_confirmations: u32,
            freeze_on_reorg: bool,
            is_active: bool,
        ) {
            InternalTrait::_only_owner(@self);
            let config = ChainSecurityConfig { min_confirmations, freeze_on_reorg, is_active };
            self.chain_security.write(chain_id, config);
            self
                .emit(
                    Event::ChainSecuritySet(
                        ChainSecuritySet {
                            chain_id,
                            min_confirmations,
                            freeze_on_reorg,
                            is_active,
                        },
                    ),
                );
        }

        fn set_oracle_feed(
            ref self: ContractState,
            asset: CollateralType,
            provider: u8,
            oracle: ContractAddress,
            feed_id: felt252,
            feed_decimals: u8,
            is_active: bool,
        ) {
            InternalTrait::_only_owner(@self);
            assert(oracle != starknet::contract_address_const::<0>(), 'INVALID_ORACLE');
            assert(provider == PROVIDER_PRAGMA || provider == PROVIDER_PYTH, 'BAD_PROVIDER');

            let asset_id = InternalTrait::_asset_id(asset);
            let feed = OracleFeed { provider, oracle, feed_id, feed_decimals, is_active };
            self.oracle_feeds.write(asset_id, feed);
            self
                .emit(
                    Event::OracleFeedSet(
                        OracleFeedSet {
                            asset_id,
                            provider,
                            oracle,
                            feed_id,
                            decimals: feed_decimals,
                            is_active,
                        },
                    ),
                );
        }

        fn set_risk_params(ref self: ContractState, asset: CollateralType, params: RiskParams) {
            InternalTrait::_only_owner(@self);
            assert(params.max_ltv_bps > 0, 'ZERO_MAX_LTV');
            assert(params.liquidation_threshold_bps >= params.max_ltv_bps, 'LTV_GT_LT');
            assert(params.liquidation_threshold_bps <= 10_000_u16, 'LT_TOO_HIGH');

            let asset_id = InternalTrait::_asset_id(asset);
            self.risk_params.write(asset_id, params);
            self
                .emit(
                    Event::RiskParamsSet(
                        RiskParamsSet {
                            asset_id,
                            max_ltv_bps: params.max_ltv_bps,
                            liquidation_threshold_bps: params.liquidation_threshold_bps,
                            chain_debt_ceiling_usd_18: params.chain_debt_ceiling_usd_18,
                            is_active: params.is_active,
                        },
                    ),
                );
        }

        fn set_ltv_proof_verifier(ref self: ContractState, verifier: ContractAddress) {
            InternalTrait::_only_owner(@self);
            self.ltv_proof_verifier.write(verifier);
            self.emit(Event::LtvProofVerifierSet(LtvProofVerifierSet { verifier }));
        }

        fn freeze_chain(ref self: ContractState, chain_id: u64, frozen: bool) {
            InternalTrait::_only_owner(@self);
            self.chain_frozen.write(chain_id, frozen);
            self.emit(Event::ChainFrozen(ChainFrozen { chain_id, frozen }));
        }

        fn freeze_deposit(ref self: ContractState, deposit_id: felt252, frozen: bool) {
            InternalTrait::_only_owner(@self);
            self.frozen_deposits.write(deposit_id, frozen);
            self.emit(Event::DepositFrozen(DepositFrozen { deposit_id, frozen }));
        }

        fn verify_cross_chain_deposit(
            ref self: ContractState,
            chain_id: u64,
            asset: CollateralType,
            deposit_id: felt252,
            amount_native_18: u128,
            starknet_user: ContractAddress,
            confirmation_depth: u32,
            proof_payload: Span<felt252>,
            commitment: felt252,
        ) {
            assert(amount_native_18 > 0, 'ZERO_DEPOSIT');
            assert(!self.frozen_deposits.read(deposit_id), 'DEPOSIT_FROZEN');
            assert(!self.chain_frozen.read(chain_id), 'CHAIN_FROZEN');

            let config = self.chain_security.read(chain_id);
            assert(config.is_active, 'CHAIN_DISABLED');
            assert(confirmation_depth >= config.min_confirmations, 'INSUFFICIENT_FINALITY');

            let asset_id = InternalTrait::_asset_id(asset);
            let verifier = ICrossChainDepositVerifierDispatcher {
                contract_address: self.chain_verifier.read(chain_id),
            };
            let is_valid = verifier
                .verify_deposit(
                    chain_id,
                    asset_id,
                    starknet_user,
                    deposit_id,
                    amount_native_18,
                    proof_payload,
                );
            assert(is_valid, 'INVALID_CROSS_CHAIN_PROOF');

            let key = (starknet_user, chain_id, asset_id);
            let mut position = self.positions.read(key);
            position.collateral_amount_18 = position.collateral_amount_18 + amount_native_18;
            position.commitment = commitment;
            self.positions.write(key, position);

            self
                .emit(
                    Event::DepositVerified(
                        DepositVerified {
                            user: starknet_user,
                            chain_id,
                            asset_id,
                            deposit_id,
                            amount_native_18,
                        },
                    ),
                );
        }

        fn borrow(
            ref self: ContractState,
            chain_id: u64,
            asset: CollateralType,
            debt_to_add_usd_18: u128,
            proof: Span<felt252>,
        ) {
            assert(debt_to_add_usd_18 > 0, 'ZERO_DEBT');
            assert(!self.chain_frozen.read(chain_id), 'CHAIN_FROZEN');

            let user = get_caller_address();
            let asset_id = InternalTrait::_asset_id(asset);
            let key = (user, chain_id, asset_id);
            let mut position = self.positions.read(key);
            assert(position.collateral_amount_18 > 0, 'NO_COLLATERAL');

            let params = self.risk_params.read(asset_id);
            assert(params.is_active, 'ASSET_DISABLED');

            let price_18 = InternalTrait::_get_price_18(@self, asset_id);
            let collateral_usd_18 = position.collateral_amount_18 * price_18 / WAD;

            let new_debt = position.debt_usd_18 + debt_to_add_usd_18;
            let max_borrowable = collateral_usd_18 * params.max_ltv_bps.into() / BPS_DENOMINATOR;
            assert(new_debt <= max_borrowable, 'ABOVE_MAX_LTV');

            let public_input_hash = InternalTrait::_ltv_public_input_hash(
                @self, user, chain_id, asset_id, position.commitment, new_debt, price_18,
            );
            let verifier = ILtvProofVerifierV2Dispatcher {
                contract_address: self.ltv_proof_verifier.read(),
            };
            assert(verifier.verify_ltv_proof(user, public_input_hash, proof), 'INVALID_LTV_PROOF');

            let chain_backed_after = self.chain_backed_debt_usd_18.read(chain_id) + debt_to_add_usd_18;
            assert(chain_backed_after <= params.chain_debt_ceiling_usd_18, 'CHAIN_DEBT_CEILING');

            position.debt_usd_18 = new_debt;
            self.positions.write(key, position);
            self.chain_backed_debt_usd_18.write(chain_id, chain_backed_after);

            let health_factor = InternalTrait::_health_factor_wad(@self, position, params, price_18);
            self
                .emit(
                    Event::Borrowed(
                        Borrowed {
                            user,
                            chain_id,
                            asset_id,
                            debt_added_usd_18: debt_to_add_usd_18,
                            health_factor_wad: health_factor,
                        },
                    ),
                );
        }

        fn get_price_18(self: @ContractState, asset: CollateralType) -> u128 {
            let asset_id = InternalTrait::_asset_id(asset);
            InternalTrait::_get_price_18(self, asset_id)
        }

        fn get_health_factor_wad(
            self: @ContractState,
            user: ContractAddress,
            chain_id: u64,
            asset: CollateralType,
        ) -> u128 {
            let asset_id = InternalTrait::_asset_id(asset);
            let params = self.risk_params.read(asset_id);
            let price_18 = InternalTrait::_get_price_18(self, asset_id);
            let position = self.positions.read((user, chain_id, asset_id));
            InternalTrait::_health_factor_wad(self, position, params, price_18)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _only_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
        }

        fn _asset_id(asset: CollateralType) -> u8 {
            match asset {
                CollateralType::Bitcoin(_) => 0_u8,
                CollateralType::Ethereum(_) => 1_u8,
                CollateralType::BNB(_) => 2_u8,
                CollateralType::XRP(_) => 3_u8,
                CollateralType::Solana(_) => 4_u8,
                CollateralType::Tron(_) => 5_u8,
            }
        }

        fn _pow10(exp: u8) -> u128 {
            let mut out = 1_u128;
            let mut i = 0_u8;
            loop {
                if i == exp {
                    break;
                }
                out = out * 10;
                i = i + 1_u8;
            };
            out
        }

        fn _normalize_to_18(price: u128, decimals: u8) -> u128 {
            if decimals == 18_u8 {
                return price;
            }

            if decimals < 18_u8 {
                let diff = 18_u8 - decimals;
                return price * Self::_pow10(diff);
            }

            let diff = decimals - 18_u8;
            price / Self::_pow10(diff)
        }

        fn _get_price_18(self: @ContractState, asset_id: u8) -> u128 {
            let feed = self.oracle_feeds.read(asset_id);
            assert(feed.is_active, 'ORACLE_DISABLED');

            if feed.provider == PROVIDER_PRAGMA {
                let oracle = IPragmaSpotFeedDispatcher { contract_address: feed.oracle };
                let price = oracle.get_spot_price(feed.feed_id);
                return Self::_normalize_to_18(price, feed.feed_decimals);
            }

            if feed.provider == PROVIDER_PYTH {
                let oracle = IPythSpotFeedDispatcher { contract_address: feed.oracle };
                let price = oracle.get_price_unsafe(feed.feed_id);
                return Self::_normalize_to_18(price, feed.feed_decimals);
            }

            assert(feed.provider == PROVIDER_PRAGMA || feed.provider == PROVIDER_PYTH, 'UNKNOWN_PROVIDER');
            0_u128
        }

        fn _health_factor_wad(
            self: @ContractState, position: Position, params: RiskParams, price_18: u128,
        ) -> u128 {
            let _ = self;
            if position.debt_usd_18 == 0 {
                return NO_DEBT_HEALTH_FACTOR;
            }

            let collateral_usd_18 = position.collateral_amount_18 * price_18 / WAD;
            let adjusted = collateral_usd_18 * params.liquidation_threshold_bps.into()
                / BPS_DENOMINATOR;
            adjusted * WAD / position.debt_usd_18
        }

        fn _ltv_public_input_hash(
            self: @ContractState,
            user: ContractAddress,
            chain_id: u64,
            asset_id: u8,
            commitment: felt252,
            debt_usd_18: u128,
            price_18: u128,
        ) -> felt252 {
            let _ = self;
            user.into()
                + chain_id.into()
                + asset_id.into()
                + commitment
                + debt_usd_18.into()
                + price_18.into()
                + LTV_PROOF_DOMAIN_SEPARATOR
        }
    }
}
