#[starknet::contract]
mod MockPriceOracle {
    use crate::interfaces::{IMockPriceOracleAdmin, IPriceOracle};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        price: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_price: u128) {
        self.price.write(initial_price);
    }

    #[abi(embed_v0)]
    impl MockPriceOracleAdminImpl of IMockPriceOracleAdmin<ContractState> {
        fn set_price(ref self: ContractState, price: u128) {
            self.price.write(price);
        }
    }

    #[abi(embed_v0)]
    impl MockPriceOracleImpl of IPriceOracle<ContractState> {
        fn get_btc_usd_price(self: @ContractState) -> u128 {
            self.price.read()
        }
    }
}
