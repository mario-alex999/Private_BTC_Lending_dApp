#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT_DIR/scaffold-stark-2"
REPO_URL="https://github.com/Scaffold-Stark/scaffold-stark-2.git"
CLONE_ONLY=false
COPY_CONTRACTS=false
COPY_ENV=false

print_help() {
  cat <<USAGE
Usage: scripts/migrate_to_scaffold_stark_2.sh [options]

Options:
  --target <path>       Target directory for scaffold-stark-2 clone.
  --clone-only          Clone scaffold-stark-2 without copying project files.
  --copy-contracts      Copy contracts from this repo into target migration folder.
  --copy-env            Export Starknet env values into target migration snapshot.
  -h, --help            Show help.

Examples:
  bash scripts/migrate_to_scaffold_stark_2.sh --clone-only
  bash scripts/migrate_to_scaffold_stark_2.sh --copy-contracts --copy-env
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is required but not installed."
    exit 1
  fi
}

find_target_contracts_dir() {
  local target="$1"
  if [[ -d "$target/packages/snfoundry/contracts" ]]; then
    echo "$target/packages/snfoundry/contracts"
    return
  fi

  if [[ -d "$target/packages/contracts" ]]; then
    echo "$target/packages/contracts"
    return
  fi

  echo "$target/contracts_import"
}

copy_contracts() {
  local target="$1"
  local contracts_dir
  contracts_dir="$(find_target_contracts_dir "$target")"

  mkdir -p "$contracts_dir/migrations/private_btc_lending/src"
  mkdir -p "$contracts_dir/migrations/private_btc_lending/tests"

  cp -R "$ROOT_DIR/contracts/src/." "$contracts_dir/migrations/private_btc_lending/src/"
  cp -R "$ROOT_DIR/contracts/tests/." "$contracts_dir/migrations/private_btc_lending/tests/"

  if [[ -f "$ROOT_DIR/contracts/Scarb.toml" ]]; then
    cp "$ROOT_DIR/contracts/Scarb.toml" "$contracts_dir/migrations/private_btc_lending/Scarb.toml"
  fi

  cat > "$contracts_dir/migrations/private_btc_lending/README.md" <<README
This folder contains contracts migrated from Private_BTC_Lending_dApp.

Next step:
1. Move selected modules into scaffold-stark-2's active contract workspace.
2. Reconcile dependencies and package layout.
3. Rebuild with the target scaffold tooling.
README

  echo "Copied contracts into: $contracts_dir/migrations/private_btc_lending"
}

copy_env_snapshot() {
  local target="$1"
  mkdir -p "$target/migrations/private_btc_lending"

  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    echo "No .env found at project root. Skipping env snapshot."
    return
  fi

  {
    echo "# Snapshot exported from Private_BTC_Lending_dApp"
    echo "# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Review carefully before using in production"
    grep -E '^(STARKNET_|LENDING_POOL_ADDRESS|STABLECOIN_ADDRESS|BTC_PROOF_VERIFIER_ADDRESS|LTV_PROOF_VERIFIER_ADDRESS|PRAGMA_|HERODOTUS_|GARAGA_|NEXT_PUBLIC_)' "$ROOT_DIR/.env" || true
  } > "$target/migrations/private_btc_lending/.env.migration"

  echo "Created env snapshot: $target/migrations/private_btc_lending/.env.migration"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      shift
      TARGET_DIR="$1"
      ;;
    --clone-only)
      CLONE_ONLY=true
      ;;
    --copy-contracts)
      COPY_CONTRACTS=true
      ;;
    --copy-env)
      COPY_ENV=true
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      print_help
      exit 1
      ;;
  esac
  shift
done

require_cmd git

if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "scaffold-stark-2 already exists at: $TARGET_DIR"
else
  echo "Cloning scaffold-stark-2 into: $TARGET_DIR"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

if [[ "$CLONE_ONLY" == "true" ]]; then
  echo "Clone completed (clone-only mode)."
  exit 0
fi

if [[ "$COPY_CONTRACTS" == "true" ]]; then
  copy_contracts "$TARGET_DIR"
fi

if [[ "$COPY_ENV" == "true" ]]; then
  copy_env_snapshot "$TARGET_DIR"
fi

echo "Migration helper completed."
echo "Target: $TARGET_DIR"
