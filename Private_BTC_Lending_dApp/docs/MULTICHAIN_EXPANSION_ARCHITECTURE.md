# Multi-Chain Collateral Expansion Architecture

## Scope

Starknet Hub accepts collateral proven from: Ethereum, BNB, Solana, XRP, TRON, and Bitcoin.

## Hub (Starknet / Cairo)

Core components:

- `CollateralManager` (chain-agnostic collateral ledger)
- `Price Oracle Registry` (Pragma + Pyth normalization to `1e18`)
- `Cross-chain Verifier Router` (per-chain proof/message verifier)
- `Risk Engine` (per-asset LTV/LT and per-chain debt ceiling)
- `Reorg Freeze Controls` (`freeze_deposit`, `freeze_chain`)

## Finality Policy

Recommended minimum confirmation policy (configurable in `chain_security`):

- Ethereum: 64 slots (~2 epochs) for high-value borrow limits
- BNB: 15-30 blocks depending on relayer SLA
- Solana: finalized commitment (plus light-client inclusion proof)
- XRP: validated ledger + destination-tag validity
- TRON: 19-27 block window + relayer quorum attestation

If a backend reorg watcher detects reorg depth beyond policy, Hub should freeze the affected deposit or entire chain debt line until manual/operator review.

## Oracle Registry Normalization

- Pragma (ETH/BNB): feed decimals normalized to `1e18`
- Pyth (SOL/XRP): feed decimals normalized to `1e18`
- Any oracle source is converted with:
  - if decimals < 18: multiply by `10^(18-decimals)`
  - if decimals > 18: divide by `10^(decimals-18)`

## Privacy Consistency

ZK-LTV public input hash always includes:

- `user`
- `chain_id`
- `asset_id`
- `position_commitment`
- `debt_after`
- `price_18`
- `domain_separator`

This keeps the same LTV proof semantics regardless of source chain while preventing replay between chains/assets.

## Global Debt Ceiling / Contagion Controls

- Per-asset max LTV and liquidation threshold
- Per-chain debt ceiling (`chain_backed_debt_usd_18 <= chain_debt_ceiling_usd_18`)
- Emergency freeze controls:
  - `freeze_chain(chain_id, true)`
  - `freeze_deposit(deposit_id, true)`

## Backend Services

- `CrossChainIndexer` listens for spoke lock events
- `HerodotusClient` requests proof generation
- `WitnessAPI` serves witness payloads for local proof generation
- `ReorgWatcher` verifies canonicality and freezes affected debt lines if needed
- `WebSocketNotifier` pushes finality and freeze events to frontend
