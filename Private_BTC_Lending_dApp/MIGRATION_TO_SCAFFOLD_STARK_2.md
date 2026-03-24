# Migration Plan: Starknet-Scaffold -> scaffold-stark-2

This repo is deprecated. Use this guide to move the Private BTC Lending app into `scaffold-stark-2`.

## 1) Bootstrap scaffold-stark-2

```bash
npm run scaffold2:init
```

This clones:

- `https://github.com/Scaffold-Stark/scaffold-stark-2.git`
- Into: `./scaffold-stark-2`

## 2) Export current contracts and env

```bash
npm run scaffold2:migrate
```

This performs:

- Contracts export from `contracts/src` to target `migrations/private_btc_lending/src`
- Tests export from `contracts/tests` to target `migrations/private_btc_lending/tests`
- `Scarb.toml` snapshot export
- `.env` Starknet snapshot export (`.env.migration`)

## 3) Integrate into scaffold-stark-2 workspace

After export, open the target and move only the modules you want into the active contract package used by scaffold-stark-2.

Recommended order:

1. `interfaces.cairo`, `types.cairo`
2. `herodotus_fact_registry_adapter.cairo`
3. `garaga_inequality_verifier_adapter.cairo`
4. `lending_pool.cairo`

Then update module exports (`lib.cairo`) and dependency versions.

## 4) Re-wire frontend/env

Map `.env.migration` values into scaffold-stark-2 frontend env files and deployment config.

Pay attention to:

- `NEXT_PUBLIC_LENDING_POOL_ADDRESS`
- `NEXT_PUBLIC_STARKNET_RPC_URL`
- verifier/oracle addresses

## 5) Validate

Run build/test inside scaffold-stark-2 after integration.

---

## Script reference

The helper script is:

- `scripts/migrate_to_scaffold_stark_2.sh`

Show options:

```bash
bash scripts/migrate_to_scaffold_stark_2.sh --help
```
