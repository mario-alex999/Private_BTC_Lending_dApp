#[starknet::contract]
mod MockGaragaVerifier {
    use crate::interfaces::{IGaragaVerifier, IMockGaragaVerifierAdmin};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        result: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_result: bool) {
        self.result.write(initial_result);
    }

    #[abi(embed_v0)]
    impl MockGaragaVerifierAdminImpl of IMockGaragaVerifierAdmin<ContractState> {
        fn set_result(ref self: ContractState, result: bool) {
            self.result.write(result);
        }
    }

    #[abi(embed_v0)]
    impl MockGaragaVerifierImpl of IGaragaVerifier<ContractState> {
        fn verify(
            self: @ContractState, proof: Span<felt252>, public_inputs: Span<felt252>,
        ) -> bool {
            let _ = (proof, public_inputs);
            self.result.read()
        }
    }
}
