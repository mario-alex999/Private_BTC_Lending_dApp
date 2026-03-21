#[starknet::contract]
mod MockStablecoin {
    use core::integer::u256;

    use crate::interfaces::IStablecoin;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
    }

    #[abi(embed_v0)]
    impl MockStablecoinImpl of IStablecoin<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let current = self.balances.read(recipient);
            self.balances.write(recipient, current + amount);
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            let sender_balance = self.balances.read(sender);

            if sender_balance < amount {
                return false;
            }

            let recipient_balance = self.balances.read(recipient);
            self.balances.write(sender, sender_balance - amount);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }
    }
}
