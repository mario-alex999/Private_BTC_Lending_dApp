#[starknet::contract]
mod HerodotusFactRegistryAdapter {
    use core::array::SpanTrait;

    use crate::interfaces::{
        IBtcProofVerifier, IHerodotusFactRegistryAdapterAdmin, IIntegrityFactRegistryDispatcher,
        IIntegrityFactRegistryDispatcherTrait,
    };
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        fact_registry: ContractAddress,
        min_security_bits: u32,
        required_settings: felt252,
        domain_separator: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        fact_registry: ContractAddress,
        min_security_bits: u32,
        required_settings: felt252,
        domain_separator: felt252,
    ) {
        assert(owner != starknet::contract_address_const::<0>(), 'INVALID_OWNER');
        assert(fact_registry != starknet::contract_address_const::<0>(), 'INVALID_REGISTRY');

        self.owner.write(owner);
        self.fact_registry.write(fact_registry);
        self.min_security_bits.write(min_security_bits);
        self.required_settings.write(required_settings);
        self.domain_separator.write(domain_separator);
    }

    #[abi(embed_v0)]
    impl HerodotusFactRegistryAdapterAdminImpl of IHerodotusFactRegistryAdapterAdmin<
        ContractState,
    > {
        fn set_fact_registry(ref self: ContractState, fact_registry: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            assert(fact_registry != starknet::contract_address_const::<0>(), 'INVALID_REGISTRY');
            self.fact_registry.write(fact_registry);
        }

        fn set_min_security_bits(ref self: ContractState, min_security_bits: u32) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            self.min_security_bits.write(min_security_bits);
        }

        fn set_required_settings(ref self: ContractState, required_settings: felt252) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            self.required_settings.write(required_settings);
        }

        fn set_domain_separator(ref self: ContractState, domain_separator: felt252) {
            assert(get_caller_address() == self.owner.read(), 'NOT_OWNER');
            self.domain_separator.write(domain_separator);
        }
    }

    #[abi(embed_v0)]
    impl HerodotusFactRegistryAdapterImpl of IBtcProofVerifier<ContractState> {
        fn verify_deposit_proof(
            self: @ContractState,
            borrower: ContractAddress,
            txid: felt252,
            vout: u32,
            amount_sats: u128,
            btc_block_height: u64,
            vault_script_hash: felt252,
            proof_blob: Span<felt252>,
        ) -> bool {
            assert(proof_blob.len() >= 3, 'PROOF_BLOB_TOO_SHORT');

            let verification_hash = *proof_blob.at(0);
            let supplied_settings = *proof_blob.at(1);
            let expected_fact_hash = *proof_blob.at(2);

            let derived_fact_hash = InternalTrait::_derive_fact_hash(
                self, borrower, txid, vout, amount_sats, btc_block_height, vault_script_hash,
            );
            assert(derived_fact_hash == expected_fact_hash, 'FACT_BINDING_FAIL');

            let fact_registry = IIntegrityFactRegistryDispatcher {
                contract_address: self.fact_registry.read(),
            };
            let verification = fact_registry.get_verification(verification_hash);

            assert(verification.fact_hash == expected_fact_hash, 'FACT_HASH_MISMATCH');
            assert(
                verification.security_bits >= self.min_security_bits.read(), 'LOW_SECURITY_BITS',
            );
            assert(verification.settings == supplied_settings, 'SETTINGS_MISMATCH');
            assert(verification.settings == self.required_settings.read(), 'UNAPPROVED_SETTINGS');

            true
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _derive_fact_hash(
            self: @ContractState,
            borrower: ContractAddress,
            txid: felt252,
            vout: u32,
            amount_sats: u128,
            btc_block_height: u64,
            vault_script_hash: felt252,
        ) -> felt252 {
            txid
                + vout.into()
                + amount_sats.into()
                + btc_block_height.into()
                + vault_script_hash
                + borrower.into()
                + self.domain_separator.read()
        }
    }
}
