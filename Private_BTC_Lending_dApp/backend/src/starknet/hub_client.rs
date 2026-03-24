use anyhow::Result;
use serde_json::Value;
use uuid::Uuid;

#[derive(Clone)]
pub struct HubClient {
    rpc_url: String,
    contract_address: String,
}

impl HubClient {
    pub fn new(rpc_url: String, contract_address: String) -> Self {
        Self {
            rpc_url,
            contract_address,
        }
    }

    pub async fn freeze_deposit(&self, deposit_id: &str) -> Result<()> {
        let _ = (&self.rpc_url, &self.contract_address, deposit_id);
        // TODO: invoke `freeze_deposit(deposit_id, true)` on hub contract.
        Ok(())
    }

    pub async fn freeze_chain(&self, chain_id: u64) -> Result<()> {
        let _ = (&self.rpc_url, &self.contract_address, chain_id);
        // TODO: invoke `freeze_chain(chain_id, true)` on hub contract.
        Ok(())
    }

    pub async fn submit_proof_relay(
        &self,
        chain_id: u64,
        asset_id: u16,
        public_input_hash: &str,
        proof_payload: &Value,
        calldata: &Value,
        target_contract: &str,
    ) -> Result<String> {
        let _ = (
            &self.rpc_url,
            &self.contract_address,
            chain_id,
            asset_id,
            public_input_hash,
            proof_payload,
            calldata,
            target_contract,
        );

        // TODO: replace with starknet RPC `addInvokeTransaction` call.
        Ok(format!("0x{}", Uuid::new_v4().simple()))
    }
}
