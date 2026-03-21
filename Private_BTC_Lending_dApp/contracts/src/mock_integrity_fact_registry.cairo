#[starknet::contract]
mod MockIntegrityFactRegistry {
    use crate::interfaces::{IIntegrityFactRegistry, IMockIntegrityFactRegistryAdmin};
    use crate::types::VerificationRecord;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        verifications: Map<felt252, VerificationRecord>,
    }

    #[abi(embed_v0)]
    impl MockIntegrityFactRegistryAdminImpl of IMockIntegrityFactRegistryAdmin<ContractState> {
        fn set_verification(
            ref self: ContractState, verification_hash: felt252, record: VerificationRecord,
        ) {
            self.verifications.write(verification_hash, record);
        }
    }

    #[abi(embed_v0)]
    impl MockIntegrityFactRegistryImpl of IIntegrityFactRegistry<ContractState> {
        fn get_verification(
            self: @ContractState, verification_hash: felt252,
        ) -> VerificationRecord {
            self.verifications.read(verification_hash)
        }
    }
}
