#[starknet::contract]
mod PragmaOracleAdapter {
    use crate::interfaces::{
        IPragmaOracleAdapterAdmin, IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait,
        IPriceOracle,
    };
    use crate::types::DataType;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        pragma_oracle: ContractAddress,
        pair_id: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        pragma_oracle: ContractAddress,
        pair_id: felt252,
    ) {
        assert(owner != starknet::contract_address_const::<0>(), 'INVALID_OWNER');
        assert(pragma_oracle != starknet::contract_address_const::<0>(), 'INVALID_ORACLE');
        self.owner.write(owner);
        self.pragma_oracle.write(pragma_oracle);
        self.pair_id.write(pair_id);
    }

    #[abi(embed_v0)]
    impl PragmaOracleAdapterAdminImpl of IPragmaOracleAdapterAdmin<ContractState> {
        fn set_pragma_oracle(ref self: ContractState, pragma_oracle: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            assert(pragma_oracle != starknet::contract_address_const::<0>(), 'INVALID_ORACLE');
            self.pragma_oracle.write(pragma_oracle);
        }

        fn set_pair_id(ref self: ContractState, pair_id: felt252) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            self.pair_id.write(pair_id);
        }
    }

    #[abi(embed_v0)]
    impl PragmaOracleAdapterImpl of IPriceOracle<ContractState> {
        fn get_btc_usd_price(self: @ContractState) -> u128 {
            let oracle = IPragmaOracleDispatcher { contract_address: self.pragma_oracle.read() };
            let output = oracle.get_data_median(DataType::SpotEntry(self.pair_id.read()));
            output.price
        }
    }
}
