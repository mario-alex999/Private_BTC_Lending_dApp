#[starknet::contract]
mod GaragaInequalityVerifierAdapter {
    use crate::interfaces::{
        IGaragaInequalityVerifierAdapterAdmin, IGaragaVerifierDispatcher,
        IGaragaVerifierDispatcherTrait, ILtvProofVerifier,
    };
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        garaga_verifier: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, garaga_verifier: ContractAddress,
    ) {
        assert(owner != starknet::contract_address_const::<0>(), 'INVALID_OWNER');
        assert(garaga_verifier != starknet::contract_address_const::<0>(), 'INVALID_VERIFIER');
        self.owner.write(owner);
        self.garaga_verifier.write(garaga_verifier);
    }

    #[abi(embed_v0)]
    impl GaragaInequalityVerifierAdapterAdminImpl of IGaragaInequalityVerifierAdapterAdmin<
        ContractState,
    > {
        fn set_garaga_verifier(ref self: ContractState, verifier: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            assert(verifier != starknet::contract_address_const::<0>(), 'INVALID_VERIFIER');
            self.garaga_verifier.write(verifier);
        }
    }

    #[abi(embed_v0)]
    impl GaragaInequalityVerifierAdapterImpl of ILtvProofVerifier<ContractState> {
        fn verify_ltv_proof(
            self: @ContractState,
            user: ContractAddress,
            public_input_hash: felt252,
            proof: Span<felt252>,
        ) -> bool {
            let mut public_inputs = ArrayTrait::new();
            public_inputs.append(user.into());
            public_inputs.append(public_input_hash);

            let verifier = IGaragaVerifierDispatcher {
                contract_address: self.garaga_verifier.read(),
            };
            verifier.verify(proof, public_inputs.span())
        }
    }
}
