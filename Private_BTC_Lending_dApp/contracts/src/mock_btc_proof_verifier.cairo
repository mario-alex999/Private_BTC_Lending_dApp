#[starknet::contract]
mod MockBtcProofVerifier {
    use crate::interfaces::{IBtcProofVerifier, IMockBtcProofVerifierAdmin};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        result: bool,
    }

    #[abi(embed_v0)]
    impl MockBtcProofVerifierAdminImpl of IMockBtcProofVerifierAdmin<ContractState> {
        fn set_result(ref self: ContractState, result: bool) {
            self.result.write(result);
        }
    }

    #[abi(embed_v0)]
    impl MockBtcProofVerifierImpl of IBtcProofVerifier<ContractState> {
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
            let _ = (
                borrower, txid, vout, amount_sats, btc_block_height, vault_script_hash, proof_blob,
            );
            self.result.read()
        }
    }
}
