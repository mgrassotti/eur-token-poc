#!/usr/bin/env bash
# Per-boot startup for the MAT PoC Cloud Agent environment.
# Starts the Docker daemon, brings up the regtest/DLC stack, and makes sure the
# development database is migrated and seeded. Idempotent and safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

echo "== Docker daemon =="
source .cursor/docker-up.sh

echo "== Regtest / DLC stack (bitcoind, electrs, Pythia oracle, dlc-node) =="
docker compose -f docker-compose.regtest.yml --profile dlc up -d

wait_for_bitcoind

echo "== Development database (migrate + seed if empty) =="
bin/rails db:prepare

echo "== Environment ready — Rails is launched in the 'rails' terminal =="
